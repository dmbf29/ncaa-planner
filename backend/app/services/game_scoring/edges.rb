module GameScoring
  # Local-only: where the plays after touchdowns end and where the game itself ends in a stream recording, from
  # <recording>.edges.json (tools/scouting/game_edges.py). Empty when that file hasn't been made.
  class Edges
    def initialize(source)
      path = Recordings::STREAMS_DIR.join("#{source}.edges.json")
      @data = path.file? ? JSON.parse(path.read) : {}
    end

    # Video second the extra point / two-point try after the touchdown logged at `score_time` is over, or nil.
    def conversion_end(score_time)
      entry = @data.fetch("conversions", []).find { |conversion| (conversion["score_time"] - score_time).abs < 1 }
      entry && entry["end"]
    end

    # Video second the "Final" card ends; everything after it is player-of-the-game screens and menus. Nil when not found.
    def final_end
      @data.dig("final", "end")
    end
  end
end
