# In-world air dates for the two weekly shows, derived from the kickoff times
# on the season's games so the Review and the Big Game Breakdown feel like
# scheduled shows through the week:
#
#   Saturday games  ->  Review pod the following Monday
#                       Big Game Breakdown the Thursday before the next
#                       Saturday
#
# A week's "anchor" is the most common game date (the Saturday slate). A
# week with no timed games (a schedule that's been uploaded without
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

  def game_dates_by_week
    @game_dates_by_week ||= begin
      week_numbers = @season.weeks.pluck(:id, :number).to_h
      Game.where(week_id: week_numbers.keys).where.not(time: nil).pluck(:week_id, :time)
          .group_by { |week_id, _time| week_numbers[week_id] }
          .transform_values { |rows| rows.map { |_week_id, time| time.to_date } }
    end
  end

  def last_game_date(week_number)
    game_dates_by_week[week_number]&.max
  end

  def earliest_game_date(week_number)
    game_dates_by_week[week_number]&.min
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
