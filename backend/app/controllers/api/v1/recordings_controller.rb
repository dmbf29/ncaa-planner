module Api
  module V1
    # Local-only: stream recordings waiting to be attached to a game. See GameScoring::Inbox.
    class RecordingsController < BaseController
      skip_after_action :verify_authorized
      before_action :require_local_capture
      before_action :set_dynasty

      def index
        render json: { recordings: GameScoring::Inbox.new(@dynasty).call }
      end

      def dismiss
        GameScoring::Inbox.dismiss(params[:recording])
        head :no_content
      rescue GameScoring::Recordings::Error => e
        render json: { error: e.message, code: "dismiss_failed" }, status: :unprocessable_entity
      end

      private

      def require_local_capture
        render json: { error: "Recordings are only available in local development.", code: "not_available" }, status: :not_found unless Rails.env.development?
      end

      def set_dynasty
        @dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
      end
    end
  end
end
