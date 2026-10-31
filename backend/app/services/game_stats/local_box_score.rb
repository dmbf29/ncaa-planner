module GameStats
  # Turns what tools/capture/read_box_score.py read off the box score pages (the raw text of every value)
  # into CollegeGameStat fields, the same [{ team:, fields: }] BoxScoreExtractor builds from the AI.
  #
  # Returns nil (so the caller asks the AI instead) unless the numbers can be trusted: every row must have been
  # read for both teams on the two pages, the teams must match this game's, and the totals must add up
  # (quarters = final, rushing + passing yards = total offense, + returns = total yards, fumbles + INTs =
  # turnovers). A misread digit breaks one of those sums almost every time.
  class LocalBoxScore
    ROW_LABELS = [
      "Score", "First Downs", "Total Offense", "Total Plays", "Yards Per Play", "Rushes - Yards - TDs", "Yards Per Rush",
      "Comp - Att - TDs", "Yards Per Pass", "Passing Yards", "3rd Down Conv.", "4th Down Conv.", "2-Point Conv.",
      "Red Zone TD-FG-%", "Turnovers", "Fumble Lost", "Interceptions", "PR Yards", "KR Yards", "Total Yards",
      "Punts - Avg", "Penalties - Yards", "T.O.P"
    ].freeze
    NUMBER = /-?\d+(?:\.\d+)?/

    attr_reader :reason

    def initialize(home_college:, away_college:)
      @colleges = [ home_college, away_college ]
    end

    # pages: the raw read_box_score results, one per screenshot.
    def call(pages)
      pages = Array(pages)
      return fail_with("no pages were read") if pages.empty? || pages.any?(&:nil?)

      teams = match_teams(pages) or return nil
      rows = pages.map { |page| page["rows"] }.reduce({}) { |all, page_rows| all.merge(page_rows) { |_label, a, b| a.compact.size >= b.compact.size ? a : b } }
      missing = ROW_LABELS.reject { |label| rows[label]&.size == 2 && rows[label].none?(&:blank?) }
      return fail_with("couldn't read #{missing.join(', ')}") if missing.any?

      # Both pages show the line score; a page where a lone 0 quarter went unread has fewer entries.
      line_score = pages.map { |page| page["line_score"] }.select { |scores| scores&.size == 2 }.max_by { |scores| scores.sum(&:size) } or return fail_with("no line score")
      return fail_with("line score incomplete") unless line_score.all? { |scores| scores.key?("Final") && (1..4).all? { |quarter| scores.key?(quarter.to_s) } }

      entries = [ 0, 1 ].map do |side|
        fields = side_fields(rows, side).merge(line_score_fields(line_score[side]))
        { team: teams[side].name, fields: fields.compact }
      end
      return nil unless consistent?(entries, rows)

      entries
    rescue ArgumentError, TypeError => e
      fail_with("unparseable value (#{e.message})")
    end

    private

    def fail_with(message)
      @reason = message
      nil
    end

    # The college on each side, [left, right]. A panel name matches a college by containment ("JAMES MADISON"
    # in "James Madison"); if only one side matches, the other side is the other college.
    def match_teams(pages)
      page = pages.find { |candidate| candidate["left_team"] && candidate["right_team"] }
      return fail_with("team names not found") unless page

      left = @colleges.find { |college| same_team?(page["left_team"], college.name) }
      right = @colleges.find { |college| same_team?(page["right_team"], college.name) }
      left ||= (@colleges - [ right ]).first if right
      right ||= (@colleges - [ left ]).first if left
      return fail_with("panel names #{page['left_team']} / #{page['right_team']} don't match this game") unless left && right && left != right

      [ left, right ]
    end

    # "GA SOUTHERN" is Georgia Southern, "APP ST." Appalachian State: every word on the panel must start a
    # distinct word of the college's name, in order.
    def same_team?(panel_text, name)
      return true if squash(panel_text) == squash(name)

      remaining = words(name)
      words(panel_text).all? do |word|
        index = remaining.index { |candidate| candidate.start_with?(word) }
        remaining = remaining.drop(index + 1) if index
        index
      end && words(panel_text).size == words(name).size
    end

    def words(text)
      text.to_s.downcase.scan(/[a-z0-9]+/)
    end

    def squash(text)
      text.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end

    def side_fields(rows, side)
      value = ->(label) { rows[label][side].to_s.strip }
      fields = {}
      fields[:final_score] = int(value["Score"])
      fields[:first_downs] = int(value["First Downs"])
      fields[:total_offense] = int(value["Total Offense"])
      fields[:total_plays] = int(value["Total Plays"])
      fields[:yards_per_play] = float(value["Yards Per Play"])
      fields[:rushes], fields[:rushing_yards], fields[:rushing_tds] = triple(value["Rushes - Yards - TDs"])
      fields[:yards_per_rush] = float(value["Yards Per Rush"])
      fields[:passing_completions], fields[:passing_attempts], fields[:passing_tds] = triple(value["Comp - Att - TDs"])
      fields[:yards_per_pass] = float(value["Yards Per Pass"])
      fields[:passing_yards] = int(value["Passing Yards"])
      fields[:third_down_conversions], fields[:third_down_attempts] = pair(value["3rd Down Conv."])
      fields[:fourth_down_conversions], fields[:fourth_down_attempts] = pair(value["4th Down Conv."])
      fields[:two_point_conversions], fields[:two_point_attempts] = pair(value["2-Point Conv."])
      fields[:red_zone_tds], fields[:red_zone_field_goals], fields[:red_zone_success_percentage] = red_zone(value["Red Zone TD-FG-%"])
      fields[:turnovers] = int(value["Turnovers"])
      fields[:fumbles_lost] = int(value["Fumble Lost"])
      fields[:interceptions_thrown] = int(value["Interceptions"])
      fields[:punt_return_yards] = int(value["PR Yards"])
      fields[:kick_return_yards] = int(value["KR Yards"])
      fields[:total_yards] = int(value["Total Yards"])
      fields[:punts] = pair(value["Punts - Avg"]).first
      fields[:penalties], fields[:penalty_yards] = pair(value["Penalties - Yards"])
      fields[:time_of_possession] = clock(value["T.O.P"])
      fields
    end

    def line_score_fields(scores)
      quarters = (1..4).to_h { |quarter| [ :"points_in_quarter_#{quarter}", int(scores[quarter.to_s]) ] }
      overtime = scores.except("1", "2", "3", "4", "Final").values.sum { |points| int(points) }
      quarters.merge(points_in_overtime: (overtime if scores.keys.any? { |key| !%w[1 2 3 4 Final].include?(key) }))
    end

    def consistent?(entries, rows)
      entries.each_with_index.all? do |entry, side|
        f = entry[:fields]
        line_score_total = (1..4).sum { |quarter| f[:"points_in_quarter_#{quarter}"] } + f[:points_in_overtime].to_i
        checks = {
          "quarters add up to the score" => line_score_total == f[:final_score],
          "total offense = rushing + passing yards" => f[:total_offense] == f[:rushing_yards] + f[:passing_yards],
          "total yards = offense + returns" => f[:total_yards] == f[:total_offense] + f[:punt_return_yards] + f[:kick_return_yards],
          "turnovers = fumbles lost + interceptions" => f[:turnovers] == f[:fumbles_lost] + f[:interceptions_thrown]
        }
        failed = checks.reject { |_name, ok| ok }.keys
        @reason = "side #{side + 1}: #{failed.join('; ')} doesn't hold" if failed.any? && @reason.nil?
        failed.empty?
      end
    end

    def int(text)
      Integer(text.to_s.strip.delete(","), 10)
    end

    def float(text)
      Float(text.to_s.strip)
    end

    # "31-127-0" -> [31, 127, 0]; the middle number (yards) can be negative: "10--3-0".
    def triple(text)
      match = text.to_s.delete(" ").match(/\A(\d+)-(-?\d+)-(\d+)\z/) or raise ArgumentError, "expected a-b-c, got #{text.inspect}"
      match.captures.map { |number| Integer(number, 10) }
    end

    # "5-10 (50%)" / "0 - 0.0" / "1-5" -> the first two numbers.
    def pair(text)
      match = text.to_s.delete(" ").match(/\A(\d+)-(-?#{NUMBER})/) or raise ArgumentError, "expected a-b, got #{text.inspect}"
      [ Integer(match[1], 10), match[2].to_f % 1 == 0 ? match[2].to_i : match[2].to_f ]
    end

    # "1-2-60 %" -> [1, 2, 60.0]
    def red_zone(text)
      match = text.to_s.delete(" ").match(/\A(\d+)-(\d+)-(#{NUMBER})%?\z/) or raise ArgumentError, "expected a-b-pct, got #{text.inspect}"
      [ Integer(match[1], 10), Integer(match[2], 10), match[3].to_f ]
    end

    # "12:00" -> seconds
    def clock(text)
      match = text.to_s.strip.match(/\A(\d+):(\d{2})\z/) or raise ArgumentError, "expected m:ss, got #{text.inspect}"
      (match[1].to_i * 60) + match[2].to_i
    end
  end
end
