module Api
  module V1
    class InjuriesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_student_season
      before_action :set_injury, only: %i[update destroy]

      def create
        injury = @student_season.injuries.build(injury_params)
        authorize injury

        if injury.save
          render json: injury, status: :created
        else
          render json: { error: injury.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def update
        authorize @injury

        if @injury.update(injury_params)
          render json: @injury
        else
          render json: { error: @injury.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      def destroy
        authorize @injury
        @injury.destroy
        head :no_content
      end

      private

      def set_student_season
        @student_season = policy_scope(StudentSeason).find(params[:student_season_id])
      end

      def set_injury
        @injury = @student_season.injuries.find(params[:id])
      end

      def injury_params
        params.require(:injury).permit(:game_id, :description, :weeks_out)
      end
    end
  end
end
