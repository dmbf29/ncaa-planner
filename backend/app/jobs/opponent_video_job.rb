# Same background/poll shape as RosterVideoJob, but runs tools/capture/read_card_video.py: local OCR over a screen
# recording of the opponent picker, one team card at a time. Shares RosterVideoJob's upload stash, Python env and
# concurrency cap.
class OpponentVideoJob < RosterVideoJob
  SCRIPT = Rails.root.join("../tools/capture/read_card_video.py").expand_path
end
