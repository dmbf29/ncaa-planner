# Offense and defense ratings built only from a team's starters, as an
# alternative to the game's hand-entered offense/defense.
#
# The game's own team ratings fold in the whole roster (backups and depth
# included) and run it through a scaling curve, so a deep team can show a 91
# offense without a single player in the 90s. These are a plain average of the
# starters' overalls instead, so a unit can never rate above its best players
# and the number means what it says: the typical starter you would face.
#
# The game doesn't expose a depth chart, so a room's "starters" are its
# highest-rated players (WinTotals::Calculator::ROOM_SLOTS, the same stand-in
# the Win Totals and Roster Breakdown use): 11 on each side.
#
# Only the quarterback is weighted up (QB_WEIGHT). In the 2027 backtest
# (135 teams) the offense rating correlated 0.78 with points scored per game,
# against 0.70 for the game's hand-entered offense, and extra QB weight beyond
# 2x added nothing. Defense is an even average: neither it nor the game's
# defense number predicted points allowed in that season (r near 0), so there
# was nothing to tune it against.
class StarterRatings
  OFFENSE_ROOMS = %w[QB RB WR TE OL].freeze
  DEFENSE_ROOMS = %w[DL LB DB].freeze
  QB_WEIGHT = 2.0

  # `college_season`'s student_seasons should be loaded by the caller when
  # rating many teams. Each value is a Float, or nil with no rated starters.
  def self.for(college_season)
    new(college_season).to_h
  end

  def initialize(college_season, calculator: WinTotals::Calculator.new)
    @college_season = college_season
    @calculator = calculator
  end

  def offense
    unit(OFFENSE_ROOMS)
  end

  def defense
    unit(DEFENSE_ROOMS)
  end

  # Offense and defense count equally.
  def overall
    ratings = [ offense, defense ].compact
    ratings.sum / ratings.size unless ratings.empty?
  end

  def to_h
    { offense: offense&.round(1), defense: defense&.round(1), overall: overall&.round(1) }
  end

  private

  def unit(rooms)
    weighted = rooms.flat_map { |room| starters.fetch(room, []).map { |overall| [ overall, weight(room) ] } }
    return nil if weighted.empty?

    weighted.sum { |overall, weight| overall * weight } / weighted.sum { |_overall, weight| weight }
  end

  def weight(room)
    room == "QB" ? QB_WEIGHT : 1.0
  end

  def starters
    @starters ||= begin
      by_room = @college_season.student_seasons.select(&:overall).group_by { |ss| @calculator.room_of(ss.position) }
      WinTotals::Calculator::ROOM_SLOTS.to_h { |room, slots| [ room, Array(by_room[room]).map(&:overall).max(slots) ] }
    end
  end
end
