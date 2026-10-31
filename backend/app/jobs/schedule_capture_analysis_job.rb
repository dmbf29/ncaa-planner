# Reads a finished Remote Play schedule capture (ScheduleCapture::Session) on this Mac, with no AI call. The
# screenshots are read straight from disk, so unlike ScheduleAnalysisJob there are no blobs.
class ScheduleCaptureAnalysisJob < ApplicationJob
  queue_as :default

  def perform(token:, season_id:, paths:)
    result = ScheduleStats::LocalSchedule.new.call(paths, season: Season.find(season_id))
    AnalysisStatus.complete!(token, result)
  rescue ScheduleStats::LocalSchedule::Error => e
    AnalysisStatus.failed!(token, e.message)
  end
end
