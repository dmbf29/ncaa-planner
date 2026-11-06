module GameScoring
  # One shared text rendering of games.scoring_summary, so the recap prompt and the podcast markdown say the same thing.
  module Formatter
    module_function

    # [[heading, [line, ...]], ...] in game order, e.g. ["Quarter 1", ["5:30 Georgia Southern touchdown (extra point) - Georgia Southern 7, NC State 0"]]
    def quarters(summary)
      summary["plays"].group_by { |play| play["quarter"] }.sort.map do |quarter, plays|
        [ quarter <= 4 ? "Quarter #{quarter}" : "Overtime #{quarter - 4}", plays.map { |play| line(summary, play) } ]
      end
    end

    def line(summary, play)
      extra = " (#{play['extra']})" if play["extra"]
      approx = " [approximate]" if play["approx"]
      "#{play['clock'] || '?'} #{play['team']} #{play['kind'].downcase}#{extra}#{approx} - " \
        "#{summary['home']} #{play['home_score']}, #{summary['away']} #{play['away_score']}"
    end

    def text(summary)
      quarters(summary).map { |heading, lines| "#{heading}:\n#{lines.map { |l| "- #{l}" }.join("\n")}" }.join("\n")
    end
  end
end
