module Api
  module V1
    # Marking a recruit from the public Recruits page (DynastyPortalsController#recruits) as signed with one
    # of the signed-in user's coached teams. #show lists those teams; #sign saves the recruit as a
    # SignedRecruit the same way a signing-screen upload does.
    class RecruitPoolsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season

      def show
        teams = @season.college_seasons.where.not(coach_id: nil).includes(:college).map { |cs| { college_id: cs.college_id, name: cs.college.name } }
        render json: { teams: teams.sort_by { |team| team[:name] } }
      end

      def sign
        recruit = DynastyRewired::RecruitPool.new(@season).find(params[:rank]) or raise ActiveRecord::RecordNotFound, "No recruit with that rank"
        college_season = @season.college_seasons.where.not(coach_id: nil).find_by!(college_id: params[:college_id])
        week = @season.weeks.find_by!(number: params[:week_number])

        warnings = RecruitmentTrail::CommitService.new(college_season, week).call([ signing_row(recruit) ])
        @season.touch # the dashboard payload is cached on season.updated_at
        render json: { warnings: warnings, signed_with: college_season.college.name }
      rescue DynastyRewired::Client::Error => e
        render json: { error: e.message, code: "dynasty_rewired_error" }, status: :bad_gateway
      end

      private

      def set_season
        dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
        authorize @season, :show?
      end

      def signing_row(recruit)
        {
          first_name: recruit[:first_name], last_name: recruit[:last_name], position: recruit[:position], state: recruit[:state],
          star_rating: recruit[:stars], national_rank: recruit[:rank], position_rank: recruit[:position_rank],
          state_rank: recruit[:state_rank], transfer: false
        }
      end
    end
  end
end
