# Best-effort inference of a CFP bracket round from freeform bowl name
# text, shared by ScheduleStats::CommitService (real games) and
# BowlProjections::Extractor (projected games). Reliable for "CFP First
# Round" since that round is never given its own sponsor name in-game, but
# quarterfinals/semifinals/the championship are usually hosted by a
# rotating New Year's Six bowl brand (e.g. "Orange Bowl") that this can't
# resolve from text alone — those need a manual correction in the review
# step before committing.
module CfpRoundInference
  PATTERNS = {
    /championship/i => "championship",
    /semifinal/i => "semifinal",
    /quarterfinal/i => "quarterfinal",
    /first round/i => "first_round"
  }.freeze

  def self.call(bowl_name)
    return nil if bowl_name.blank?

    PATTERNS.find { |pattern, _| bowl_name.match?(pattern) }&.last
  end
end
