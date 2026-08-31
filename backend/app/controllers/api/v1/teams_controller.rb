module Api
  module V1
    class TeamsController < BaseController
      before_action :set_team, only: %i[show update destroy import_roster analyze_roster_update commit_roster_update]

      def index
        teams = policy_scope(Team.includes(:squads).where(user: current_user))
        render json: teams.as_json(include: { squads: { only: %i[id name] } })
      end

      def show
        authorize @team
        render json: team_json(@team)
      end

      def create
        team = current_user.teams.build(team_params)
        authorize team

        if team.save
          team.squads.find_or_create_by!(name: "Offense")
          team.squads.find_or_create_by!(name: "Defense")
          render json: team.as_json(include: { squads: { only: %i[id name] } }), status: :created
        else
          render json: { error: team.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def update
        authorize @team
        if @team.update(team_params)
          render json: @team
        else
          render json: { error: @team.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @team
        @team.destroy
        head :no_content
      end

      def import_roster
        authorize @team
        ScrapePlayersJob.perform_now(team_id: @team.id, college_id: params[:college_id])
        render json: team_json(@team.reload)
      end

      def analyze_roster_update
        authorize @team
        result = RosterUpdates::Extractor.new.call(@team, Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_roster_update
        authorize @team
        warnings = RosterUpdates::CommitService.new(@team).call(
          rows: commit_rows,
          missing_player_actions: commit_missing_player_actions
        )
        render json: { team: team_json(@team.reload), warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_team
        @team = policy_scope(Team).find(params[:id])
      end

      def team_params
        params.require(:team).permit(:name, :college_id)
      end

      def commit_rows
        Array(params[:rows]).map { |row| row.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_missing_player_actions
        Array(params[:missing_player_actions]).map { |action| action.to_unsafe_h.deep_symbolize_keys }
      end

      def team_json(team)
        team.as_json(
          include: {
            squads: {
              include: {
                position_boards: {
                  include: {
                    players: { only: %i[id name status class_year dev_trait archetype overall attributes tags] }
                  }
                }
              }
            }
          }
        )
      end
    end
  end
end
