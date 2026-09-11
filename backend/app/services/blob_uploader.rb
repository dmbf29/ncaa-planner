# Turns freshly uploaded files into ActiveStorage blobs; anything already a
# Blob (a reanalyze re-run, or blobs an earlier step already created) passes
# through untouched. Shared by every "analyze via background job" flow
# (GameStats::ExtractionService, ScheduleAnalysisJob, ...) — uploading
# happens synchronously in the controller (fast, no LLM call) so only a
# plain signed_id, not a raw file object, has to cross onto the job queue
# (ActiveJob can't serialize an ActionDispatch::Http::UploadedFile).
module BlobUploader
  def self.attach_blobs(files_or_blobs)
    Array(files_or_blobs).map do |file|
      next file if file.is_a?(ActiveStorage::Blob)

      ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: file.content_type)
    end
  end
end
