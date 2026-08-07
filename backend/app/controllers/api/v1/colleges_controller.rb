module Api
  module V1
    class CollegesController < BaseController
      skip_after_action :verify_policy_scoped, only: :index

      def index
        render json: College.order(:name).as_json(only: %i[id name conference])
      end
    end
  end
end
