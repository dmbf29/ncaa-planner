module Top25Capture
  # Same watcher as the schedule capture, pointed at the Top 25 poll. The poll's header isn't classified, so every
  # screen kept is read; the list is scrolled with the stick held down, so frames are taken twice a second.
  class Session < ScheduleCapture::Session
    def label = "top25"
    def signature_box = "0.03,0.15,0.97,0.90"
    def paths_kind = nil
  end
end
