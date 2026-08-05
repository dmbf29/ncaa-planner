module Api
  module V1
    class SeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_dynasty
      before_action :set_season, only: :show

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
    end
  end
end
