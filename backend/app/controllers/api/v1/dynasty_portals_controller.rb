module Api
  module V1
    # Public, unauthenticated endpoints powering the shareable dynasty dashboard —
    # anyone with a dynasty/season id can read this data, same as SeasonBroadcastsController.
    # Editing/uploading dynasty data still requires auth and goes through the
    # BaseController-backed controllers elsewhere in this namespace.
    class DynastyPortalsController < ApplicationController
      def show
        dynasty = Dynasty.find(params[:id])
        render json: {
          id: dynasty.id,
          name: dynasty.name,
          seasons: dynasty.seasons.order(year: :desc).as_json(only: %i[id year])
        }
      end

      def dashboard
        render json: ::SeasonDashboardSerializer.new(set_season).as_json
      end

      def standings
        render json: ::ConferenceStandingsSerializer.new(set_season).as_json
      end

      def rankings
        season = set_season
        week = season.weeks.find_by!(number: params[:week_number])
        render json: ::WeekRankingsSerializer.new(week).as_json
      end

      def all_americans
        render json: ::SeasonAllAmericansSerializer.new(set_season).as_json
      end

      def roster
        college_season = set_season.college_seasons.find(params[:college_season_id])
        render json: ::CollegeSeasonRosterSerializer.new(college_season).as_json
      end

      def week_games
        season = set_season
        week = season.weeks.find_by!(number: params[:week_number])
        render json: ::WeekGamesSerializer.new(week).as_json
      end

      private

      def set_season
        dynasty = Dynasty.find(params[:dynasty_id])
        dynasty.seasons.find(params[:season_id])
      end
    end
  end
end
