module Api
  module V1
    # Public, unauthenticated endpoints intended for third-party consumption
    # (e.g. a podcast-generation script). No ownership check is performed —
    # anyone with a dynasty/season id can read this data.
    class SeasonBroadcastsController < ApplicationController
      before_action :set_season

      def win_totals
        data = ::WinTotalsSerializer.new(@season).as_json
        render_broadcast(data) { ::WinTotalsMarkdownPresenter.new(data).to_markdown }
      end

      def weeks
        week_numbers = parse_week_numbers
        if week_numbers.empty?
          render json: { error: "week_numbers query param is required (e.g. ?week_numbers=1,2)", code: "bad_request" },
                 status: :bad_request
          return
        end

        data = ::SeasonWeeksSerializer.new(@season, week_numbers).as_json
        render_broadcast(data) { ::SeasonWeeksMarkdownPresenter.new(data).to_markdown }
      end

      def team_breakdown
        data = ::TeamBreakdownSerializer.new(@season).as_json
        render_broadcast(data) { ::TeamBreakdownMarkdownPresenter.new(data).to_markdown }
      end

      private

      def set_season
        dynasty = Dynasty.find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
      end

      def parse_week_numbers
        params[:week_numbers].to_s.split(",").filter_map { |n| Integer(n, exception: false) }
      end

      def render_broadcast(json_data)
        if markdown_requested?
          render plain: yield, content_type: "text/markdown"
        else
          render json: json_data
        end
      end

      def markdown_requested?
        %w[markdown md].include?(params[:format].to_s.downcase)
      end
    end
  end
end
