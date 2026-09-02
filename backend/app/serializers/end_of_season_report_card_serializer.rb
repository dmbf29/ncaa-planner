# End-of-season variant of MidseasonReportCardSerializer. Meant to run
# after the bowl games are played but before the transfer portal opens —
# by then every coached team's played_schedule already covers the entire
# season (regular season, conference championship, and bowl game, since
# scheduled_games doesn't filter those out), and remaining_schedule is
# naturally empty for everyone, so nothing about the shared evidence-
# gathering needs to change. This only adds the season-closing content: a
# hardware recap (SeasonAward winners connected to our programs) and each
# conference's actual champion versus who the numbers would have favored.
class EndOfSeasonReportCardSerializer < MidseasonReportCardSerializer
  def as_json
    super.merge(
      season_awards: season_awards_json,
      conference_champions: conference_champions_json
    )
  end

  private

  def focus_json
    {
      instructions: "End-of-season report cards for our #{coached_college_seasons.size} coached teams — the " \
                    "full season, including the conference championship and bowl game where applicable, is in " \
                    "the books. Each host gives their own final letter grade (A+ to F) for each team based on " \
                    "the evidence below — the app does not compute a grade, and the hosts do not have to agree " \
                    "with each other."
    }
  end

  def season_awards
    @season_awards ||= @season.season_awards
                               .includes(:award, :coach, student_season: [ :student, { college_season: :college } ])
                               .to_a
                               .sort_by { |sa| sa.award.sort_order }
  end

  def season_awards_json
    season_awards.map { |sa| season_award_json(sa) }
  end

  def season_award_json(season_award)
    college = award_recipient_college(season_award)

    {
      award: season_award.award.name,
      recipient: season_award.recipient_name,
      stat_line: season_award.stat_line,
      college: college && college_json(college, college_conference(college)),
      coached_by_us: college.present? && coached_college_ids.include?(college.id)
    }
  end

  def award_recipient_college(season_award)
    if season_award.student_season
      season_award.student_season.college_season.college
    elsif season_award.coach
      all_college_seasons.find { |cs| cs.coach_id == season_award.coach_id }&.college
    end
  end

  def coached_college_ids
    @coached_college_ids ||= coached_college_seasons.map(&:college_id).to_set
  end

  # college_season.conference (not college.conference) is the source of
  # truth elsewhere in this file since colleges can realign — mirror that
  # here even though season_awards doesn't carry a college_season directly
  # for a coach recipient.
  def college_conference(college)
    all_college_seasons.find { |cs| cs.college_id == college.id }&.conference
  end

  # "Predicted" reuses the same team_strength signal WinTotalsSerializer's
  # champion predictions are built on, so this is a legitimate look-back at
  # that earlier episode's call, not a different opinion. Top 2 on both
  # sides — predicted finalists vs. who actually played in the real
  # conference-championship-week game (Week#conference_championship) —
  # since a real conference championship is a game between two teams, not
  # a single favorite.
  def conference_champions_json
    conferences = coached_college_seasons.filter_map(&:conference).uniq

    conferences.map do |conference|
      ranked = college_seasons_by_conference.fetch(conference, [])
                                             .filter_map { |cs| [ cs, @calculator.team_strength(cs) ] }
                                             .select { |_cs, strength| strength }
                                             .sort_by { |_cs, strength| -strength }
      predicted_finalists = ranked.first(2).map { |cs, _strength| cs }
      actual_result = actual_conference_championship_result(conference)

      conference_champion_json(conference, predicted_finalists, actual_result)
    end
  end

  def conference_champion_json(conference, predicted_finalists, actual_result)
    champion = actual_result && actual_result[:champion]
    runner_up = actual_result && actual_result[:runner_up]
    predicted_ids = predicted_finalists.map(&:college_id)

    {
      conference: conference,
      predicted_finalists: predicted_finalists.map { |cs| conference_champion_entry(cs) },
      actual_champion: champion && conference_champion_entry(champion),
      actual_runner_up: runner_up && conference_champion_entry(runner_up),
      actual_champion_was_top_pick: champion && predicted_finalists.first&.college_id == champion.college_id,
      actual_champion_was_predicted_finalist: champion && predicted_ids.include?(champion.college_id),
      actual_runner_up_was_predicted_finalist: runner_up && predicted_ids.include?(runner_up.college_id)
    }
  end

  def conference_champion_entry(college_season)
    { college: college_json(college_season.college, college_season.conference), coached_by_us: coached_college_ids.include?(college_season.college_id) }
  end

  def conference_championship_week
    return @conference_championship_week if defined?(@conference_championship_week)

    @conference_championship_week = @season.weeks.find_by(conference_championship: true)
  end

  def actual_conference_championship_result(conference)
    return nil unless conference_championship_week

    game = conference_championship_week.games
                                        .includes(:home_college, :away_college, :college_game_stats)
                                        .find { |g| conference_championship_matchup?(g, conference) }
    return nil unless game

    winner_id, loser_id = ranked_college_ids(game)
    return nil unless winner_id

    { champion: college_seasons_by_college_id[winner_id], runner_up: college_seasons_by_college_id[loser_id] }
  end

  def conference_championship_matchup?(game, conference)
    college_seasons_by_college_id[game.home_college_id]&.conference == conference &&
      college_seasons_by_college_id[game.away_college_id]&.conference == conference
  end

  def ranked_college_ids(game)
    stats = game.college_game_stats.index_by(&:college_id)
    home_stat = stats[game.home_college_id]
    away_stat = stats[game.away_college_id]
    return [ nil, nil ] unless home_stat&.final_score && away_stat&.final_score

    home_stat.final_score > away_stat.final_score ? [ game.home_college_id, game.away_college_id ] : [ game.away_college_id, game.home_college_id ]
  end
end
