module PortalPreview
  # Extracts one coached program's "players leaving" screen — the roster
  # status table shown ahead of the transfer portal, with a status
  # (Transfer/Pro Draft/Staying/Graduation), a reason detail, and a
  # persuasion chance per player.
  #
  # The team is read off the header (top-left) the same way
  # RecruitmentTrail::Extractor does it — an unmatched header just leaves
  # college_id nil for manual correction in the review UI.
  #
  # NAME on screen is a first initial + last name, same truncated format
  # RecruitmentTrail deals with — matching against the roster (once the
  # college is known) happens separately in Matcher, not here.
  #
  # overall is transcribed for display/matching context only — it's NOT
  # authoritative (it can have drifted from what's on the StudentSeason
  # record since the screen was captured), so nothing downstream should
  # treat it as a source of truth over the real roster data.
  class Extractor
    include CollegeMatching

    STATUSES = PortalStatus::STATUSES
    PERSUASION_LEVELS = PortalStatus::PERSUASION_LEVELS

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game "players leaving"/roster outlook screens and
      transcribing the exact values shown. The on-screen text is often a very light, low-contrast gray and can
      be hard to read — look carefully at each row before reporting a value, and only report a value if you can
      actually see it. Never guess.
    PROMPT

    def call(images)
      return empty_result if images.blank?

      raw = chat.with_schema(schema).ask(prompt, with: images).content
      players = Array(raw["players"]).select { |row| row.is_a?(Hash) }.map { |row| build_row(row) }

      {
        college_id: resolve_college(raw["team_raw_name"], raw["team_college_name"])&.id,
        college_raw_name: raw["team_raw_name"],
        players: dedupe(players),
        colleges: colleges_json
      }
    end

    private

    def empty_result
      { college_id: nil, college_raw_name: nil, players: [], colleges: colleges_json }
    end

    def chat
      RubyLLM.chat.with_instructions(SYSTEM_PROMPT)
    end

    def schema
      names = college_names
      statuses = STATUSES
      persuasion_levels = PERSUASION_LEVELS

      RubyLLM::Schema.create do
        string :team_raw_name, description: "The team name shown in the top-left header, exactly as shown, e.g. 'BOWLING GREEN'"
        string :team_college_name, enum: names,
               description: "The database college that team_raw_name refers to — use your knowledge of team " \
                            "nicknames/abbreviations. Only use '#{UNMATCHED}' if none of the options are a plausible match."
        array :players, description: "One entry per player row in the table, top to bottom across all images." do
          object do
            string :first_initial, description: "The first initial shown before the last name in the NAME column, e.g. 'B'"
            string :last_name, description: "The last name shown in the NAME column"
            string :position, description: "The POS column abbreviation, exactly as shown, e.g. 'WR', 'QB', 'MIKE'"
            string :class_year, description: "The YEAR column, exactly as shown, e.g. 'SO', 'SO (RS)', 'FR'"
            integer :overall, description: "The OVR column"
            string :status, enum: statuses,
                   description: "The REASON column's category, ignoring anything in parentheses: 'transfer', " \
                                "'pro_draft' (shown as 'Pro Draft'), 'staying' (shown as 'Staying'), or " \
                                "'graduation' (shown as 'Graduation')"
            string :transfer_reason, required: false,
                   description: "Only when status is transfer: the text in parentheses after 'Transfer', " \
                                "exactly as shown, e.g. 'Playing Time', 'Brand Exposure'. Leave unset otherwise."
            integer :projected_draft_round, required: false,
                    description: "Only when status is pro_draft: the number after 'Projected Round' in " \
                                 "parentheses. Leave unset otherwise."
            string :persuasion_chance, enum: persuasion_levels,
                   description: "The PERSUASION CHANCE column. Use 'not_applicable' for a dash/'---' (shown for " \
                                "some players, typically seniors, who have no remaining eligibility to persuade)."
          end
        end
      end
    end

    def prompt
      "This is one team's roster status screen ahead of the transfer portal, a table split across multiple " \
        "images if needed. First read the team name from the top-left header, then read every player row, top " \
        "to bottom, across all images. The text is often light gray and low-contrast — look closely. If the " \
        "same player appears in more than one image (e.g. an overlapping scroll), only report them once."
    end

    def build_row(row)
      {
        first_initial: row["first_initial"],
        last_name: row["last_name"],
        position: row["position"],
        class_year: normalize_class_year(row["class_year"]),
        overall: row["overall"],
        status: row["status"],
        transfer_reason: row["transfer_reason"],
        projected_draft_round: row["projected_draft_round"],
        persuasion_chance: row["persuasion_chance"]
      }
    end

    # The screen uses a space before the redshirt suffix ("SO (RS)"), same
    # as RosterImport — normalize to how the rest of the app stores it.
    def normalize_class_year(class_year)
      class_year.to_s.strip.sub(/\s+\(RS\)/, "(RS)").presence
    end

    def dedupe(players)
      players.uniq { |row| [ row[:last_name].to_s.strip.downcase, row[:position].to_s.strip.downcase, row[:class_year].to_s.strip.downcase ] }
    end
  end
end
