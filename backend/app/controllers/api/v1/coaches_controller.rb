module Api
  module V1
    class CoachesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized

      def update
        coach = policy_scope(Coach).find(params[:id])
        authorize coach
        if coach.update(coach_params)
          render json: {
            id: coach.id,
            nil_amount: coach.nil_amount,
            job_security: coach.job_security,
            job_security_label: coach.job_security_label
          }
        else
          render json: { error: coach.errors.full_messages.to_sentence, code: "unprocessable_entity" },
                 status: :unprocessable_entity
        end
      end

      private

      def coach_params
        params.require(:coach).permit(:nil_amount, :job_security)
      end
    end
  end
end
