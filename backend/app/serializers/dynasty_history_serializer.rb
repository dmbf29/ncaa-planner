# The league's past, as facts: who won the national title and each conference, who won the big awards, how our coached
# programs did, and the series between our coaches. It exists so the podcast hosts know what is already history (a
# second Sun Belt Heisman winner is not a first; the reigning champion is not an upstart). Every count is computed
# here rather than left for the model to work out.
#
# Only seasons before `season` are included, plus `season` itself when `include_current` is set (for shows that air
# after it ended). The current season's own events belong to the episode's own source document.
class DynastyHistorySerializer
  # Awards listed in full every season; any other award only shows up when our conference or a coached program won it.
  HEADLINE_AWARDS = [ "Heisman Trophy", "Maxwell Award", "Walter Camp Award", "Bear Bryant COTY Award" ].freeze

  def initialize(season, include_current: false, with_chronicles: true)
    @season = season
    @include_current = include_current
    @with_chronicles = with_chronicles
  end

  def as_json
    {
      through_year: seasons.map(&:year).max,
      our_conference: our_conference,
      seasons: seasons.map { |season| season_json(season) },
      series: series_json
    }
  end

  def seasons
    @seasons ||= begin
      scope = @season.dynasty.seasons
      scope = @include_current ? scope.where(year: ..@season.year) : scope.where(year: ...@season.year)
      scope.order(:year).to_a
    end
  end

  private

  # The conference most of our coached programs play in, per the latest season on record.
  def our_conference
    @our_conference ||= begin
      latest = [ @season, *seasons ].max_by(&:year)
      latest.college_seasons.where.not(coach_id: nil).group(:conference).order(Arel.sql("COUNT(*) DESC")).count.keys.first
    end
  end

  def season_json(season)
    {
      year: season.year,
      chronicle: (season.chronicle.presence if @with_chronicles),
      national_champion: national_title(season),
      conference_champions: conference_champions(season),
      awards: awards(season),
      our_programs: our_programs(season)
    }
  end

  def weeks_by_season
    @weeks_by_season ||= Week.where(season_id: seasons.map(&:id)).group_by(&:season_id)
  end

  def games_for(season, weeks)
    Game.where(week_id: weeks.map(&:id)).includes(:home_college, :away_college, :college_game_stats)
  end

  # { winner:, loser:, winner_score:, loser_score: } for a played game, nil for one that hasn't been or ended level.
  def result(game)
    scores = game.college_game_stats.index_by(&:college_id)
    home = scores[game.home_college_id]&.final_score
    away = scores[game.away_college_id]&.final_score
    return nil if home.nil? || away.nil? || home == away

    home_won = home > away
    { winner: (home_won ? game.home_college : game.away_college).name, loser: (home_won ? game.away_college : game.home_college).name,
      winner_score: [ home, away ].max, loser_score: [ home, away ].min, winner_college_id: (home_won ? game.home_college_id : game.away_college_id) }
  end

  def national_title(season)
    weeks = weeks_by_season[season.id].to_a.select(&:post_season)
    final = games_for(season, weeks).find { |game| game.cfp_round == "championship" }
    return nil unless final && (outcome = result(final))

    outcome.slice(:winner, :loser, :winner_score, :loser_score)
  end

  # One entry per conference title game (a conference championship week game between two teams of one conference).
  def conference_champions(season)
    weeks = weeks_by_season[season.id].to_a.select(&:conference_championship)
    conferences = season.college_seasons.pluck(:college_id, :conference).to_h
    games_for(season, weeks).filter_map do |game|
      conference = conferences[game.home_college_id]
      next if conference.blank? || conference != conferences[game.away_college_id]
      next unless (outcome = result(game))

      outcome.slice(:winner, :loser, :winner_score, :loser_score).merge(conference: conference)
    end
  end

  def award_rows(season)
    @award_rows ||= {}
    @award_rows[season.id] ||= season.season_awards.includes(:award, :coach, student_season: [ :student, { college_season: :college } ]).to_a
  end

  def coached_college_ids(season)
    @coached_college_ids ||= {}
    @coached_college_ids[season.id] ||= season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def awards(season)
    award_rows(season).filter_map do |row|
      entry = award_entry(row)
      next unless HEADLINE_AWARDS.include?(entry[:award]) || entry[:conference] == our_conference || coached_college_ids(season).include?(entry[:college_id])

      entry.except(:college_id)
    end.sort_by { |entry| [ HEADLINE_AWARDS.index(entry[:award]) || HEADLINE_AWARDS.size, entry[:award] ] }
  end

  def award_entry(row)
    if (student_season = row.student_season)
      college_season = student_season.college_season
      { award: row.award.name, name: student_season.student.name, position: student_season.position,
        college: college_season.college.name, college_id: college_season.college_id, conference: college_season.conference }
    else
      # A coach award: the coach's program that season, if they had one.
      college_season = row.coach.college_seasons.find_by(season_id: row.season_id)
      { award: row.award.name, name: row.coach.name, position: "Head coach", college: college_season&.college&.name,
        college_id: college_season&.college_id, conference: college_season&.conference }
    end
  end

  # How each program with one of our coaches finished the season, with its coach and any titles.
  def our_programs(season)
    champion = national_title(season)&.fetch(:winner)
    conference_winners = conference_champions(season).map { |c| c[:winner] }
    season.college_seasons.where.not(coach_id: nil).includes(:college, :coach).sort_by { |cs| cs.college.name }.map do |cs|
      { college: cs.college.name, coach: cs.coach.name, wins: cs.wins, losses: cs.losses, conference: cs.conference,
        conference_champion: conference_winners.include?(cs.college.name), national_champion: cs.college.name == champion }
    end
  end

  # Head-to-head records between programs of our coaches, over the seasons covered. Orders each pair by name.
  def series_json
    ids = seasons.flat_map { |season| coached_college_ids(season).to_a }.uniq
    return [] if ids.size < 2

    games = Game.where(week_id: weeks_by_season.values.flatten.map(&:id), home_college_id: ids, away_college_id: ids)
                .includes(:home_college, :away_college, :college_game_stats)
    tallies = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    games.each do |game|
      next unless (outcome = result(game))

      pair = [ game.home_college.name, game.away_college.name ].sort
      tallies[pair][outcome[:winner]] += 1
    end
    tallies.map { |(a, b), wins| { teams: [ a, b ], wins: { a => wins[a], b => wins[b] } } }
  end
end
