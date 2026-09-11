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

      # Extraction is ~20+ sequential Claude calls (box score field-groups +
      # per-team, per-category player stats) — too slow to run inline within
      # Heroku's fixed 30s request timeout. Uploads the screenshots as blobs
      # right away (fast, no LLM call) and hands their signed_ids to
      # GameAnalysisJob to run in the background; the frontend polls
      # #analyze_status with the returned token for the result.
      def analyze
        authorize @game
        token = SecureRandom.uuid
        box_score_blobs = GameStats::ExtractionService.attach_blobs(Array(params[:box_score_images]))
        home_blobs = GameStats::ExtractionService.attach_blobs(Array(params[:home_images]))
        away_blobs = GameStats::ExtractionService.attach_blobs(Array(params[:away_images]))

        GameStats::AnalysisStatus.pending!(token)
        GameAnalysisJob.perform_later(
          game_id: @game.id,
          token: token,
          box_score_signed_ids: box_score_blobs.map(&:signed_id),
          home_signed_ids: home_blobs.map(&:signed_id),
          away_signed_ids: away_blobs.map(&:signed_id)
        )
        render json: { token: token, status: "pending" }, status: :accepted
      end

      # Re-runs extraction on a section's already-attached screenshots — no
      # new upload needed — for when the first pass missed something and a
      # retry is worth trying before resorting to manual entry. Reuses the
      # existing blobs, so this never creates duplicate screenshot
      # attachments on commit. Backgrounded the same way #analyze is.
      def reanalyze
        authorize @game
        attachment_name = SECTION_ATTACHMENTS[params[:section]]
        return render json: { error: "invalid section" }, status: :unprocessable_entity unless attachment_name

        token = SecureRandom.uuid
        signed_ids = @game.public_send(attachment_name).map { |screenshot| screenshot.blob.signed_id }

        GameStats::AnalysisStatus.pending!(token)
        GameAnalysisJob.perform_later(
          game_id: @game.id,
          token: token,
          box_score_signed_ids: attachment_name == :box_score_screenshots ? signed_ids : [],
          home_signed_ids: attachment_name == :home_stat_screenshots ? signed_ids : [],
          away_signed_ids: attachment_name == :away_stat_screenshots ? signed_ids : []
        )
        render json: { token: token, status: "pending" }, status: :accepted
      end

      # Polled by the frontend after #analyze/#reanalyze until status moves
      # past "pending". "not_found" covers an expired (15min TTL) or unknown
      # token, surfaced to the user as a plain failure rather than a silent
      # infinite poll.
      def analyze_status
        authorize @game
        status = GameStats::AnalysisStatus.read(params[:token])

        case status[:status]
        when "completed"
          render json: { status: "completed", analysis: analysis_json(status[:result]) }
        when "failed"
          render json: { status: "failed", error: status[:error], code: "extraction_failed" }, status: :unprocessable_entity
        when "not_found"
          render json: { status: "failed", error: "Analysis expired or not found — try again.", code: "extraction_failed" },
                 status: :unprocessable_entity
        else
          render json: { status: "pending" }
        end
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
