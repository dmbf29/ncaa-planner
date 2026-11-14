module Api
  module V1
    # Refreshes player ratings from Dynasty Rewired's roster captures, one school per request since a
    # school is one API call and a whole season would outlast a web request (see DynastyRewired::Rosters).
    # #show lists the schools; #create refreshes the one named.
    class DynastyRewiredRostersController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season

      def show
        schools = DynastyRewired::Rosters.new(@season).schools
        render json: { schools: schools.map { |school| school.slice(:name, :team_id) } }
      rescue DynastyRewired::Client::Error => e
        render_error(e)
      end

      def create
        return render json: { error: "team_id must be the numeric id from the school list" }, status: :unprocessable_entity unless params[:team_id].to_s.match?(/\A\d+\z/)

        school = DynastyRewired::Rosters.new(@season).refresh(name: params[:school], team_id: params[:team_id], apply: true)
        render json: {
          school: school.name,
          updated: school.updates.size,
          unchanged: school.unchanged,
          unmatched: school.unmatched,
          missing: school.missing
        }
      rescue DynastyRewired::Client::Error => e
        render_error(e)
      end

      private

      def set_season
        dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
        authorize @season, :show?
      end

      def render_error(error)
        render json: { error: error.message, code: "dynasty_rewired_error" }, status: :bad_gateway
      end
    end
  end
end
