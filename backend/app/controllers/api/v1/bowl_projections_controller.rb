module Api
  module V1
    class BowlProjectionsController < BaseController
      before_action :set_week
      before_action :set_bowl_projection, only: %i[update destroy]

      def index
        bowl_projections = policy_scope(@week.bowl_projections)
        render json: bowl_projections
      end

      def create
        bowl_projection = @week.bowl_projections.build(bowl_projection_params)
        authorize bowl_projection

        if bowl_projection.save
          render json: bowl_projection, status: :created
        else
          render json: { error: bowl_projection.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def update
        authorize @bowl_projection

        if @bowl_projection.update(bowl_projection_params)
          render json: @bowl_projection
        else
          render json: { error: @bowl_projection.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def destroy
        authorize @bowl_projection
        @bowl_projection.destroy
        head :no_content
      end

      private

      def set_week
        @week = Week.find(params[:week_id])
      end

      def set_bowl_projection
        @bowl_projection = @week.bowl_projections.find(params[:id])
      end

      def bowl_projection_params
        params.require(:bowl_projection).permit(:bowl_name, :cfp_round, :projected_home_college_id, :projected_away_college_id)
      end
    end
  end
end
