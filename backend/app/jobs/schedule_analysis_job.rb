# WeekScheduleExtractor's 3 Claude calls already run concurrently (see its
# own comments), but the matchups call alone — it compiles a 144-value
# college-name enum into its schema on every request — can still take
# longer than Heroku's fixed 30s request timeout by itself. Backgrounded
# the same way GameAnalysisJob is.
class ScheduleAnalysisJob < ApplicationJob
  queue_as :default

  def perform(token:, image_signed_ids:)
    images = Array(image_signed_ids).map { |signed_id| ActiveStorage::Blob.find_signed!(signed_id) }
    result = ScheduleStats::WeekScheduleExtractor.new.call(images)
    AnalysisStatus.complete!(token, result)
  rescue RubyLLM::Error => e
    AnalysisStatus.failed!(token, "AI extraction failed: #{e.message}")
  end
end
