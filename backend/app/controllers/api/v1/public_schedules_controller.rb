module Api
  module V1
    # A coach's own scheduling page. No login: the unguessable share token in the URL identifies the team, the same
    # trust model as the other public dynasty endpoints. Every rule is enforced here (Scheduling::PickRules), not in the UI.
    class PublicSchedulesController < ApplicationController
      before_action :set_college_season

      def show
        render json: Scheduling::CoachView.new(@college_season)
      end

      def pick
        rules = Scheduling::PickRules.new(@college_season)
        rules.set_pick!(week, params[:opponent_college_id].to_i, ActiveModel::Type::Boolean.new.cast(params[:is_away]) || false)
        render json: Scheduling::CoachView.new(@college_season.reload)
      rescue Scheduling::PickRules::Error => e
        render_error(e)
      end

      def unpick
        Scheduling::PickRules.new(@college_season).remove_pick!(week)
        render json: Scheduling::CoachView.new(@college_season.reload)
      rescue Scheduling::PickRules::Error => e
        render_error(e)
      end

      def confirm
        Scheduling::PickRules.new(@college_season).confirm!
        render json: Scheduling::CoachView.new(@college_season.reload)
      rescue Scheduling::PickRules::Error => e
        render_error(e)
      end

      private

      def set_college_season
        @college_season = CollegeSeason.where.not(coach_id: nil).find_by!(schedule_token: params[:token])
      end

      def week
        @college_season.season.weeks.find(params[:week_id])
      end

      def render_error(error)
        render json: { error: error.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end
    end
  end
end
