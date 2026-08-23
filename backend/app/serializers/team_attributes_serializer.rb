# Every college with a CollegeSeason row for a season, grouped by conference, with the
# team-level rating attributes a coach edits by hand (overall/offense/defense/prestige
# aren't derived from anything in-app — the game doesn't expose them any other way).
class TeamAttributesSerializer
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
           .includes(:college)
           .joins(:college)
           .group_by { |cs| cs.college.conference }
           .sort_by { |conference, _rows| conference.to_s }
  end

  def conference_json(conference, rows)
    {
      conference: conference,
      teams: rows.sort_by { |cs| cs.college.name }.map { |cs| team_json(cs) }
    }
  end

  def team_json(college_season)
    {
      id: college_season.id,
      college: { id: college_season.college.id, name: college_season.college.name },
      overall: college_season.overall,
      offense: college_season.offense,
      defense: college_season.defense,
      prestige: college_season.prestige
    }
  end
end
