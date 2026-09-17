# Best-effort inference of a CFP bracket round from freeform bowl name
# text, shared by ScheduleStats::CommitService (real games) and
# BowlProjections::Extractor (projected games). Reliable for "CFP First
# Round" since that round is never given its own sponsor name in-game, but
# quarterfinals/semifinals are hosted by a rotating New Year's Six bowl
# brand (e.g. "Orange Bowl") that plain text alone can't resolve to a
# round — for those, a caller that knows which bowl week the game landed
# on (ScheduleStats::CommitService does, via the real committed Week;
# BowlProjections::Extractor doesn't, since a projections screenshot never
# says which week it was captured on — see its class comment) can pass
# week_number to disambiguate.
module CfpRoundInference
  # Rotates annually among these 6 traditional bowls, two of which host
  # that year's quarterfinals and two the semifinals — which two is a
  # yearly assignment this can't infer from the name alone, but *that* a
  # game hosted by one of them in Bowl Week 2/3 is a quarterfinal/
  # semifinal is fixed, since nothing else is scheduled those weeks.
  NEW_YEARS_SIX_BOWLS = [
    "Cotton Bowl", "Fiesta Bowl", "Orange Bowl", "Peach Bowl", "Rose Bowl", "Sugar Bowl"
  ].freeze

  # Season#create_weeks fixes this numbering: 16 = Bowl Week 1 (first
  # round, alongside plenty of non-playoff bowls the same week — so that
  # week is deliberately left out here and resolved by the "first round"
  # text pattern below instead), 17 = Bowl Week 2 (quarterfinals), 18 =
  # Bowl Week 3 (semifinals), 19 = Bowl Week 4 (always the national
  # championship, regardless of how that game happens to be labeled).
  QUARTERFINAL_WEEK_NUMBER = 17
  SEMIFINAL_WEEK_NUMBER = 18
  CHAMPIONSHIP_WEEK_NUMBER = 19

  PATTERNS = {
    /championship/i => "championship",
    /semifinal/i => "semifinal",
    /quarterfinal/i => "quarterfinal",
    /first round/i => "first_round"
  }.freeze

  def self.call(bowl_name, week_number: nil)
    return nil if bowl_name.blank?

    from_week(bowl_name, week_number) || PATTERNS.find { |pattern, _| bowl_name.match?(pattern) }&.last
  end

  def self.from_week(bowl_name, week_number)
    return "championship" if week_number == CHAMPIONSHIP_WEEK_NUMBER
    return nil unless NEW_YEARS_SIX_BOWLS.any? { |bowl| bowl_name.casecmp?(bowl) }

    case week_number
    when QUARTERFINAL_WEEK_NUMBER then "quarterfinal"
    when SEMIFINAL_WEEK_NUMBER then "semifinal"
    end
  end
  private_class_method :from_week
end
