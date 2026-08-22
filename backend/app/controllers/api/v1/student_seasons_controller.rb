module Api
  module V1
    class StudentSeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_student_season

      def update
        authorize @student_season
        if @student_season.student.update(student_params)
          render json: { id: @student_season.id, name: @student_season.student.name }
        else
          render json: { error: @student_season.student.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      private

      def set_student_season
        @student_season = policy_scope(StudentSeason).find(params[:id])
      end

      def student_params
        params.require(:student_season).permit(:first_name, :last_name)
      end
    end
  end
end
