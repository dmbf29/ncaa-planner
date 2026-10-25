# Same background/poll shape as RosterVideoJob, but runs tools/transfer_video/extract.py: local OCR over a
# recording of the "players leaving" screen that returns only the players whose reason is Transfer. It shares
# RosterVideoJob's upload stash, Python env and concurrency cap.
class TransferVideoJob < RosterVideoJob
  SCRIPT = Rails.root.join("tools/transfer_video/extract.py")
end
