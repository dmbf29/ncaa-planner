# End-of-season variant of MidseasonReportCardSerializer. Meant to run
# after the bowl games are played but before the transfer portal opens —
# by then every coached team's played_schedule already covers the entire
# season (regular season, conference championship, and bowl game, since
# scheduled_games doesn't filter those out), and remaining_schedule is
# naturally empty for everyone, so nothing about the shared evidence-
# gathering needs to change. This adds the season-closing content (a
# hardware recap limited to our programs plus the Heisman for national
# context, and each conference's actual champion versus who the numbers
# would have favored), a dedicated bowl-game callout, and re-bases
# Signature Wins/Bad Losses on the opponent's actual final record (and,
# for a loss, our own) instead of a preseason expectation (see
# notable_results_json).
class EndOfSeasonReportCardSerializer < MidseasonReportCardSerializer
  HEADLINE_AWARD = "Heisman Trophy".freeze

  # A win over a team with at least this many wins is a signature win
  # regardless of our own record — an 8-win team is a genuinely good team
  # by any measure, not just relative to us.
  SIGNATURE_WIN_MIN_WINS = 8

  def as_json
    super.merge(
      season_awards: season_awards_json,
      conference_champions: conference_champions_json
    )
  end

  private

  # Per-team All-American honorees (national or conference team, either
  # tier) — a season-ending honor, unlike SeasonAward's individual awards,
  # so it only belongs here, not on the midseason version. Scoped to our
  # own coached teams, unlike SeasonAllAmericansSerializer's full
  # league-wide list, since this rides along inside each team's own
  # report card section.
  def team_json(college_season)
    super.merge(
      all_americans: all_americans_for(college_season.college_id).map { |aa| all_american_json(aa) },
      bowl_games: bowl_games_for(college_season)
    )
  end

  def bowl_games_for(college_season)
    scheduled_games(college_season)
      .select { |g| g[:played] && g[:week].post_season }
      .map { |g| bowl_game_json(g) }
  end

  def bowl_game_json(game)
    {
      week_label: week_label_for(game[:week]),
      home: game[:home],
      opponent: college_json(game[:opponent_college], game[:opponent]&.conference),
      opponent_ratings: ratings_json(game[:opponent]),
      result: game[:result]
    }
  end

  # Signature win: beat another one of our coached teams (always notable
  # for this group's podcast regardless of record), or beat a team that
  # finished with at least SIGNATURE_WIN_MIN_WINS wins outright — a
  # measure of the opponent alone, not relative to us.
  #
  # Bad loss: lost to another one of our coached teams (same reasoning),
  # or lost to a team whose own record makes the loss look worse than a
  # coin flip: if WE finished with a winning record, any loss to a .500-
  # or-worse team qualifies; if we finished at .500 or below ourselves,
  # only a loss to a team with an even worse winning percentage than ours
  # counts — otherwise almost every loss we had would qualify.
  #
  # Either way this replaces MidseasonReportCardSerializer's pregame-lean
  # definition (see pregame_projection) — a preseason expectation isn't
  # the right yardstick once the whole season, including the opponent's,
  # is in the books.
  def notable_results_json(played_games)
    our_wins = played_games.count { |g| g[:result][:won] }
    our_pct = win_pct(our_wins, played_games.size - our_wins)

    signature_wins = played_games.select { |g| g[:result][:won] && signature_win?(g[:opponent]) }
    bad_losses = played_games.select { |g| !g[:result][:won] && bad_loss?(g[:opponent], our_pct) }

    {
      signature_wins: signature_wins.map { |g| notable_game_json(g) },
      bad_losses: bad_losses.map { |g| notable_game_json(g) }
    }
  end

  def notable_game_json(game)
    super.merge(
      opponent_record: opponent_record_json(game[:opponent]),
      opponent_coached_by_us: fellow_coached_opponent?(game[:opponent])
    )
  end

  def opponent_record_json(opponent_college_season)
    return nil unless opponent_college_season

    record = opponent_final_record(opponent_college_season)
    { wins: record[:wins], losses: record[:losses] }
  end

  def signature_win?(opponent_college_season)
    return false unless opponent_college_season

    fellow_coached_opponent?(opponent_college_season) ||
      opponent_final_record(opponent_college_season)[:wins] >= SIGNATURE_WIN_MIN_WINS
  end

  def bad_loss?(opponent_college_season, our_pct)
    return false unless opponent_college_season

    return true if fellow_coached_opponent?(opponent_college_season)

    record = opponent_final_record(opponent_college_season)
    opponent_pct = win_pct(record[:wins], record[:losses])
    our_pct > 0.5 ? opponent_pct <= 0.5 : opponent_pct < our_pct
  end

  def fellow_coached_opponent?(opponent_college_season)
    opponent_college_season.present? && coached_college_ids.include?(opponent_college_season.college_id)
  end

  # Every one of our own coached teams' games gets a box score entered, so
  # deriving a fellow coached team's record from recorded games is
  # reliable. A non-coached opponent's games are only entered when they
  # happen to play one of our coached teams, though — recorded games for
  # them are a small, incomplete slice of their real schedule — so their
  # record instead comes straight from this season's own conference-
  # standings columns (college_season.wins/losses), which reflect their
  # true full season. Falls back to the derived-from-games count only if
  # standings haven't been recorded at all yet.
  def opponent_final_record(college_season)
    @opponent_final_records ||= {}
    @opponent_final_records[college_season.id] ||= if fellow_coached_opponent?(college_season) || standings_missing?(college_season)
      record_json(scheduled_games(college_season).select { |g| g[:played] })
    else
      { wins: college_season.wins, losses: college_season.losses }
    end
  end

  def standings_missing?(college_season)
    college_season.wins.nil? || college_season.losses.nil?
  end

  def all_americans
    @all_americans ||= AllAmerican.where(student_season: StudentSeason.where(college_season: coached_college_seasons))
                                   .includes(student_season: [ :student, { college_season: :college } ])
                                   .to_a
  end

  def all_americans_for(college_id)
    all_americans.select { |aa| aa.student_season.college_season.college_id == college_id }
                 .sort_by { |aa| [ aa.tier, aa.student_season.student.name ] }
  end

  def all_american_json(all_american)
    student_season = all_american.student_season
    {
      name: student_season.student.name,
      position: student_season.position,
      national: all_american.national,
      conference: all_american.conference,
      tier: all_american.tier,
      preseason: all_american.preseason
    }
  end

  def focus_json
    {
      instructions: "End-of-season report cards for our #{coached_college_seasons.size} coached teams — the " \
                    "full season, including the conference championship and bowl game where applicable, is in " \
                    "the books. Each host gives their own final letter grade (A+ to F) for each team based on " \
                    "the evidence below — the app does not compute a grade, and the hosts do not have to agree " \
                    "with each other."
    }
  end

  # Trimmed to what our programs actually won, plus the Heisman regardless
  # of who won it — that's the one award casual college football
  # conversation always references, so it's included for national context
  # even on a season where none of our teams were in the running. Every
  # other national award is left out; the full list belongs to
  # SeasonAllAmericansSerializer-style league-wide views, not our teams'
  # own report cards.
  def season_awards
    @season_awards ||= all_season_awards.select { |sa| our_award?(sa) || sa.award.name == HEADLINE_AWARD }
  end

  def all_season_awards
    @all_season_awards ||= @season.season_awards
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
      coached_by_us: our_recipient_college?(college)
    }
  end

  def our_award?(season_award)
    our_recipient_college?(award_recipient_college(season_award))
  end

  def our_recipient_college?(college)
    college.present? && coached_college_ids.include?(college.id)
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
