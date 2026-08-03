module Api
  module V1
    class SeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_dynasty
      before_action :set_season

      def show
        authorize @season
        render json: ::SeasonDashboardSerializer.new(@season).as_json
      end

      private

      def set_dynasty
        @dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
      end

      def set_season
        @season = @dynasty.seasons.find(params[:id])
      end
    end
  end
end
