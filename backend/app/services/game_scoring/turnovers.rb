module GameScoring
  # Local-only: the turnovers of one game, from <recording>.keyplays.json (tools/scouting/key_plays.py). The scoreboard flashes
  # a red FUMBLE label, but an interception shows nothing, so a turnover is also a change of possession (the scoreboard's ball
  # marker jumping sides) on downs 1-3, away from kickoffs, breaks and the scoring play that causes the kickoff. Those can't tell
  # an interception from a lost fumble that showed no label, so they are just "Turnover".
  #
  # Each event: time (video seconds), quarter, clock, team (the team that gave the ball up), kind ("Turnover" or "Fumble"),
  # lost (Fumble only: possession changed within FUMBLE_JOIN seconds) and the home/away score when it happened.
  class Turnovers
    DOWNS = (1..3)
    BEFORE_SCORE = 15
    AFTER_SCORE = 75
    FUMBLE_JOIN = 20

    def initialize(game, report, key_plays_path, home_is_left)
      @game = game
      @report = report
      @key_plays_path = key_plays_path
      @home_is_left = home_is_left
    end

    def call
      return [] unless @key_plays_path.file?

      key_plays = JSON.parse(@key_plays_path.read)
      changes = key_plays.fetch("possession_changes", [])
      fumbles = key_plays["plays"].select { |play| play["kind"] == "Fumble" }.map { |play| fumble_event(play, changes) }
      turnovers = changes.select { |change| turnover?(change) && fumbles.none? { |fumble| joined?(fumble["time"], change["time"]) } }
                         .map { |change| turnover_event(change) }
      (fumbles + turnovers).sort_by { |event| event["time"] }
    end

    private

    def turnover?(change)
      DOWNS.cover?(change["down"].to_i) && !change["kickoff"] && !change["break"] &&
        scoring_times.none? { |time| (time - BEFORE_SCORE..time + AFTER_SCORE).cover?(change["time"]) }
    end

    def joined?(fumble_time, change_time)
      (fumble_time..fumble_time + FUMBLE_JOIN).cover?(change_time)
    end

    def scoring_times
      @scoring_times ||= @report["scoring"].map { |play| play["time"].to_f }
    end

    # The team with the ball when the label showed fumbled it; it lost the ball if possession changed right after.
    def fumble_event(play, changes)
      lost = changes.any? { |change| joined?(play["time"], change["time"]) && change["to"] != play["side"] }
      event(play, team_for(play["side"]), "Fumble").merge("lost" => lost)
    end

    # The side that has the ball afterwards gained it; the other side turned it over.
    def turnover_event(change)
      event(change, team_for(opposite(change["to"])), "Turnover")
    end

    def event(source, team, kind)
      home_score, away_score = scores_for(source)
      { "time" => source["time"], "quarter" => source["quarter"] || quarter_near(source["time"]), "clock" => source["clock"], "team" => team,
        "kind" => kind, "home_score" => home_score, "away_score" => away_score }.compact
    end

    def team_for(side)
      return nil if side.nil?

      (side == "L") == @home_is_left ? @game.home_college.name : @game.away_college.name
    end

    def opposite(side)
      side == "L" ? "R" : "L"
    end

    # [home, away]: the bar's own reading when there was one, else the score after the last scoring play before it.
    def scores_for(source)
      left, right = source.values_at("left_score", "right_score")
      left, right = last_score_before(source["time"]) if left.nil? || right.nil?
      @home_is_left ? [ left, right ] : [ right, left ]
    end

    def last_score_before(time)
      play = @report["scoring"].select { |entry| entry["time"] <= time }.max_by { |entry| entry["time"] }
      play ? play["score"] : [ 0, 0 ]
    end

    def quarter_near(time)
      nearest = @report["scoring"].min_by { |entry| (entry["time"] - time).abs }
      nearest && nearest["quarter"]
    end
  end
end
