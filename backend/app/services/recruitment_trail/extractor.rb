module RecruitmentTrail
  # Extracts one coached program's list of signed recruits from the
  # recruiting-class screen (the per-team roster of commits, not the
  # national class-ranking table — that's Recruiting::Extractor).
  #
  # The team is read off the header (name next to the logo, top-left) the
  # same way TeamSchedule::ScheduleExtractor does it, with the same
  # fallback: an unmatched header just leaves college_id nil for manual
  # correction in the review UI. Only the WEEK the class is being recorded
  # against is picked by the user beforehand.
  #
  # Every column transcribed is always visible on the screen, so the row
  # fields are all required and the only variable-length part is the row
  # array itself — the same shape Recruiting::Extractor uses successfully
  # with an even wider row, staying well inside the structured-output
  # limits noted in the game_stats/ services.
  #
  # NAME on screen is just a first initial + last name ("G. Cushenberry").
  # first_initial is captured as-is; the full first name is filled in by
  # hand on the review screen so the recruit can be name-matched next
  # season during roster import.
  #
  # Duplicate rows (the same last name / position / state appearing twice
  # across the uploaded images, e.g. from an overlapping scroll) are
  # collapsed here so the review table — and the commit — only ever see one
  # of each.
  #
  # The screen has a filter pill in the top-right — OVERALL, RECRUITS, or
  # TRANSFERS — that's read once per call and applied to every row, same
  # simplification as team_raw_name (this assumes one upload = one filter
  # state, not a mix of screenshots from different tabs). A row only gets
  # tagged transfer: true when the filter reads TRANSFERS; OVERALL is
  # treated the same as RECRUITS (i.e. not a transfer) for now, since
  # there's no way to tell the two apart within an OVERALL screen — upload
  # the RECRUITS/TRANSFERS-filtered screen instead of OVERALL when the
  # distinction matters.
  class Extractor
    include CollegeMatching

    FILTER_LABELS = %w[overall recruits transfers].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game recruiting screens and transcribing the
      exact values shown. Only report a value if you can actually see it — never guess.
    PROMPT

    def call(images)
      return empty_result if images.blank?

      raw = chat.with_schema(schema).ask(prompt, with: images).content
      transfer = raw["filter_label"] == "transfers"
      recruits = Array(raw["recruits"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row, transfer) }

      {
        college_id: resolve_college(raw["team_raw_name"], raw["team_college_name"])&.id,
        college_raw_name: raw["team_raw_name"],
        filter_label: raw["filter_label"],
        recruits: dedupe(recruits),
        colleges: colleges_json
      }
    end

    private

    def empty_result
      { college_id: nil, college_raw_name: nil, filter_label: nil, recruits: [], colleges: colleges_json }
    end

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      names = college_names
      labels = FILTER_LABELS
      RubyLLM::Schema.create do
        string :team_raw_name, description: "The team name shown next to the logo in the top-left of the screen, exactly as shown, e.g. 'OHIO STATE'"
        string :team_college_name, enum: names,
               description: "The database college that team_raw_name refers to — use your knowledge of team " \
                            "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
        string :filter_label, enum: labels,
               description: "The filter pill shown in the top-right of the header, exactly which of the three " \
                            "it reads: 'OVERALL', 'RECRUITS', or 'TRANSFERS'."
        array :recruits, description: "One entry per player row in the recruiting table, top to bottom across all images." do
          object do
            string :first_initial, description: "The first initial shown before the last name in the NAME column, e.g. 'G'"
            string :last_name, description: "The last name shown in the NAME column"
            string :position, description: "The first POS column — the position abbreviation, e.g. 'LEDG', 'WR', 'QB'"
            integer :star_rating, description: "The RATING column, which is drawn as a row of 5 star icons. Count only " \
                                               "the filled (solid) stars; ignore the empty/outlined ones. Result is 1 to 5, " \
                                               "e.g. 5 for '★★★★★', 4 for '★★★★☆', 3 for '★★★☆☆'."
            integer :nil_amount, description: "The OFFER column — the NIL offer number"
            integer :national_rank, description: "The NAT column — national rank"
            integer :position_rank, description: "The second POS column — position rank"
            integer :state_rank, description: "The STA column — state rank"
            string :state, description: "The ST column — the two-letter state abbreviation, e.g. 'GA', 'TX'"
            string :class_year, required: false,
                   description: "The CLASS column, exactly as shown — e.g. 'HS' (high school), 'JC (JR)'/'JC (SO)' " \
                                "(junior college), or a plain class year like 'SO'/'JR'/'SR' for a transfer's year " \
                                "at their previous school. Leave unset if not visible."
          end
        end
      end
    end

    def prompt
      "This is one team's recruiting class screen, a table of signed recruits split across multiple " \
        "images if needed. First read the team name from the top-left header and the filter pill in the " \
        "top-right (OVERALL, RECRUITS, or TRANSFERS), then read every player row, top to bottom, across all " \
        "images. If the same player appears in more than one image, only report them once."
    end

    def build_row(row, transfer)
      {
        first_initial: row["first_initial"],
        first_name: nil,
        last_name: row["last_name"],
        position: row["position"],
        star_rating: row["star_rating"],
        nil_amount: row["nil_amount"],
        national_rank: row["national_rank"],
        position_rank: row["position_rank"],
        state_rank: row["state_rank"],
        state: row["state"],
        class_year: row["class_year"],
        transfer: transfer
      }
    end

    # Same natural key the CommitService upserts on, so what the reviewer
    # sees is already the set that will actually be saved.
    def dedupe(recruits)
      recruits.uniq { |row| [ row[:last_name].to_s.strip.downcase, row[:position].to_s.strip.downcase, row[:state].to_s.strip.downcase ] }
    end
  end
end
