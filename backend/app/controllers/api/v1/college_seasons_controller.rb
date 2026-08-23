module Api
  module V1
    class CollegeSeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_college_season

      def update
        authorize @college_season
        if @college_season.update(college_season_params)
          render json: {
            id: @college_season.id,
            overall: @college_season.overall,
            offense: @college_season.offense,
            defense: @college_season.defense,
            prestige: @college_season.prestige
          }
        else
          render json: { error: @college_season.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      private

      def set_college_season
        @college_season = policy_scope(CollegeSeason).find(params[:id])
      end

      def college_season_params
        params.require(:college_season).permit(:overall, :offense, :defense, :prestige)
      end
    end
  end
end
