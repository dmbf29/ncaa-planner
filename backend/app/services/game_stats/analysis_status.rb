module GameStats
  # Tracks progress of a background extraction (GameAnalysisJob) so
  # GamesController#analyze_status has something to poll. Backed by
  # Rails.cache rather than a table — this is disposable, review-before-
  # commit data with the same lifecycle the old synchronous response had
  # (thrown away once the user commits or navigates away), so a table +
  # migration would be more machinery than the data warrants.
  #
  # Relies on Rails.cache being process-local (:memory_store in production —
  # see config/environments/production.rb) and the job running in that same
  # process (the SOLID_QUEUE_IN_PUMA puma plugin, not a separate worker
  # dyno). If this app ever scales to multiple web dynos, a poll request can
  # land on a dyno that never ran the job and see nothing — move this to a
  # DB-backed store (or a shared cache) before doing that.
  module AnalysisStatus
    TTL = 15.minutes

    def self.pending!(token)
      Rails.cache.write(key(token), { status: "pending" }, expires_in: TTL)
    end

    def self.complete!(token, result)
      Rails.cache.write(key(token), { status: "completed", result: result }, expires_in: TTL)
    end

    def self.failed!(token, message)
      Rails.cache.write(key(token), { status: "failed", error: message }, expires_in: TTL)
    end

    def self.read(token)
      Rails.cache.read(key(token)) || { status: "not_found" }
    end

    def self.key(token)
      "game_analysis_status/#{token}"
    end
  end
end
