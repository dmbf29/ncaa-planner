module PlayersOfTheWeek
  # Extracts National/Conference Player of the Week screenshots. Unlike the
  # Heisman/All-American screens, each image is fully self-contained: one
  # scope (a conference name or "National" in the header) with exactly one
  # offensive and one defensive winner, so a single call per image is
  # enough — no separate classification pass, no variable-length array.
  #
  # The screen never shows the winner's own team as text, only a logo, so
  # college resolution instead goes through GameCollegeResolver using the
  # opponent name + score that IS shown as text (e.g. "vs FCS Southeast (W
  # 27-20)"). The same enum-vs-raw-text caution CollegeMatching documents
  # applies to that opponent name too, so both fields are captured here.
  #
  # The week is read off the screen too (top-right badge, e.g. "SEASON WEEK
  # 1") rather than picked by the user beforehand — matched against the
  # season's weeks by number. If it can't be parsed/matched, the row is left
  # unresolved for manual selection in the review UI, same fallback pattern
  # as an unmatched college.
  class Extractor
    include CollegeMatching

    SEASON_WEEK_PATTERN = /\Aseason\s+week\s+(\d+)\z/i

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game "Player of the Week" screenshots and
      transcribing the exact values shown. Only report a value if you can actually see it — never guess.
      Each screenshot shows exactly one offensive and one defensive winner for a single conference (or
      "National").
    PROMPT

    def call(images, season:)
      return { groups: [], colleges: colleges_json } if images.blank?

      rows = Array(images).flat_map { |image| extract_image(image, season) }
      { groups: group_rows(rows), colleges: colleges_json }
    end

    private

    def extract_image(image, season)
      raw = fetch(image)
      return [] if raw.blank?

      week = resolve_week(season, raw["week_label"])
      resolver = GameCollegeResolver.new(week) if week

      Array(raw["sides"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row, raw, week, resolver) }
    end

    # Retry once on an empty/partial response — same cheap insurance the
    # other extractors use.
    def fetch(image)
      raw = fetch_once(image)
      raw = fetch_once(image) if Array(raw["sides"]).size < 2
      raw
    end

    def fetch_once(image)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(schema)
      chat.ask(prompt, with: [ image ]).content
    end

    def schema
      names = college_names
      RubyLLM::Schema.create do
        string :week_label, description: "The week badge shown in the top-right corner, exactly as shown, e.g. 'SEASON WEEK 1'"
        boolean :scope_national, description: "True if the header badge says 'NATIONAL', false if it names a conference."
        string :scope_conference_label, required: false,
               description: "The conference name shown in the header badge, exactly as shown. Omit if scope_national is true."
        array :sides, description: "Exactly two entries: one offensive winner, one defensive winner." do
          object do
            string :side, enum: %w[offensive defensive], description: "Which section this entry came from."
            string :first_name, description: "Player's first name"
            string :last_name, description: "Player's last name (include suffixes like Jr./III here, not in first_name)"
            string :position, description: "The position abbreviation shown next to the player's name, e.g. 'FS', 'HB'"
            string :stat_line, description: "The full stat line text shown below the result, exactly as shown, joined into one string"
            string :opponent_raw_name, description: "The opponent name shown next to the result, exactly as shown, e.g. 'FCS Southeast'"
            string :opponent_matched_name, enum: names,
                   description: "The database college that opponent_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
            string :result, enum: %w[W L], description: "Whether the PLAYER'S OWN team won or lost that game"
            integer :team_score, description: "The player's own team's score in that result, e.g. 27 in '(W 27-20)'"
            integer :opponent_score, description: "The opponent's score in that result, e.g. 20 in '(W 27-20)'"
          end
        end
      end
    end

    def prompt
      "This is a National or Conference Player of the Week screenshot. Read the week badge in the top-right " \
        "and the scope badge in the top-left, then read both the DEFENSIVE and OFFENSIVE entries."
    end

    # Only trusts the literal "SEASON WEEK N" form for a number match — a
    # bare "WEEK N" also appears in post-season badges (e.g. "BOWL WEEK 1")
    # and would otherwise misresolve to regular-season week N. Anything else
    # falls back to an exact match against a week's name (covers
    # "Conference Championship", "Bowl Week 1", etc.).
    def resolve_week(season, raw_label)
      return nil if raw_label.blank?

      normalized = raw_label.strip
      if (match = normalized.match(SEASON_WEEK_PATTERN))
        return season.weeks.find_by(number: match[1].to_i)
      end

      season.weeks.find { |week| week.name.present? && week.name.casecmp?(normalized) }
    end

    def build_row(row, raw, week, resolver)
      college = resolver&.resolve(
        opponent_raw_name: row["opponent_raw_name"],
        opponent_matched_name: row["opponent_matched_name"],
        team_score: row["team_score"],
        opponent_score: row["opponent_score"]
      )

      {
        week_id: week&.id,
        week_label: raw["week_label"],
        national: !!raw["scope_national"],
        conference: raw["scope_national"] ? nil : raw["scope_conference_label"],
        side: row["side"],
        first_name: row["first_name"],
        last_name: row["last_name"],
        position: row["position"],
        stat_line: row["stat_line"],
        college_id: college&.id,
        opponent_context: opponent_context(row),
        class_year: nil
      }
    end

    def opponent_context(row)
      return nil if row["opponent_raw_name"].blank?

      "vs #{row['opponent_raw_name']} (#{row['result']} #{row['team_score']}-#{row['opponent_score']})"
    end

    def group_rows(rows)
      rows.group_by { |row| [ row[:week_id], row[:national], row[:conference] ] }.map do |(week_id, national, conference), group_rows|
        { week_id: week_id, week_label: group_rows.map { |row| row[:week_label] }.compact.first,
          national: national, conference: conference, rows: group_rows }
      end
    end
  end
end
