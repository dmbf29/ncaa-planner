# Full conference standings table for a season, grouped by conference —
# every college with a CollegeSeason row, not just coached teams, since
# standings are league-wide context. Sorted by conference win % then
# overall win % within each conference, matching how a real standings
# table reads.
class ConferenceStandingsSerializer
  def initialize(season)
    @season = season
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
           .joins(:college)
           .group_by { |cs| cs.college.conference }
           .sort_by { |conference, _rows| conference.to_s }
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
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
      teams: rows.sort_by { |cs| [ -win_pct(cs.conference_wins, cs.conference_losses), -win_pct(cs.wins, cs.losses) ] }
                 .map { |cs| team_json(cs) }
    }
  end

  def win_pct(wins, losses)
    total = wins.to_i + losses.to_i
    return 0.0 if total.zero?

    wins.to_f / total
  end

  def team_json(college_season)
    {
      id: college_season.id,
      college: { id: college_season.college.id, name: college_season.college.name },
      coach: college_season.coach && { id: college_season.coach.id, name: college_season.coach.name },
      coached_by_us: coached_college_ids.include?(college_season.college_id),
      rank: rank_for_college(college_season.college_id),
      wins: college_season.wins,
      losses: college_season.losses,
      conference_wins: college_season.conference_wins,
      conference_losses: college_season.conference_losses,
      points_for: college_season.points_for,
      points_against: college_season.points_against,
      conference_points_for: college_season.conference_points_for,
      conference_points_against: college_season.conference_points_against
    }
  end
end
