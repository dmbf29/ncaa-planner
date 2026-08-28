module Api
  module V1
    class GamesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      skip_before_action :authenticate_user!, only: :show
      before_action :set_game

      SECTION_ATTACHMENTS = {
        "box_score" => :box_score_screenshots,
        "home" => :home_stat_screenshots,
        "away" => :away_stat_screenshots
      }.freeze

      # Public, unauthenticated — the game show page is part of the shareable
      # dynasty portal, same reasoning as DynastyPortalsController. Uploading
      # or editing (analyze/commit below) still requires being the dynasty's
      # owner, enforced by GamePolicy.
      def show
        render json: game_json
      end

      def analyze
        authorize @game
        result = GameStats::ExtractionService.new(@game).call(
          box_score_files: Array(params[:box_score_images]),
          home_files: Array(params[:home_images]),
          away_files: Array(params[:away_images])
        )
        render json: analysis_json(result)
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      # Re-runs extraction on a section's already-attached screenshots — no
      # new upload needed — for when the first pass missed something and a
      # retry is worth trying before resorting to manual entry. Reuses the
      # existing blobs (ExtractionService#attach_transient_blobs skips
      # re-uploading anything that's already a Blob), so this never creates
      # duplicate screenshot attachments on commit.
      def reanalyze
        authorize @game
        attachment_name = SECTION_ATTACHMENTS[params[:section]]
        return render json: { error: "invalid section" }, status: :unprocessable_entity unless attachment_name

        blobs = @game.public_send(attachment_name).map(&:blob)
        result = GameStats::ExtractionService.new(@game).call(
          box_score_files: attachment_name == :box_score_screenshots ? blobs : [],
          home_files: attachment_name == :home_stat_screenshots ? blobs : [],
          away_files: attachment_name == :away_stat_screenshots ? blobs : []
        )
        render json: analysis_json(result)
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      # Separate, opt-in step from #analyze — runs the text-only narrative/
      # player-of-the-game AI pass over already-reviewed stats. Skipped
      # entirely for games the user doesn't care to write up (e.g. games
      # for non-user-coached colleges), saving the extra AI call.
      def analyze_narrative
        authorize @game
        payload = analysis_params
        narrative = GameStats::NarrativeSynthesizer.new(home_college: @game.home_college, away_college: @game.away_college)
                                                    .call(college_stats: payload[:college_stats] || [], player_stats: payload[:player_stats] || [])
        render json: { narrative: narrative }
      rescue RubyLLM::Error => e
        render json: { error: "AI analysis failed: #{e.message}", code: "narrative_failed" }, status: :unprocessable_entity
      end

      def commit
        authorize @game
        payload = analysis_params
        GameStats::CommitService.new(@game).call(
          box_score_screenshot_signed_ids: payload[:box_score_screenshot_signed_ids] || [],
          home_screenshot_signed_ids: payload[:home_screenshot_signed_ids] || [],
          away_screenshot_signed_ids: payload[:away_screenshot_signed_ids] || [],
          narrative: payload[:narrative] || {},
          college_stats: payload[:college_stats] || [],
          player_stats: payload[:player_stats] || []
        )
        render json: game_json(reload: true)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_game
        @game = Game.find(params[:id])
      end

      def analysis_params
        params.require(:analysis).to_unsafe_h.deep_symbolize_keys
      end

      def game_json(reload: false)
        @game.reload if reload

        {
          id: @game.id,
          week: { id: @game.week.id, number: @game.week.number },
          home_college: { id: @game.home_college.id, name: @game.home_college.name },
          away_college: { id: @game.away_college.id, name: @game.away_college.name },
          bowl_name: @game.bowl_name,
          cfp_round: @game.cfp_round,
          played: @game.played?,
          box_score_screenshots: screenshots_json(@game.box_score_screenshots),
          home_screenshots: screenshots_json(@game.home_stat_screenshots),
          away_screenshots: screenshots_json(@game.away_stat_screenshots),
          existing_analysis: existing_analysis_json
        }
      end

      def screenshots_json(attachments)
        attachments.map do |screenshot|
          { id: screenshot.id, filename: screenshot.filename.to_s, url: rails_blob_path(screenshot, only_path: true) }
        end
      end

      # Reconstructs a committed game's stats in the exact same shape the
      # `analyze` action produces, so the frontend can feed it straight into
      # the same review/edit form instead of needing a separate "view" mode.
      # nil when there's nothing to reconstruct yet (a never-touched game).
      def existing_analysis_json
        return nil unless @game.played? || @game.box_score_screenshots.attached? || @game.home_stat_screenshots.attached? || @game.away_stat_screenshots.attached?

        {
          college_stats: @game.college_game_stats.includes(:college).map { |stat| existing_college_stat_json(stat) },
          player_stats: existing_player_stats_json,
          narrative: {
            narrative_summary: @game.narrative_summary,
            offense_player_of_game_id: @game.offensive_player_of_game_id,
            offense_player_stat_line: @game.offensive_player_stat_line,
            defense_player_of_game_id: @game.defensive_player_of_game_id,
            defense_player_stat_line: @game.defensive_player_stat_line
          },
          home_roster: GameStats::Roster.for(@game.home_college, @game.week.season),
          away_roster: GameStats::Roster.for(@game.away_college, @game.week.season)
        }
      end

      def existing_college_stat_json(stat)
        { team: stat.college.name, fields: stat.attributes.slice(*GameStats::StatFields::COLLEGE_FIELDS.map(&:to_s)) }
      end

      # A StudentGameStat holds every category's columns on one row (a
      # rushing QB has both passing_* and rushing_* filled in), but the
      # review form expects one row per category — same shape a fresh
      # extraction produces — so split back out, skipping categories this
      # player has no values in.
      def existing_player_stats_json
        @game.student_game_stats.includes(student_season: [ :student, { college_season: :college } ]).flat_map do |stat|
          GameStats::StatFields::CATEGORIES.filter_map { |category| existing_player_category_row(stat, category) }
        end
      end

      def existing_player_category_row(stat, category)
        columns = GameStats::StatFields::PLAYER_FIELDS.select { |field| field.to_s.start_with?("#{category}_") }
        fields = columns.index_with { |column| stat.public_send(column) }
        return nil if fields.values.all?(&:nil?)

        student_season = stat.student_season
        {
          student_season_id: stat.student_season_id,
          display_name: student_season.student.name,
          team: student_season.college_season.college.name,
          category: category,
          fields: fields
        }
      end

      def analysis_json(result)
        {
          box_score_screenshot_signed_ids: result[:box_score_screenshot_signed_ids],
          home_screenshot_signed_ids: result[:home_screenshot_signed_ids],
          away_screenshot_signed_ids: result[:away_screenshot_signed_ids],
          college_stats: result[:college_stats],
          player_stats: result[:player_stats],
          home_roster: result[:home_roster],
          away_roster: result[:away_roster]
        }
      end
    end
  end
end
