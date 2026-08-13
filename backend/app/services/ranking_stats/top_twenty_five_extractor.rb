module RankingStats
  # Extracts a Top 25 poll from however many screenshots it takes to show all
  # 25 rows (the poll doesn't fit in one shot). All images are given to every
  # call, like BoxScoreExtractor does for its fixed 2-team array — but unlike
  # that fixed array, this is a variable-length (up to 25 row) array, so it
  # gets PlayerCategoryExtractor's stricter ~4-field-per-call treatment
  # rather than BoxScoreExtractor's ~9-10, per the empirically-discovered
  # structured-output complexity limit documented on that class. Rows are
  # keyed by `rank` (always visible, 1-25, unambiguous) rather than by team
  # name, since OCR'd names can drift slightly between separate calls.
  class TopTwentyFiveExtractor
    include CollegeMatching

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game Top 25 poll screenshots and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess. A dash ("---")
      means the value isn't set (e.g. an unranked team's "LW" column); leave that field unset.
    PROMPT

    def call(images)
      return { rows: [], colleges: colleges_json } if images.blank?

      standings = fetch_standings(images).index_by { |row| row["rank"] }
      this_week = fetch_this_week(images).index_by { |row| row["rank"] }
      last_week_matchup = fetch_last_week_matchup(images).index_by { |row| row["rank"] }
      last_week_result = fetch_last_week_result(images).index_by { |row| row["rank"] }

      rows = standings.keys.sort.map do |rank|
        build_row(rank, standings[rank], this_week[rank], last_week_matchup[rank], last_week_result[rank])
      end

      { rows: rows, colleges: colleges_json }
    end

    private

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def fetch_standings(images)
      schema = RubyLLM::Schema.create do
        array :rankings, description: "One entry per ranked team, up to 25." do
          object do
            integer :rank, description: "The team's rank (RANK column), 1-25"
            string :college_name, description: "Team name exactly as shown, e.g. 'Ohio State'"
            integer :lw_ranking, required: false, description: "LW column — the team's rank last week, if shown"
            integer :wins, required: false, description: "First number in the W-L column"
            integer :losses, required: false, description: "Second number in the W-L column"
          end
        end
      end
      raw = chat.with_schema(schema).ask(prompt("standings"), with: images).content
      Array(raw["rankings"]).select { |row| row.is_a?(Hash) && row["rank"].is_a?(Integer) }
    end

    def fetch_this_week(images)
      schema = RubyLLM::Schema.create do
        array :this_week, description: "One entry per ranked team's THIS WEEK column, up to 25." do
          object do
            integer :rank, description: "The team's rank (RANK column), 1-25 — matches the standings table"
            string :opponent_name, required: false,
                   description: "This week's opponent name, without any leading rank number or 'at' prefix. " \
                                "Leave unset if the column shows '---' (bye week) or is blank."
            integer :opponent_rank, required: false, description: "Opponent's rank number shown before their name, if any"
            boolean :is_away, required: false,
                    description: "True if the opponent name is prefixed with 'at' (this team travels)"
          end
        end
      end
      raw = chat.with_schema(schema).ask(prompt("this week matchups"), with: images).content
      Array(raw["this_week"]).select { |row| row.is_a?(Hash) && row["rank"].is_a?(Integer) }
    end

    def fetch_last_week_matchup(images)
      schema = RubyLLM::Schema.create do
        array :last_week, description: "One entry per ranked team's LAST WEEK column, up to 25." do
          object do
            integer :rank, description: "The team's rank (RANK column), 1-25 — matches the standings table"
            string :opponent_name, required: false,
                   description: "Last week's opponent name, without any leading rank number, 'at' prefix, or " \
                                "W/L result. Leave unset if the column is blank."
            integer :opponent_rank, required: false, description: "Opponent's rank number shown before their name, if any"
            boolean :is_away, required: false,
                    description: "True if the opponent name is prefixed with 'at' (this team traveled)"
          end
        end
      end
      raw = chat.with_schema(schema).ask(prompt("last week matchups"), with: images).content
      Array(raw["last_week"]).select { |row| row.is_a?(Hash) && row["rank"].is_a?(Integer) }
    end

    # The two score digits are asked for as plain, order-of-appearance values
    # rather than "team_score"/"opponent_score" — the poll always prints the
    # winning score first regardless of which team's row it's in (e.g. both
    # the winner's "W 40-28" row and the loser's "L 40-28" row show "40-28"),
    # so a field asking the model to attribute one number to "this team" is
    # answered wrong for every losing team's row (it just echoes first-number
    # -> team_score without re-deriving from the W/L letter). build_row
    # derives the actual team/opponent scores from `result` instead, which
    # is a plain visual read (the W/L letter) the model gets right.
    def fetch_last_week_result(images)
      schema = RubyLLM::Schema.create do
        array :results, description: "One entry per ranked team's LAST WEEK result, up to 25." do
          object do
            integer :rank, description: "The team's rank (RANK column), 1-25 — matches the standings table"
            string :result, required: false, enum: %w[win loss],
                   description: "Whether this team won or lost last week, if a result is shown"
            integer :first_score, required: false,
                    description: "The first number shown in the score, e.g. 40 in 'W 40-28' or 'L 40-28' — " \
                                 "read it exactly as printed, do not guess whose score it is"
            integer :second_score, required: false,
                    description: "The second number shown in the score, e.g. 28 in 'W 40-28' or 'L 40-28' — " \
                                 "read it exactly as printed, do not guess whose score it is"
          end
        end
      end
      raw = chat.with_schema(schema).ask(prompt("last week results"), with: images).content
      Array(raw["results"]).select { |row| row.is_a?(Hash) && row["rank"].is_a?(Integer) }
    end

    def prompt(focus)
      "These screenshots together show a Top 25 college football poll, split across multiple images " \
        "since it doesn't fit in one. Read every visible row across all images and report the #{focus}."
    end

    def build_row(rank, standing, this_week, last_week_matchup, last_week_result)
      college_name = standing&.fetch("college_name", nil)
      {
        rank: rank,
        college_name: college_name,
        college_id: resolve_college(college_name)&.id,
        lw_ranking: standing&.fetch("lw_ranking", nil),
        wins: standing&.fetch("wins", nil),
        losses: standing&.fetch("losses", nil),
        this_week: opponent_entry(this_week),
        last_week: opponent_entry(last_week_matchup).merge(
          result: last_week_result&.fetch("result", nil),
          **resolved_scores(last_week_result)
        )
      }
    end

    # The printed numbers are (winning score, losing score) in that order,
    # independent of whose row they're printed on — see fetch_last_week_result.
    def resolved_scores(result_row)
      result = result_row&.fetch("result", nil)
      first_score = result_row&.fetch("first_score", nil)
      second_score = result_row&.fetch("second_score", nil)
      return { team_score: nil, opponent_score: nil } if result.nil? || first_score.nil? || second_score.nil?

      winning_score, losing_score = [ first_score, second_score ].minmax.reverse
      result == "win" ? { team_score: winning_score, opponent_score: losing_score } :
        { team_score: losing_score, opponent_score: winning_score }
    end

    def opponent_entry(row)
      name = row&.fetch("opponent_name", nil)
      {
        opponent_name: name,
        opponent_college_id: resolve_college(name)&.id,
        opponent_rank: row&.fetch("opponent_rank", nil),
        is_away: row&.fetch("is_away", nil) || false
      }
    end
  end
end
