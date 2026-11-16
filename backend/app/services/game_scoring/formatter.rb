module GameScoring
  # One shared text rendering of games.scoring_summary (the scoring plays and, when the recording has a key-plays file, the
  # turnovers), so the recap prompt and the podcast markdown say the same thing.
  module Formatter
    module_function

    # [[heading, [line, ...]], ...] in game order, e.g. ["Quarter 1", ["5:30 Georgia Southern touchdown (extra point) - Georgia Southern 7, NC State 0"]]
    def quarters(summary)
      events(summary).group_by { |event| event["quarter"] }.sort_by { |quarter, _| quarter.to_i }.map do |quarter, plays|
        [ quarter.to_i <= 4 ? "Quarter #{quarter}" : "Overtime #{quarter.to_i - 4}", plays.map { |play| line(summary, play) } ]
      end
    end

    # Scores and turnovers together, in the order they happened (older summaries have no video times: score order, then
    # turnovers by clock).
    def events(summary)
      return summary["plays"] if summary["turnovers"].blank?

      all = summary["plays"] + summary["turnovers"]
      return all.sort_by { |event| event["time"] } if all.all? { |event| event["time"] }

      all.each_with_index.sort_by { |event, index| [ event["quarter"].to_i, -clock_seconds(event["clock"]), index ] }.map(&:first)
    end

    def line(summary, play)
      case play["kind"]
      when "Turnover" then "#{prefix(play)} #{play['team']} turnover#{score_suffix(summary, play)}"
      when "Fumble" then "#{prefix(play)} #{play['team']} fumble (#{play['lost'] ? 'lost' : 'recovered'})#{score_suffix(summary, play)}"
      else
        extra = " (#{play['extra']})" if play["extra"]
        approx = " [approximate]" if play["approx"]
        "#{prefix(play)} #{play['team']} #{play['kind'].downcase}#{extra}#{approx}#{score_suffix(summary, play)}"
      end
    end

    def text(summary)
      quarters(summary).map { |heading, lines| "#{heading}:\n#{lines.map { |l| "- #{l}" }.join("\n")}" }.join("\n")
    end

    def prefix(play)
      play["clock"] || "?"
    end

    def score_suffix(summary, play)
      return "" unless play["home_score"] && play["away_score"]

      " - #{summary['home']} #{play['home_score']}, #{summary['away']} #{play['away_score']}"
    end

    def clock_seconds(clock)
      minutes, seconds = clock.to_s.split(":").map(&:to_i)
      minutes.to_i * 60 + seconds.to_i
    end
  end
end
