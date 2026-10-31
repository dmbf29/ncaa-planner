# Reads a finished Remote Play Top 25 capture (Top25Capture::Session) on this Mac, with no AI call.
class Top25CaptureAnalysisJob < ApplicationJob
  queue_as :default

  def perform(token:, paths:)
    AnalysisStatus.complete!(token, RankingStats::LocalTop25.new.call(paths))
  rescue RankingStats::LocalTop25::Error => e
    AnalysisStatus.failed!(token, e.message)
  end
end
