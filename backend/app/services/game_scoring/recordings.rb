module GameScoring
  # Local-only: the scouting pipeline (tools/scouting/scout.py) leaves a <recording>.scout.json next to every stream
  # recording in streams/, including the scoring plays it read off the broadcast scoreboard. This finds the reports that
  # are about one Game and turns the chosen one into the summary stored on games.scoring_summary.
  #
  # A recording belongs to a game when its last scoreboard reading equals the game's recorded final score (either way
  # round, since the scoreboard's left side isn't always the home team). That also settles which side is which when
  # both teams print the same name (Bulls vs Bulls). `verified` says the plays themselves add up to the final score.
  #
  # A game with no box score yet (a recording attached the day it was played, see Inbox) has no final score to match, so
  # the broadcast's usual layout is assumed (away team on the left) and the summary is marked `provisional` until the box
  # score is saved and it is built again (see refresh).
  class Recordings
    STREAMS_DIR = Rails.root.join("..", "streams").expand_path
    ID_FORMAT = %r{\A[\w-]+/[\w-]+\z}

    Error = Class.new(StandardError)

    # Every attached recording so far has the away team on the scoreboard's left.
    PROVISIONAL_HOME_IS_LEFT = false

    def initialize(game)
      @game = game
    end

    def candidates
      return [] unless final_scores

      Dir[STREAMS_DIR.join("*/*.scout.json")].sort.reverse.filter_map do |path|
        report = JSON.parse(File.read(path))
        next if orientation(report).nil?

        id = recording_id(path)
        { id: id, channel: id.split("/").first, teams: report["teams"], plays: report["scoring"].size,
          verified: verified?(report), final_score: report["scoring"].last&.dig("score") }
      end
    end

    def build(recording_id)
      raise Error, "Unknown recording." unless recording_id.to_s.match?(ID_FORMAT)

      path = STREAMS_DIR.join("#{recording_id}.scout.json")
      raise Error, "No scouting report for that recording." unless path.exist?

      report = JSON.parse(path.read)
      home_is_left = final_scores ? orientation(report) : PROVISIONAL_HOME_IS_LEFT
      raise Error, "That recording's final score doesn't match this game." if home_is_left.nil?

      {
        "source" => recording_id,
        "verified" => verified?(report),
        "provisional" => final_scores ? nil : true,
        "home" => @game.home_college.name,
        "away" => @game.away_college.name,
        "plays" => report["scoring"].map { |play| play_json(play, home_is_left) },
        "turnovers" => Turnovers.new(@game, report, STREAMS_DIR.join("#{recording_id}.keyplays.json"), home_is_left).call
      }
    end

    # Builds the game's summary again from its own recording, once the box score is in (a provisional one assumed the layout).
    # Keeps the old summary when the recording doesn't match the box score.
    def refresh
      summary = @game.scoring_summary
      return unless summary&.dig("provisional") && final_scores

      @game.update!(scoring_summary: build(summary["source"]))
    rescue Error
      nil
    end

    private

    def final_scores
      @final_scores ||= begin
        by_college = @game.college_game_stats.to_h { |stat| [ stat.college_id, stat.final_score ] }
        home, away = by_college.values_at(@game.home_college_id, @game.away_college_id)
        [ home, away ] if home && away
      end
    end

    # true: scoreboard left = home team, false: left = away team, nil: this recording isn't of this game. The last
    # scoreboard reading can be stale or misread (27-17 when the game ended 27-24), so the score after the last
    # scoring play counts too.
    def orientation(report)
      return nil unless final_scores

      scoreboard_pairs(report).each do |pair|
        return true if pair == final_scores
        return false if pair == final_scores.reverse
      end
      nil
    end

    def scoreboard_pairs(report)
      last = report["last_score"]
      [ last && [ last["left"], last["right"] ], report["scoring"].last&.dig("score") ].compact
    end

    def verified?(report)
      last_play = report["scoring"].last
      return false unless last_play
      return scoreboard_pairs(report).first == last_play["score"] unless final_scores

      [ final_scores, final_scores.reverse ].include?(last_play["score"])
    end

    def recording_id(path)
      "#{File.basename(File.dirname(path))}/#{File.basename(path, '.scout.json')}"
    end

    def play_json(play, home_is_left)
      left_score, right_score = play["score"]
      home_scored = (play["side"] == 0) == home_is_left
      {
        "time" => play["time"], "quarter" => play["quarter"], "clock" => play["clock"], "team" => home_scored ? @game.home_college.name : @game.away_college.name,
        "kind" => play["kind"], "points" => play["points"], "extra" => play["extra"], "approx" => play["approx"] || nil,
        "home_score" => home_is_left ? left_score : right_score, "away_score" => home_is_left ? right_score : left_score
      }.compact
    end
  end
end
