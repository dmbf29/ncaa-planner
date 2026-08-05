module Api
  module V1
    class WeeksController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_week

      def analyze_top_25_rankings
        authorize @week
        result = RankingStats::TopTwentyFiveExtractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_top_25_rankings
        authorize @week
        warnings = RankingStats::CommitService.new(@week).call(commit_rows)
        render json: { week_id: @week.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_heisman_candidates
        authorize @week
        result = HeismanCandidates::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_heisman_candidates
        authorize @week
        warnings = HeismanCandidates::CommitService.new(@week).call(commit_rows)
        render json: { week_id: @week.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_week
        @week = Week.find(params[:id])
      end

      def commit_rows
        params.require(:rows)
        params[:rows].map { |row| row.to_unsafe_h.deep_symbolize_keys }
      end
    end
  end
end
