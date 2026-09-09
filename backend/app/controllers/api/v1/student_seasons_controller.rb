module Api
  module V1
    class StudentSeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_student_season

      def update
        authorize @student_season

        StudentSeason.transaction do
          @student_season.student.update!(student_params) if student_params.present?
          @student_season.update!(student_season_params) if student_season_params.present?
        end

        render json: { id: @student_season.id, name: @student_season.student.name, overall: @student_season.overall }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages.to_sentence, code: "unprocessable_entity" },
               status: :unprocessable_entity
      end

      private

      def set_student_season
        @student_season = policy_scope(StudentSeason).find(params[:id])
      end

      def student_params
        params.require(:student_season).permit(:first_name, :last_name)
      end

      def student_season_params
        params.require(:student_season).permit(:overall)
      end
    end
  end
end
