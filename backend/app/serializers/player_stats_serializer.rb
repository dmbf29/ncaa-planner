# Full player stat lines for some scope within a dynasty — one college, one
# conference, or the whole league ("national") — every season that scope has
# been played, plus a club-history view combining every one of those seasons
# per player. Unlike TeamSeasonStats (single leader per category, for the
# dashboard card), this returns every player's full stat line, grouped into
# the four box-score categories.
#
# Conference membership is a per-CollegeSeason attribute (colleges can
# change conferences season to season), so a conference/national scope is
# resolved fresh per season: "seasons" groups by year, not by CollegeSeason,
# since a non-college scope can span many CollegeSeason rows per year.
class PlayerStatsSerializer
  CATEGORIES = %i[passing rushing receiving defense].freeze

  # Column that decides whether a player belongs in a category's table, and
  # how that table is sorted (best first).
  PRIMARY_FIELD = {
    passing: :passing_yards, rushing: :rushing_yards, receiving: :receiving_yards, defense: :defense_tackles
  }.freeze

  # Rate/derived columns (beyond SUM_FIELDS/MAX_FIELDS) worth showing per category.
  EXTRA_FIELDS = {
    passing: %i[passing_avg passing_rating], rushing: %i[rushing_avg], receiving: %i[receiving_avg], defense: []
  }.freeze

  def initialize(dynasty, college: nil, conference: nil, coached: false)
    @dynasty = dynasty
    @college = college
    @conference = conference
    @coached = coached
  end

  def as_json
    {
      scope: scope_json,
      seasons: seasons_json,
      club_history: club_history_json
    }
  end

  private

  def scope_json
    return { type: "college", college: { id: @college.id, name: @college.name } } if @college
    return { type: "conference", conference: @conference } if @conference
    return { type: "coached" } if @coached

    { type: "national" }
  end

  def college_seasons
    @college_seasons ||= begin
      scope = CollegeSeason.joins(:season).where(seasons: { dynasty_id: @dynasty.id })
      scope = scope.where(college_id: @college.id) if @college
      scope = scope.where(conference: @conference) if @conference
      scope = scope.where(college_id: coached_college_ids) if @coached
      scope.includes(:season).to_a
    end
  end

  # Every college that's had a coach at some point in this dynasty — the
  # same "yours" definition the scope-picker dropdown uses for its "Your
  # Teams" group.
  def coached_college_ids
    @coached_college_ids ||= CollegeSeason.joins(:season)
                                           .where(seasons: { dynasty_id: @dynasty.id })
                                           .where.not(coach_id: nil)
                                           .distinct
                                           .pluck(:college_id)
  end

  def college_season_ids_by_year
    @college_season_ids_by_year ||= college_seasons.group_by { |cs| cs.season.year }
                                                     .transform_values { |rows| rows.map(&:id).to_set }
  end

  def game_stats
    @game_stats ||= StudentGameStat.joins(student_season: :college_season)
                                    .where(college_seasons: { id: college_seasons.map(&:id) })
                                    .includes(student_season: [ :student, { college_season: :college } ])
                                    .to_a
  end

  def seasons_json
    college_season_ids_by_year.keys.sort.map { |year| season_json(year) }
  end

  def season_json(year)
    ids = college_season_ids_by_year[year]
    rows = game_stats.select { |gs| ids.include?(gs.student_season.college_season_id) }
    by_student_season = rows.group_by(&:student_season)

    {
      year: year,
      categories: CATEGORIES.index_with do |category|
        category_rows(category, by_student_season) { |student_season, _rows| season_player_json(student_season) }
      end
    }
  end

  def club_history_json
    by_student = game_stats.group_by { |gs| gs.student_season.student }

    {
      categories: CATEGORIES.index_with do |category|
        category_rows(category, by_student) { |student, rows| history_player_json(student, rows) }
      end
    }
  end

  # `grouped` maps a player key (StudentSeason for a season, Student for club
  # history) to their StudentGameStat rows. Only players with a positive
  # primary stat appear, sorted best-first.
  def category_rows(category, grouped)
    grouped.filter_map do |key, rows|
      totals = PlayerStatTotals.call(rows)
      next unless (totals[PRIMARY_FIELD[category]] || 0).positive?

      yield(key, rows).merge(totals: totals.slice(*fields_for(category)))
    end.sort_by { |row| -row[:totals][PRIMARY_FIELD[category]] }
  end

  def fields_for(category)
    PlayerStatTotals::SUM_FIELDS.fetch(category) + PlayerStatTotals::MAX_FIELDS.fetch(category) +
      EXTRA_FIELDS.fetch(category) + [ :games_played ]
  end

  def season_player_json(student_season)
    {
      student_season_id: student_season.id,
      name: student_season.student.name,
      position: student_season.position,
      class_year: student_season.class_year,
      college: college_json(student_season.college_season.college)
    }
  end

  def history_player_json(student, rows)
    latest_season = rows.map(&:student_season).max_by { |ss| ss.college_season.season.year }
    years = rows.map { |gs| gs.student_season.college_season.season.year }.uniq.sort

    {
      student_id: student.id,
      name: student.name,
      position: latest_season.position,
      years: years,
      college: college_json(latest_season.college_season.college)
    }
  end

  def college_json(college)
    { id: college.id, name: college.name }
  end
end
