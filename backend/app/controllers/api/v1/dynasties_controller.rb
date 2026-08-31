module Api
  module V1
    class DynastiesController < BaseController
      def index
        dynasties = policy_scope(Dynasty).includes(:seasons)
        render json: dynasties.as_json(include: { seasons: { only: %i[id year] } })
      end
    end
  end
end
