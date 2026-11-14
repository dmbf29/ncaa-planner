module Api
  module V1
    # Search the season's recruit pool from Dynasty Rewired and mark a recruit as signed with a coached
    # team (see DynastyRewired::RecruitPool). #show returns one page of matches; #sign saves the recruit
    # as a SignedRecruit the same way a signing-screen upload does.
    class RecruitPoolsController < BaseController
      PAGE_SIZE = 50

      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season

      def show
        pool = DynastyRewired::RecruitPool.new(@season)
        pool.refresh if params[:refresh].present?
        matches = pool.search(query: params[:q], position: params[:position], stars: params[:stars], state: params[:state], archetype: params[:archetype])
        offset = params[:offset].to_i
        signed = signed_with

        render json: {
          total: matches.size,
          recruits: matches.slice(offset, PAGE_SIZE).to_a.map { |recruit| recruit.except(:search_name).merge(signed_with: signed[recruit[:rank]]) },
          filters: filter_options(pool.all),
          teams: coached_teams
        }
      rescue DynastyRewired::Client::Error => e
        render json: { error: e.message, code: "dynasty_rewired_error" }, status: :bad_gateway
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

      # national rank => the college that signed them, for recruits already recorded this season.
      def signed_with
        SignedRecruit.joins(college_season: :college)
                     .where(college_seasons: { season_id: @season.id }, transfer: false)
                     .where.not(national_rank: nil)
                     .pluck(:national_rank, "colleges.name").to_h
      end

      def coached_teams
        @season.college_seasons.where.not(coach_id: nil).includes(:college).map { |cs| { college_id: cs.college_id, name: cs.college.name } }.sort_by { |team| team[:name] }
      end

      def filter_options(pool)
        {
          positions: pool.filter_map { |r| r[:position] }.uniq.sort,
          states: pool.filter_map { |r| r[:state] }.uniq.sort,
          archetypes: pool.filter_map { |r| r[:archetype] }.uniq.sort
        }
      end
    end
  end
end
