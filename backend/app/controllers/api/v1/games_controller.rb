module Api
  module V1
    class GamesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_game

      def show
        authorize @game
        render json: game_json
      end

      def analyze
        authorize @game
        result = GameStats::ExtractionService.new(@game).call(Array(params[:images]))
        render json: analysis_json(result)
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit
        authorize @game
        payload = commit_params
        GameStats::CommitService.new(@game).call(
          screenshot_signed_ids: payload[:screenshot_signed_ids] || [],
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

      def commit_params
        params.require(:analysis).to_unsafe_h.deep_symbolize_keys
      end

      def game_json(reload: false)
        @game.reload if reload

        {
          id: @game.id,
          week: { id: @game.week.id, number: @game.week.number },
          home_college: { id: @game.home_college.id, name: @game.home_college.name },
          away_college: { id: @game.away_college.id, name: @game.away_college.name },
          played: @game.played?,
          narrative: {
            narrative_summary: @game.narrative_summary,
            offense_player_of_game_id: @game.offensive_player_of_game_id,
            offense_player_stat_line: @game.offensive_player_stat_line,
            defense_player_of_game_id: @game.defensive_player_of_game_id,
            defense_player_stat_line: @game.defensive_player_stat_line
          },
          college_stats: @game.college_game_stats.includes(:college).map { |stat| existing_college_stat_json(stat) },
          player_stats: @game.student_game_stats.includes(student_season: :student).map { |stat| existing_player_stat_json(stat) },
          home_roster: GameStats::Roster.for(@game.home_college, @game.week.season),
          away_roster: GameStats::Roster.for(@game.away_college, @game.week.season)
        }
      end

      def existing_college_stat_json(stat)
        { team: stat.college.name }.merge(stat.attributes.slice(*GameStats::VisionExtractor::COLLEGE_FIELDS.map(&:to_s)))
      end

      def existing_player_stat_json(stat)
        {
          student_season_id: stat.student_season_id,
          name: stat.student_season.student.name,
          position: stat.student_season.position
        }.merge(stat.attributes.slice(*GameStats::VisionExtractor::PLAYER_FIELDS.map(&:to_s)))
      end

      def analysis_json(result)
        {
          screenshot_signed_ids: result[:screenshot_signed_ids],
          college_stats: result[:college_stats],
          player_stats: result[:player_stats],
          narrative: result[:narrative],
          home_roster: result[:home_roster],
          away_roster: result[:away_roster]
        }
      end
    end
  end
end
