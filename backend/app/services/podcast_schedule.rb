# In-world air dates for the two weekly shows, derived from the kickoff times
# on the season's games so the Review and the Big Game Breakdown feel like
# scheduled shows through the week:
#
#   Saturday games  ->  Review pod the following Monday
#                       Big Game Breakdown the Thursday before the next
#                       Saturday
#
# A week's "anchor" is the most common game date across the whole league (the
# Saturday slate). The shows only cover our coached teams' games, though, so
# the exceptions that move an air date (a Thursday or Tuesday kickoff, a
# Sunday or Monday finish) only count when one of OUR games is the one played
# then; a midweek game between two other teams doesn't pull the show earlier.
# A week with no timed games (a schedule that's been uploaded without
# kickoffs) is inferred from the nearest timed regular-season week, seven days
# per week of distance, so the shows still get dates until real ones are
# entered. Postseason weeks are irregular and never inferred.
class PodcastSchedule
  LAST_INFERRABLE_WEEK = 14
  THURSDAY = 4

  def initialize(season)
    @season = season
  end

  # The day the Review pod for `week_number` airs: the day after its last
  # game, pushed past Sunday to Monday. nil when no date can be worked out.
  def review_date(week_number)
    last = last_game_date(week_number)
    last ||= anchor_date(week_number)
    return nil unless last

    date = last + 1
    date += 1 if date.sunday?
    date
  end

  # The day the Big Game Breakdown for `week_number` airs: the Thursday on or
  # before the week's anchor date, or the day before the first kickoff when a
  # game is played that Thursday or earlier.
  def preview_date(week_number)
    anchor = anchor_date(week_number)
    return nil unless anchor

    thursday = anchor - ((anchor.wday - THURSDAY) % 7)
    earliest = earliest_game_date(week_number)
    earliest && earliest <= thursday ? earliest - 1 : thursday
  end

  private

  # { week number => [date, ...] } for every timed game in the league.
  def game_dates_by_week
    @game_dates_by_week ||= dates_by_week(timed_games)
  end

  # The same, for games involving one of our coached teams only.
  def our_game_dates_by_week
    @our_game_dates_by_week ||= dates_by_week(timed_games.select { |_week_id, _time, home_id, away_id| coached_college_ids.include?(home_id) || coached_college_ids.include?(away_id) })
  end

  def timed_games
    @timed_games ||= Game.where(week_id: week_numbers_by_id.keys).where.not(time: nil)
                         .pluck(:week_id, :time, :home_college_id, :away_college_id)
  end

  def week_numbers_by_id
    @week_numbers_by_id ||= @season.weeks.pluck(:id, :number).to_h
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def dates_by_week(games)
    games.group_by { |week_id, *| week_numbers_by_id[week_id] }
         .transform_values { |rows| rows.map { |_week_id, time, *| time.in_time_zone(PodcastShow::TIME_ZONE).to_date } }
  end

  def last_game_date(week_number)
    our_game_dates_by_week[week_number]&.max
  end

  def earliest_game_date(week_number)
    our_game_dates_by_week[week_number]&.min
  end

  def anchor_date(week_number)
    dates = game_dates_by_week[week_number]
    return modal_date(dates) if dates.present?
    return nil if week_number > LAST_INFERRABLE_WEEK

    nearest = game_dates_by_week.keys.select { |number| number <= LAST_INFERRABLE_WEEK }
                                .min_by { |number| [ (number - week_number).abs, number ] }
    return nil unless nearest

    modal_date(game_dates_by_week[nearest]) + (7 * (week_number - nearest))
  end

  # Most common date, latest wins a tie.
  def modal_date(dates)
    dates.tally.max_by { |date, count| [ count, date ] }.first
  end
end
