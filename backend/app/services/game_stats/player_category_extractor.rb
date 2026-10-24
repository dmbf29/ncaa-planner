module GameStats
  # Extracts StudentGameStat fields for one team's stat category (passing/
  # rushing/receiving/defense) from that category's screenshot(s). The team
  # is known from the caller (images are uploaded per-team), so the model
  # only has to identify the player and category fields, not guess team.
  #
  # Each category is split into two small calls (4-5 optional fields each)
  # and merged by player identity — empirically, a single call asking for
  # ~9 optional fields on a variable-length array of players was
  # unreliable (it would randomly omit several fields even when they were
  # clearly visible), while the same fields split into ~5-field groups
  # came back complete and accurate every time. Fixed-length arrays (like
  # BoxScoreExtractor's always-2-teams array) didn't show this problem
  # even at ~10 fields, so the culprit seems to be the combination of an
  # uncertain array length with a large per-item optional field count, not
  # raw field count alone.
  class PlayerCategoryExtractor
    FIELD_SETS = {
      "passing" => %i[
        passing_completions passing_attempts passing_yards passing_tds passing_interceptions
        passing_rating passing_longest passing_sacks_taken passing_avg
      ],
      "rushing" => %i[rushing_carries rushing_yards rushing_avg rushing_tds rushing_fumbles rushing_yac rushing_longest],
      "receiving" => %i[receiving_receptions receiving_yards receiving_avg receiving_tds receiving_rac receiving_longest receiving_drop],
      "defense" => %i[
        defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl
        defense_sacks defense_interceptions defense_interceptions_longest defense_interceptions_yards
        defense_interceptions_avg defense_deflections
        defense_forced_fumbles defense_fumble_recoveries defense_fumble_return_yards
        defense_blocks defense_safeties defense_touchdowns
      ]
    }.freeze

    FIELD_GROUPS = {
      "passing" => [
        %i[passing_completions passing_attempts passing_yards passing_tds passing_interceptions],
        %i[passing_rating passing_longest passing_sacks_taken passing_avg]
      ],
      "rushing" => [
        %i[rushing_carries rushing_yards rushing_tds rushing_avg],
        %i[rushing_fumbles rushing_yac rushing_longest]
      ],
      "receiving" => [
        %i[receiving_receptions receiving_yards receiving_tds receiving_avg],
        %i[receiving_rac receiving_longest receiving_drop]
      ],
      "defense" => [
        %i[defense_solo_tackles defense_assist_tackles defense_tackles defense_tfl defense_sacks],
        %i[defense_interceptions defense_interceptions_yards defense_interceptions_avg defense_interceptions_longest defense_deflections]
      ]
    }.freeze

    # Columns that only appear after scrolling a table to the right, where
    # the NAME column is no longer visible. Callers (the Remote Play capture)
    # graft the name column onto the scrolled-right screenshot first, so
    # these run on that composite instead of the plain screenshots.
    # check_interceptions re-reads the INT column, which is also on the plain
    # screenshots — if the two disagree for a player, the composite's rows
    # were paired with the wrong names and its values are discarded.
    EXTRA_FIELD_GROUPS = {
      "defense" => [
        %i[defense_forced_fumbles defense_fumble_recoveries defense_fumble_return_yards defense_blocks
           defense_safeties defense_touchdowns check_interceptions]
      ]
    }.freeze

    EXTRA_NOTE = " The table is scrolled to the right, so only the NAME column and the right-hand stat columns are shown.".freeze

    FLOAT_FIELDS = %i[passing_rating passing_avg rushing_avg receiving_avg defense_sacks defense_interceptions_avg].freeze

    # Each description names the on-screen column header the field comes from.
    # Without these the model has to guess the column from a bare field name,
    # and consistently skipped some (e.g. receiving TD on a table of mostly 0s).
    # Report 0s too: a column of 0s is real data, not a missing value.
    FIELD_DESCRIPTIONS = {
      passing_completions: "COMP column: completions",
      passing_attempts: "ATT column: attempts",
      passing_yards: "YARDS column: passing yards",
      passing_tds: "TD column: passing touchdowns",
      passing_interceptions: "INT column: interceptions thrown",
      passing_rating: "RATING column: passer rating",
      passing_longest: "LONG column: longest completion",
      passing_sacks_taken: "SACKS column: sacks taken",
      passing_avg: "Completion percentage, shown as COMP%",
      rushing_carries: "CAR column: carries",
      rushing_yards: "YARDS column: rushing yards",
      rushing_avg: "AVG column: yards per carry",
      rushing_tds: "TD column: rushing touchdowns",
      rushing_fumbles: "FUMB column: fumbles",
      rushing_yac: "YAC column: yards after contact",
      rushing_longest: "LONG column: longest rush",
      receiving_receptions: "REC column: receptions",
      receiving_yards: "YARDS column: receiving yards",
      receiving_avg: "AVG column: yards per catch (not RAC AVG)",
      receiving_tds: "TD column: receiving touchdowns, the column right after AVG. A whole number; report 0 when it shows 0.",
      receiving_rac: "RAC column: run-after-catch yards (not RAC AVG)",
      receiving_longest: "LONG column: longest reception",
      receiving_drop: "DROPS column: dropped passes",
      defense_solo_tackles: "SOLO column: solo tackles",
      defense_assist_tackles: "ASSISTS column: assisted tackles",
      defense_tackles: "TAK column: total tackles",
      defense_tfl: "TFL column: tackles for loss",
      defense_sacks: "SACK column: sacks (can be a half, like 0.5)",
      defense_interceptions: "INT column: interceptions",
      defense_interceptions_longest: "INT LG column: longest interception return",
      defense_interceptions_yards: "INT YDS column: interception return yards",
      defense_interceptions_avg: "INT AVG column: average interception return",
      defense_deflections: "DEFL column: passes deflected",
      defense_forced_fumbles: "FFUMB column: forced fumbles",
      defense_fumble_recoveries: "FMBREC column: fumble recoveries",
      defense_fumble_return_yards: "FMBYDS column: fumble return yards",
      defense_blocks: "BLOCK column: blocked kicks/punts",
      defense_safeties: "SFTY column: safeties",
      defense_touchdowns: "TD column: defensive touchdowns",
      check_interceptions: "INT column"
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game player stat screenshots and transcribing the
      exact numbers shown. Only report a value if you can actually see it — never guess. Leave a field
      unset if it is not visible.
    PROMPT

    # Human-readable notes about rows that couldn't be trusted (see
    # EXTRA_FIELD_GROUPS); read after #call.
    attr_reader :warnings

    def initialize(category:, college:, roster:)
      @category = category
      @college = college
      @roster = roster
      @warnings = []
    end

    # extra_blobs: name-grafted screenshots of the scrolled-right columns, if
    # the caller has them (see EXTRA_FIELD_GROUPS). Without them those
    # columns are simply left unset.
    def call(image_blobs, extra_blobs: [])
      return [] if image_blobs.blank?

      results = FIELD_GROUPS.fetch(@category).map { |fields| run_group(image_blobs, fields) }
      extra_results = extra_blobs.blank? ? [] : EXTRA_FIELD_GROUPS.fetch(@category, []).map { |fields| run_group(extra_blobs, fields, extra: true) }

      rows = merge(results + extra_results)
      rows.each { |row| verify_extra(row) } if extra_results.any?
      rows.map { |row| build_entry(row) }.reject { |entry| StatFields.empty_line?(entry[:fields]) }
    end

    private

    # Empirically, a sub-call occasionally comes back with an empty players
    # array even when the screenshot clearly has players on it. A single
    # retry clears this up almost every time it happens.
    def run_group(image_blobs, fields, extra: false)
      rows = fetch_group(image_blobs, fields, extra: extra)
      rows = fetch_group(image_blobs, fields, extra: extra) if rows.empty?
      rows
    end

    def fetch_group(image_blobs, fields, extra: false)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(group_schema(fields))
      raw = chat.ask(prompt(extra: extra), with: image_blobs).content
      # Defensive: an occasional malformed response includes a bare string
      # instead of a proper row object, so filter those out rather than crash.
      Array(raw["players"]).select { |row| row.is_a?(Hash) }
    end

    def group_schema(fields)
      float_fields = FLOAT_FIELDS
      descriptions = FIELD_DESCRIPTIONS

      RubyLLM::Schema.create do
        array :players, description: "One entry per player shown in this stat table." do
          object do
            string :player_display_name, description: "Exactly as shown on screen, e.g. 'H.Crandall'"
            integer :student_season_id, required: false,
                    description: "id of the matching player from the roster given in the prompt, " \
                                 "only if confidently matched. Leave unset otherwise."
            # Required, not optional: with optional fields the model silently skips some columns
            # (e.g. receiving TD on a table of mostly 0s) even when they're clearly visible. Every
            # field in a group is a column shown on the screenshot, so there's nothing to omit.
            fields.each do |field|
              if float_fields.include?(field)
                number field, description: descriptions[field]
              else
                integer field, description: descriptions[field]
              end
            end
          end
        end
      end
    end

    def prompt(extra: false)
      <<~PROMPT
        This is the #{@category} stat table for #{@college.name}.#{extra ? EXTRA_NOTE : ""}

        Every requested stat column is visible in the screenshot. Report every requested field for EVERY
        player; a 0 is real data, not a missing value.

        Player names are shown as first-initial + last name (e.g. "H.Crandall"). Match each one against the
        roster below and, only if confident, set student_season_id to that player's id. If no roster is
        given, or you can't confidently match, leave student_season_id unset but still report
        player_display_name and their stats.

        #{roster_section}
      PROMPT
    end

    def roster_section
      return "Roster: none available — report player_display_name only, leave student_season_id unset." if @roster.empty?

      lines = @roster.map { |player| "- id #{player[:id]}: #{player[:name]} (#{player[:position]})" }
      "Roster:\n#{lines.join("\n")}"
    end

    # Merges rows from the group sub-calls by display name so a player who
    # appears in both calls ends up as one row with all fields.
    def merge(results)
      merged = {}
      order = []

      results.each do |rows|
        rows.each do |row|
          key = row["player_display_name"].to_s.strip.downcase
          unless merged.key?(key)
            merged[key] = { "player_display_name" => row["player_display_name"] }
            order << key
          end
          merged[key]["student_season_id"] ||= row["student_season_id"]
          merged[key].merge!(row.except("player_display_name", "student_season_id"))
        end
      end

      order.map { |key| merged[key] }
    end

    # The extra columns come from a composite image whose names were grafted
    # on from a different screenshot, so confirm the rows really line up: the
    # INT column appears in both. A mismatch means a misaligned composite —
    # keep the player's trusted fields, drop the unverifiable ones.
    def verify_extra(row)
      extra_fields = EXTRA_FIELD_GROUPS.fetch(@category).flatten.map(&:to_s)
      check = row.delete("check_interceptions")
      return if check.nil? || row["defense_interceptions"].nil? || check == row["defense_interceptions"]

      row.except!(*extra_fields)
      @warnings << "#{row['player_display_name']}: right-side stats didn't line up with their row (INT #{check} vs #{row['defense_interceptions']}) and were skipped."
    end

    def build_entry(row)
      {
        team: @college.name,
        category: @category,
        display_name: row["player_display_name"],
        student_season_id: row["student_season_id"],
        fields: row.slice(*FIELD_SETS.fetch(@category).map(&:to_s)).transform_keys(&:to_sym).compact
      }
    end
  end
end
