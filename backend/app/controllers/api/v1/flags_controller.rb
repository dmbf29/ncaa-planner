module Api
  module V1
    class FlagsController < BaseController
      skip_after_action :verify_policy_scoped, only: :index

      def index
        render json: Flag.all.order(:name)
      end
    end
  end
end
