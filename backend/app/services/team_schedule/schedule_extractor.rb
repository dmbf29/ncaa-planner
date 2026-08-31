module TeamSchedule
  # Extracts any team's full-season schedule screen — not just coached
  # teams', since this is also how a coach scouts an upcoming opponent
  # (record, ratings, last result) before they've ever controlled them.
  # header record/prestige/ratings, plus every week's row. The team itself
  # is read off the header (name next to the logo) rather than picked by
  # the user beforehand, same fallback-to-manual-correction pattern as an
  # unmatched opponent elsewhere.
  #
  # Row identity is the WEEK column's label (e.g. "3", "Conf Champ", "Bowl
  # Week 1") rather than opponent names, since it's always visible and
  # unambiguous, unlike WeekScheduleExtractor's away/home-name join key.
  # resolve_week maps that label back to a real Week deterministically
  # (Season always creates weeks 0-14 regular season, 15 conference
  # championship, 16-19 bowl weeks — see Season#create_weeks) rather than
  # asking the model to guess internal week numbers for the special weeks.
  #
  # The TIME(ET)/RESULT column prints the winning score first regardless of
  # which team's screen you're looking at (confirmed against real
  # screenshots the same way the Top25 poll's LAST WEEK column was) — so, per
  # the same fix applied there, first_score/second_score are read as plain
  # printed digits and the actual team/opponent score is derived from the
  # W/L result in Ruby, not guessed by the model.
  class ScheduleExtractor
    include CollegeMatching

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game team-schedule screenshots and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images, season:)
      return empty_result if images.blank?

      header = fetch_header(images)
      matchups_by_label = fetch_matchups(images).index_by { |row| row["week_label"] }
      results_by_label = fetch_results(images).index_by { |row| row["week_label"] }

      rows = (matchups_by_label.keys | results_by_label.keys).filter_map do |label|
        build_row(season, label, matchups_by_label[label], results_by_label[label])
      end

      {
        college_id: resolve_college(header["team_raw_name"], header["team_college_name"])&.id,
        college_raw_name: header["team_raw_name"],
        wins: header["wins"],
        losses: header["losses"],
        prestige: clamp_prestige(header["prestige"]),
        overall: header["overall"],
        offense: header["offense"],
        defense: header["defense"],
        rows: rows.sort_by { |row| row[:week_number] || Float::INFINITY },
        colleges: colleges_json
      }
    end

    private

    def empty_result
      {
        college_id: nil, college_raw_name: nil, wins: nil, losses: nil, prestige: nil,
        overall: nil, offense: nil, defense: nil, rows: [], colleges: colleges_json
      }
    end

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    # The 0-5-in-0.5-steps constraint can't be enforced in the schema itself
    # — Anthropic's structured output rejects number fields with
    # minimum/maximum/multipleOf — so it's clamped here instead as a safety
    # net against an occasional off-grid reading like 3.7.
    def clamp_prestige(value)
      return nil if value.nil?

      (value.to_f.clamp(0, 5) * 2).round / 2.0
    end

    def fetch_header(images)
      names = college_names
      schema = RubyLLM::Schema.create do
        string :team_raw_name, description: "The team name shown next to the logo at the top of the screen, exactly as shown, e.g. 'UL MONROE'"
        string :team_college_name, enum: names,
               description: "The database college team_raw_name refers to — use your knowledge of team " \
                            "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
        integer :wins, description: "First number in the overall win-loss record next to the team name, e.g. 1 in '1-1 (0-0)'"
        integer :losses, description: "Second number in the overall win-loss record, e.g. 1 in '1-1 (0-0)' " \
                                      "(the number right after the dash, not the conference record inside the parentheses)"
        number :prestige, description: "Total of the 5 star-rating icons next to the team name. Each icon is 0 " \
                                       "(empty outline), 0.5 (half-filled), or 1 (fully filled) — sum all 5 icons " \
                                       "for a value from 0 to 5 in increments of 0.5, e.g. 3.5 for three full stars " \
                                       "and one half star, or 0 if all 5 are empty outlines. Never report a value " \
                                       "outside 0-5, and always in steps of 0.5 (never e.g. 3.2 or 3.7)."
        integer :overall, description: "The number in the 'OVR' badge"
        integer :offense, description: "The number in the 'OFF' badge"
        integer :defense, description: "The number in the 'DEF' badge"
      end
      chat.with_schema(schema).ask(
        "Read the team header at the top of this schedule screenshot: the win-loss record, the star " \
        "rating, and the OVR/OFF/DEF badges.", with: images
      ).content
    end

    def fetch_matchups(images)
      names = college_names
      schema = RubyLLM::Schema.create do
        array :weeks, description: "One entry per row in the WEEK column, top to bottom across all images — every row, including BYE weeks." do
          object do
            string :week_label, description: "Exactly what's shown in the WEEK column for this row, e.g. '0', '3', 'Conf Champ', or 'Bowl Week 1'"
            boolean :is_bye, description: "True if the OPPONENT column just says 'BYE'"
            string :opponent_raw_name, required: false, description: "Opponent name exactly as shown in the OPPONENT column. Omit if is_bye is true."
            string :opponent_college_name, required: false, enum: names,
                   description: "The database college opponent_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a " \
                                "plausible match. Omit entirely if is_bye is true."
            boolean :is_away, description: "True if the row shows 'at' before the opponent name (this team " \
                                           "travels). False for 'vs' rows, and false if is_bye is true."
            integer :month, required: false, description: "Month number from the DATE column, e.g. 9 for 'Sep 19'. Omit if is_bye or no date is shown."
            integer :day, required: false, description: "Day of month from the DATE column. Omit if is_bye or no date is shown."
          end
        end
      end
      raw = chat.with_schema(schema).ask(
        "This is a full-season schedule for one team, split across multiple images if needed. Read every " \
        "row in the WEEK, OPPONENT, and DATE columns, top to bottom across all images.", with: images
      ).content
      Array(raw["weeks"]).select { |row| row.is_a?(Hash) && row["week_label"].present? }
    end

    def fetch_results(images)
      schema = RubyLLM::Schema.create do
        array :weeks, description: "One entry per row in the WEEK column — match rows up by the same week label." do
          object do
            string :week_label, description: "Same week label as shown in the WEEK column, used to line this row up with the matchup data"
            string :status, enum: %w[bye scheduled final], description: "'bye' if the OPPONENT column says BYE, " \
                                                                        "'final' if TIME(ET)/RESULT shows a final " \
                                                                        "score, 'scheduled' if it shows a kickoff time instead"
            string :time_of_day, required: false, description: "Exactly as shown in TIME(ET)/RESULT when status is 'scheduled', e.g. '4:00 PM'. Omit otherwise."
            string :result, required: false, enum: %w[win loss], description: "Whether this team won or lost, when status is 'final'. Omit otherwise."
            integer :first_score, required: false,
                    description: "The first number shown in TIME(ET)/RESULT when status is 'final', e.g. 38 in " \
                                 "'L 38-31' or 'W 38-31' — read it exactly as printed, do not guess whose score it is. Omit otherwise."
            integer :second_score, required: false, description: "The second number shown in TIME(ET)/RESULT when status is 'final'. Omit otherwise."
          end
        end
      end
      raw = chat.with_schema(schema).ask(
        "This is a full-season schedule for one team, split across multiple images if needed. For each row, " \
        "read the TIME(ET)/RESULT column across all images.", with: images
      ).content
      Array(raw["weeks"]).select { |row| row.is_a?(Hash) && row["week_label"].present? }
    end

    # Season always creates weeks 0-14 as plain-numbered regular season,
    # week 15 as the conference championship (no name set), and weeks 16-19
    # named exactly "Bowl Week 1".."Bowl Week 4" — see Season#create_weeks.
    # That fixed mapping is looked up here rather than asked of the model,
    # which has no way to know the internal week numbering for the special
    # weeks from the image alone.
    def resolve_week(season, raw_label)
      return nil if raw_label.blank?

      normalized = raw_label.strip
      return season.weeks.find_by(number: normalized.to_i) if normalized.match?(/\A\d+\z/)
      return season.weeks.find_by(conference_championship: true) if normalized.match?(/conf(erence)?\s*champ/i)

      season.weeks.find { |week| week.name.present? && week.name.casecmp?(normalized) }
    end

    def build_row(season, label, matchup, result)
      week = resolve_week(season, label)
      return nil unless week

      is_bye = !!matchup&.fetch("is_bye", false) || result&.fetch("status", nil) == "bye"
      return bye_row(week, label) if is_bye

      raw_name = matchup&.fetch("opponent_raw_name", nil)
      scores = resolved_scores(result)

      {
        week_id: week.id,
        week_number: week.number,
        week_label: label,
        is_bye: false,
        opponent_raw_name: raw_name,
        opponent_college_id: resolve_college(raw_name, matchup&.fetch("opponent_college_name", nil))&.id,
        is_away: !!matchup&.fetch("is_away", false),
        month: matchup&.fetch("month", nil),
        day: matchup&.fetch("day", nil),
        time_of_day: result&.fetch("time_of_day", nil),
        team_score: scores[:team_score],
        opponent_score: scores[:opponent_score]
      }
    end

    def bye_row(week, label)
      {
        week_id: week.id, week_number: week.number, week_label: label, is_bye: true,
        opponent_raw_name: nil, opponent_college_id: nil, is_away: false,
        month: nil, day: nil, time_of_day: nil, team_score: nil, opponent_score: nil
      }
    end

    # The printed numbers are (winning score, losing score) in that order,
    # independent of whose row they're printed on — see the class comment.
    def resolved_scores(result_row)
      result = result_row&.fetch("result", nil)
      first_score = result_row&.fetch("first_score", nil)
      second_score = result_row&.fetch("second_score", nil)
      return { team_score: nil, opponent_score: nil } if result.nil? || first_score.nil? || second_score.nil?

      winning_score, losing_score = [ first_score, second_score ].minmax.reverse
      result == "win" ? { team_score: winning_score, opponent_score: losing_score } :
        { team_score: losing_score, opponent_score: winning_score }
    end
  end
end
