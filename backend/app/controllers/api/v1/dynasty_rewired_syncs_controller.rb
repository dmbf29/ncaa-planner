module Api
  module V1
    # Pulls a season's results, box scores and Top 25 from Dynasty Rewired: #show reads the API and returns
    # what would change, #create saves the sections the user ticked (see DynastyRewired::Sync).
    class DynastyRewiredSyncsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season

      def show
        render json: DynastyRewired::Sync.new(@season).preview
      rescue DynastyRewired::Client::Error => e
        render json: { error: e.message, code: "dynasty_rewired_error" }, status: :bad_gateway
      end

      def create
        sync = DynastyRewired::Sync.new(@season)
        saved = sync.apply(params[:sections])
        render json: { saved: saved, preview: sync.preview }
      rescue DynastyRewired::Client::Error => e
        render json: { error: e.message, code: "dynasty_rewired_error" }, status: :bad_gateway
      end

      private

      def set_season
        dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
        authorize @season, :show?
      end
    end
  end
end
