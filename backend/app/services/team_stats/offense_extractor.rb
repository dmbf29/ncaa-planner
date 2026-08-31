module TeamStats
  # Extracts a conference-wide team offense stats table (points scored,
  # total offensive yards, and the passing/rushing yard+TD splits) from
  # however many screenshots it takes to show the whole conference — the
  # in-game stats screen splits columns across multiple horizontally-
  # scrolled pages, so PTS/OFF might only be visible in one image while
  # RTD/FDS are only visible in another; passing all images to each call
  # lets the model read across them. There's no coached-team filtering —
  # every row shown gets extracted, same as ConferenceStandings::Extractor,
  # since Colleges are league context even when not coached.
  #
  # A ~12-team table proved to be a much harder transcription target than
  # anything else in this codebase's screenshot-reading services: asking
  # for every team's values in one response — even split into small field
  # groups (see FIELD_GROUPS) — would reliably nail the first row or two,
  # then degrade into dropped rows or "shell" rows (matched name, every
  # field blank) for the rest. Retrying the exact same wide request tends
  # to reproduce the same degradation rather than average it out, so the
  # fix here is to shrink the ask itself: fetch the team roster first (a
  # much safer, field-free ask — see fetch_roster) to get a reliable "these
  # are the N teams that must show up" reference, then run each field group
  # against small CHUNK_SIZE-team batches of that roster instead of the
  # whole table at once. Each chunk call still retries and merges
  # (gap-filling, never overwriting a value already found) across up to
  # MAX_ATTEMPTS attempts so progress from an earlier attempt survives even
  # if a later one regresses.
  #
  # Team names get the same enum-constrained matching used elsewhere, with
  # the same fix: the enum field alone is unsafe — it consistently
  # truncates a correct longer answer down to a shorter college name
  # that's also a valid enum value and an exact prefix of the right one
  # ("Arkansas State" -> "Arkansas", "Ohio State" -> "Ohio"), so
  # college_raw_name (plain text, unaffected) is checked for an exact
  # match first and the enum field is only a fallback for genuine
  # nicknames where no exact match exists.
  class OffenseExtractor
    include CollegeMatching

    FIELD_GROUPS = [
      %i[points_scored total_offensive_yards yards_per_play passing_yards],
      %i[passing_touchdowns rushing_yards rushing_touchdowns first_downs]
    ].freeze

    FIELD_DESCRIPTIONS = {
      points_scored: "The PTS column — total points scored this season",
      total_offensive_yards: "The OFF column — total offensive yards",
      yards_per_play: "The YPP column — yards per play",
      passing_yards: "The PASS column — total passing yards",
      passing_touchdowns: "The PTD column — passing touchdowns",
      rushing_yards: "The RUSH column — total rushing yards",
      rushing_touchdowns: "The RTD column — rushing touchdowns",
      first_downs: "The FDS column — total first downs"
    }.freeze

    FLOAT_FIELDS = %i[yards_per_play].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game team offense stats tables and transcribing
      the exact values shown. Only report a value if you can actually see it — never guess. Leave a field
      unset if it is not visible in any image.
    PROMPT

    CHUNK_SIZE = 6
    MAX_ATTEMPTS = 3

    def call(images)
      return { rows: [], colleges: colleges_json } if images.blank?

      roster = fetch_roster(images)
      chunks = roster.each_slice(CHUNK_SIZE).to_a

      results = [ roster ]
      FIELD_GROUPS.each do |fields|
        chunks.each { |chunk| results << run_group(images, fields, chunk) }
      end
      rows = merge(results).map { |row| build_row(row) }

      { rows: rows, colleges: colleges_json }
    end

    private

    # The team list itself — no stat fields, just name + enum match — is
    # the safest possible ask (two required string fields, nothing
    # optional), so it's the most reliable source of "how many teams are
    # actually in this table." Retries while an attempt is still turning
    # up teams the previous attempts missed, and stops once an attempt
    # adds nothing new.
    def fetch_roster(images)
      merged = {}
      order = []

      MAX_ATTEMPTS.times do
        before = order.size
        fetch_roster_group(images).each do |row|
          key = row_key(row)
          next if key.blank? || merged.key?(key)

          merged[key] = row
          order << key
        end
        break if order.size == before
      end

      order.map { |key| merged[key] }
    end

    def fetch_roster_group(images)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(roster_schema)
      raw = chat.ask(prompt, with: images).content
      Array(raw["teams"]).select { |row| row.is_a?(Hash) }
    end

    def roster_schema
      names = college_names
      RubyLLM::Schema.create do
        array :teams, description: "One entry per row in the table." do
          object do
            string :college_raw_name, description: "The TEAM column, exactly as shown"
            string :college_name, enum: names,
                   description: "The database college that college_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
          end
        end
      end
    end

    # `chunk` is a handful of roster rows (from fetch_roster) this call is
    # scoped to. See the class doc comment for why this merges (gap-filling)
    # across attempts instead of replacing wholesale, and why completeness
    # is checked against the chunk's own team keys.
    def run_group(images, fields, chunk)
      chunk_names = chunk.map { |row| row["college_raw_name"] }
      known_keys = chunk.map { |row| row_key(row) }
      merged = {}
      order = []
      string_fields = fields.map(&:to_s)

      MAX_ATTEMPTS.times do
        fetch_group(images, fields, chunk_names).each do |row|
          key = row_key(row)
          next if key.blank?

          unless merged.key?(key)
            merged[key] = row
            order << key
            next
          end
          string_fields.each { |field| merged[key][field] ||= row[field] }
          merged[key]["college_name"] ||= row["college_name"]
        end

        complete = (known_keys - order).empty? &&
                   order.all? { |key| string_fields.all? { |field| !merged[key][field].nil? } }
        break if complete
      end

      order.map { |key| merged[key] }
    end

    def row_key(row)
      row["college_raw_name"].to_s.strip.downcase
    end

    def fetch_group(images, fields, focus_names)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(group_schema(fields))
      raw = chat.ask(prompt(focus_names), with: images).content
      Array(raw["teams"]).select { |row| row.is_a?(Hash) }
    end

    def group_schema(fields)
      names = college_names
      float_fields = FLOAT_FIELDS
      descriptions = FIELD_DESCRIPTIONS

      RubyLLM::Schema.create do
        array :teams, description: "One entry per row in the table." do
          object do
            string :college_raw_name, description: "The TEAM column, exactly as shown"
            string :college_name, enum: names,
                   description: "The database college that college_raw_name refers to — use your knowledge of team " \
                                "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
            fields.each do |field|
              if float_fields.include?(field)
                number field, required: false, description: descriptions[field]
              else
                integer field, required: false, description: descriptions[field]
              end
            end
          end
        end
      end
    end

    def prompt(focus_names = nil)
      base = "This is a college football team offense stats table, split across multiple images if needed (the " \
        "game's stats screen shows different columns on each page)."
      return "#{base} Read every row, top to bottom, across all images." if focus_names.blank?

      "#{base} Only report rows for these specific teams — ignore every other row in the table, even if you " \
        "can read it: #{focus_names.join(', ')}."
    end

    # Merges rows from the roster call and the group sub-calls by raw team
    # name so a team that appears in multiple calls ends up as one row
    # with all fields.
    def merge(results)
      merged = {}
      order = []

      results.each do |rows|
        rows.each do |row|
          key = row_key(row)
          next if key.blank?

          unless merged.key?(key)
            merged[key] = { "college_raw_name" => row["college_raw_name"] }
            order << key
          end
          merged[key]["college_name"] ||= row["college_name"]
          merged[key].merge!(row.except("college_raw_name", "college_name"))
        end
      end

      order.map { |key| merged[key] }
    end

    def build_row(row)
      {
        college_raw_name: row["college_raw_name"],
        college_id: resolve_college(row["college_raw_name"], row["college_name"])&.id,
        points_scored: row["points_scored"],
        total_offensive_yards: row["total_offensive_yards"],
        yards_per_play: row["yards_per_play"],
        passing_yards: row["passing_yards"],
        passing_touchdowns: row["passing_touchdowns"],
        rushing_yards: row["rushing_yards"],
        rushing_touchdowns: row["rushing_touchdowns"],
        first_downs: row["first_downs"]
      }
    end
  end
end
