module Api
  module V1
    class SeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_dynasty
      before_action :set_season, except: :create

      def show
        authorize @season
        render json: ::SeasonDashboardSerializer.new(@season).as_json
      end

      def create
        @season = @dynasty.seasons.new(season_params)
        authorize @season
        @season.save!
        render json: { id: @season.id, year: @season.year }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_schedule
        authorize @season
        result = ScheduleStats::WeekScheduleExtractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_schedule
        authorize @season
        week = @season.weeks.find(params[:week_id])
        warnings = ScheduleStats::CommitService.new(week).call(commit_rows)
        render json: { week_id: week.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_all_americans
        authorize @season
        result = AllAmericans::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_all_americans
        authorize @season
        warnings = AllAmericans::CommitService.new(@season).call(commit_groups)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_nil_spend
        authorize @season
        result = NilSpend::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_nil_spend
        authorize @season
        warnings = NilSpend::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_conference_standings
        authorize @season
        result = ConferenceStandings::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_conference_standings
        authorize @season
        warnings = ConferenceStandings::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_players_of_the_week
        authorize @season
        result = PlayersOfTheWeek::Extractor.new.call(Array(params[:images]), season: @season)
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_players_of_the_week
        authorize @season
        warnings = PlayersOfTheWeek::CommitService.new(@season).call(commit_groups)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_recruiting
        authorize @season
        result = Recruiting::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_recruiting
        authorize @season
        warnings = Recruiting::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_team_schedule
        authorize @season
        result = TeamSchedule::ScheduleExtractor.new.call(Array(params[:images]), season: @season)
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_team_schedule
        authorize @season
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        warnings = TeamSchedule::CommitService.new(college_season).call(team_stats_params, commit_rows)
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def destroy
        authorize @season
        @season.destroy
        head :no_content
      end

      def commit_roster_import
        authorize @season
        college_season = @season.college_seasons.find_by!(id: params[:college_season_id])
        warnings = RosterImport::CommitService.new(college_season).call(commit_players)
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def coach_assignments
        authorize @season
        render json: SeasonCoachAssignmentsSerializer.new(@season).as_json
      end

      def commit_coach_assignments
        authorize @season
        warnings = CoachContinuity::CommitService.new(@season).call(commit_assignments)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_dynasty
        @dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
      end

      def set_season
        @season = @dynasty.seasons.find(params[:id])
      end

      def season_params
        params.require(:season).permit(:year)
      end

      def commit_rows
        params.require(:rows)
        params[:rows].map { |row| row.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_groups
        params.require(:groups)
        params[:groups].map { |group| group.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_assignments
        params.require(:assignments)
        params[:assignments].map { |assignment| assignment.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_players
        params.require(:players)
        params[:players].map { |player| player.to_unsafe_h.deep_symbolize_keys }
      end

      def team_stats_params
        return {} unless params[:team_stats]

        params[:team_stats].to_unsafe_h.deep_symbolize_keys
      end
    end
  end
end
