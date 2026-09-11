# Runs GameStats::ExtractionService's ~20+ sequential Claude calls off the
# request/response cycle — that many calls back-to-back reliably exceeds
# Heroku's fixed 30s router timeout, which local dev (no such timeout) never
# surfaced. GamesController#analyze/#reanalyze upload screenshots as blobs
# and enqueue this job with their signed_ids (plain strings — ActiveJob
# can't serialize a raw uploaded-file object); GameStats::AnalysisStatus is
# how the controller's #analyze_status poll action reads the result back.
class GameAnalysisJob < ApplicationJob
  queue_as :default

  def perform(game_id:, token:, box_score_signed_ids: [], home_signed_ids: [], away_signed_ids: [])
    game = Game.find(game_id)
    result = GameStats::ExtractionService.new(game).call(
      box_score_files: resolve_blobs(box_score_signed_ids),
      home_files: resolve_blobs(home_signed_ids),
      away_files: resolve_blobs(away_signed_ids)
    )
    GameStats::AnalysisStatus.complete!(token, result)
  rescue RubyLLM::Error => e
    GameStats::AnalysisStatus.failed!(token, "AI extraction failed: #{e.message}")
  end

  private

  def resolve_blobs(signed_ids)
    Array(signed_ids).map { |signed_id| ActiveStorage::Blob.find_signed!(signed_id) }
  end
end
