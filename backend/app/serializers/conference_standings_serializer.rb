# Full conference standings table for a season, grouped by conference —
# every college with a CollegeSeason row, not just coached teams, since
# standings are league-wide context. Sorted by conference win % then
# overall win % within each conference, matching how a real standings
# table reads.
#
# Records and points come from the games played (StandingsCalculator), not from any uploaded standings;
# `through_week_number` shows the table as it stood after that week.
class ConferenceStandingsSerializer
  def initialize(season, through_week_number: nil)
    @season = season
    @calculator = StandingsCalculator.new(season, through_week_number: through_week_number)
  end

  def as_json
    {
      season: { id: @season.id, year: @season.year },
      conferences: college_seasons_by_conference.map { |conference, rows| conference_json(conference, rows) }
    }
  end

  private

  def college_seasons_by_conference
    @season.college_seasons
           .includes(:college, :coach)
           .group_by(&:conference)
           .sort_by { |conference, _rows| conference.to_s }
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def player_counts
    @player_counts ||= StudentSeason.where(college_season_id: @season.college_season_ids).group(:college_season_id).count
  end

  def latest_ranked_week
    return @latest_ranked_week if defined?(@latest_ranked_week)

    @latest_ranked_week = @season.weeks.joins(:college_week_rankings).order(number: :desc).first
  end

  def rank_for_college(college_id)
    return nil unless latest_ranked_week

    latest_ranked_week.college_week_rankings.find { |cwr| cwr.college_id == college_id }&.ranking
  end

  def conference_json(conference, rows)
    {
      conference: conference,
      teams: rows.sort_by { |cs| [ -win_pct(*record_of(cs).values_at(:conference_wins, :conference_losses)), -win_pct(*record_of(cs).values_at(:wins, :losses)) ] }
                 .map { |cs| team_json(cs) }
    }
  end

  def record_of(college_season)
    @calculator.record_for(college_season.college_id)
  end

  def win_pct(wins, losses)
    total = wins.to_i + losses.to_i
    return 0.0 if total.zero?

    wins.to_f / total
  end

  def team_json(college_season)
    record = @calculator.record_for(college_season.college_id)
    {
      id: college_season.id,
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: college_season.coach && { id: college_season.coach.id, name: college_season.coach.name },
      division: college_season.division,
      coached_by_us: coached_college_ids.include?(college_season.college_id),
      player_count: player_counts.fetch(college_season.id, 0),
      rank: rank_for_college(college_season.college_id),
      **record.slice(:wins, :losses, :conference_wins, :conference_losses, :points_for, :points_against,
                     :conference_points_for, :conference_points_against)
    }
  end
end
