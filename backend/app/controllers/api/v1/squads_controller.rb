module Api
  module V1
    class SquadsController < BaseController
      before_action :set_team
      before_action :set_squad, only: %i[update destroy]

      def index
        squads = policy_scope(@team.squads)
        render json: squads
      end

      def create
        squad = @team.squads.build(squad_params)
        authorize squad
        if squad.save
          render json: squad, status: :created
        else
          render json: { error: squad.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def update
        authorize @squad
        if @squad.update(squad_params)
          render json: @squad
        else
          render json: { error: @squad.errors.full_messages.to_sentence, code: "unprocessable_entity" }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @squad
        @squad.destroy
        head :no_content
      end

      private

      def set_team
        @team = policy_scope(Team).find(params[:team_id])
      end

      def set_squad
        @squad = policy_scope(@team.squads).find(params[:id])
      end

      def squad_params
        params.require(:squad).permit(:name, :description)
      end
    end
  end
end
