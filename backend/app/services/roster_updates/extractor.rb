module RosterUpdates
  # Extracts a roster table (one row per player, however many screenshots it takes to
  # cover the whole team) into proposed player updates for review before committing.
  #
  # Player names on screen are truncated to first-initial + last name (e.g.
  # "J.Bettis Jr."), so this asks the model to also attempt a player_id match against
  # the team's current active roster (given in the prompt) — same approach
  # GameStats::PlayerCategoryExtractor uses for student_season_id. The review screen
  # is where a wrong or missing match gets corrected, not this extraction step.
  #
  # Split into 3 small field-groups per CLAUDE.md's documented reliability limit for a
  # variable-length array of objects (empirically ~4-5 optional fields per call), each
  # merged by player_display_name — same pattern as PlayerCategoryExtractor#merge. All
  # uploaded images are passed to every call together (like NilSpend::Extractor does
  # for a multi-page table), since a multi-page roster is one continuous logical table.
  class Extractor
    CLASS_YEARS = %w[FR FR(RS) SO SO(RS) JR JR(RS) SR SR(RS)].freeze
    UNKNOWN_POSITION = "UNKNOWN".freeze

    FIELD_GROUPS = [
      %i[class_year position overall nil_amount],
      %i[speed acceleration agility change_of_direction],
      %i[strength awareness]
    ].freeze

    ATTRIBUTE_FIELDS = %i[speed acceleration agility change_of_direction strength awareness].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert at reading college football video game roster screenshots and transcribing the exact
      values shown. Only report a value if you can actually see it — never guess. Leave a field unset if it
      is not visible.
    PROMPT

    def call(team, images)
      active_players = active_players(team)
      return { rows: [], boards: board_options(team), existing_players: existing_players_json(active_players) } if images.blank?

      results = FIELD_GROUPS.map { |fields| run_group(team, images, fields, active_players) }
      rows = merge(results).map { |row| build_row(team, active_players, row) }

      { rows: rows, boards: board_options(team), existing_players: existing_players_json(active_players) }
    end

    # Same output shape as #call, but built from players already read off a roster screen recording by
    # tools/roster_video (local OCR) instead of from screenshots, so no AI call is made. The video gives full
    # first names, which makes matching against the active roster more reliable than the screenshot path's
    # first-initial + last name.
    def call_from_video(team, video_players)
      active_players = active_players(team)
      rows = Array(video_players).map { |player| build_video_row(team, active_players, player) }

      { rows: rows, boards: board_options(team), existing_players: existing_players_json(active_players) }
    end

    private

    HIGH_NIL = 200 # a NIL read above this is more likely an OCR slip than a real figure; flagged for review

    NAME_SUFFIXES = %w[jr sr ii iii iv v].freeze

    def build_video_row(team, active_players, player)
      player = player.stringify_keys
      full_name = [ player["first_name"], player["last_name"] ].map(&:to_s).map(&:strip).reject(&:blank?).join(" ")
      position = player["position"].presence
      matched = match_video_player(active_players, full_name, position)

      # The screen says LEDG/REDG where boards are LE/RE; keep the screen's code if a board already matches it.
      position = PositionBoardMapping.canonical(position) if position && resolve_board(team, position).nil?
      row = build_row(team, active_players, {
        "player_display_name" => full_name,
        "player_id" => matched&.dig(:id),
        "class_year" => video_class_year(player["class_year"]),
        "position" => position,
        "overall" => integer_or_nil(player["overall"])
      }.merge(ATTRIBUTE_FIELDS.index_with { |field| integer_or_nil(player[field.to_s]) }.stringify_keys))

      # The video tool reads the NIL column as "nil" (its "nil_amount" stays empty for the dynasty importer). A cell it
      # couldn't read (a lone "0" next to the diamond sometimes drops out) keeps the stored value instead of blanking it.
      stored_nil = matched ? team.players.find(matched[:id]).nil_amount : nil
      video_nil = integer_or_nil(player["nil"])
      row[:nil_amount] = video_nil || stored_nil
      review = Array(player["needs_review"])
      review += [ "NIL not read — kept current value" ] if video_nil.nil? && player.key?("nil")
      review += [ "NIL #{video_nil} is unusually high — check it" ] if video_nil && video_nil > HIGH_NIL
      row[:needs_review] = review.presence
      row
    end

    # Exact full name first; otherwise last name + first initial, but only when that picks out exactly one
    # active player (breaking a tie on position) -- a wrong auto-match silently overwrites a real player.
    def match_video_player(active_players, full_name, position)
      target = name_parts(full_name)
      return nil if target.nil?

      exact = active_players.select { |p| name_parts(p[:name]) == target }
      return exact.first if exact.size == 1

      candidates = active_players.select do |p|
        parts = name_parts(p[:name])
        parts && parts[:last] == target[:last] && parts[:first][0] == target[:first][0]
      end
      candidates = candidates.select { |p| p[:position].to_s.casecmp?(position.to_s) } if candidates.size > 1
      candidates.size == 1 ? candidates.first : nil
    end

    def name_parts(name)
      tokens = name.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split
      tokens.pop while tokens.size > 1 && NAME_SUFFIXES.include?(tokens.last)
      return nil if tokens.size < 2

      { first: tokens.first.to_s, last: tokens.last.to_s }
    end

    # The screen shows "SO (RS)"; the planner stores "SO(RS)".
    def video_class_year(value)
      normalized = value.to_s.gsub(/\s+/, "").upcase
      CLASS_YEARS.include?(normalized) ? normalized : nil
    end

    def integer_or_nil(value)
      Integer(value.to_s.strip, exception: false)
    end

    def run_group(team, images, fields, active_players)
      rows = fetch_group(team, images, fields, active_players)
      rows = fetch_group(team, images, fields, active_players) if rows.empty?
      rows
    end

    def fetch_group(team, images, fields, active_players)
      chat = RubyLLM.chat.with_instructions(SYSTEM_PROMPT).with_schema(group_schema(team, fields))
      raw = chat.ask(prompt(active_players), with: images).content
      Array(raw["players"]).select { |row| row.is_a?(Hash) }
    end

    def group_schema(team, fields)
      class_years = CLASS_YEARS
      positions = position_candidates(team)

      RubyLLM::Schema.create do
        array :players, description: "One entry per player row shown in the roster table(s), top to bottom." do
          object do
            string :player_display_name, description: "Exactly as shown, e.g. 'J.Bettis Jr.' (first initial + last name)"
            integer :player_id, required: false,
                    description: "id of the matching player from the roster given in the prompt, " \
                                 "only if confidently matched by name. Leave unset otherwise."
            fields.each do |field|
              case field
              when :class_year
                string field, enum: class_years, required: false, description: "The YEAR column"
              when :position
                string field, enum: positions, required: false,
                       description: "The POS column — the closest match from the given options to what's shown. " \
                                    "Only use '#{UNKNOWN_POSITION}' if none of the options are a plausible match."
              else
                integer field, required: false, description: "The #{field.to_s.upcase} column"
              end
            end
          end
        end
      end
    end

    # Constraining this to a known vocabulary (rather than a free string) keeps the
    # model from transcribing a garbled read (e.g. misreading "LE" as "LEDG") as a
    # literal position — same trick NilSpend::Extractor uses for college_name.
    def position_candidates(team)
      board_names = team_boards(team).map { |b| b[:name] }
      known_codes = PositionBoardMapping::MAP.keys + PositionBoardMapping::OFFENSE_CODES + PositionBoardMapping::DEFENSE_CODES
      (board_names + known_codes).uniq + [ UNKNOWN_POSITION ]
    end

    def prompt(active_players)
      <<~PROMPT
        This is a roster table, possibly split across multiple images — read every row, top to bottom, across
        all images.

        Player names are shown as first-initial + last name (e.g. "J.Bettis Jr."). Match each one against the
        roster below and, only if confident, set player_id to that player's id. If you can't confidently
        match, leave player_id unset but still report player_display_name and their stats.

        #{roster_section(active_players)}
      PROMPT
    end

    def roster_section(active_players)
      return "Roster: none available — report player_display_name only, leave player_id unset." if active_players.empty?

      lines = active_players.map { |p| "- id #{p[:id]}: #{p[:name]} (#{p[:position]})" }
      "Roster:\n#{lines.join("\n")}"
    end

    # Merges rows from the group sub-calls by display name so a player who appears in
    # multiple calls (or multiple images) ends up as one row with all fields.
    def merge(results)
      merged = {}
      order = []

      results.each do |rows|
        rows.each do |row|
          key = row["player_display_name"].to_s.strip.downcase
          next if key.blank?

          unless merged.key?(key)
            merged[key] = { "player_display_name" => row["player_display_name"] }
            order << key
          end
          merged[key]["player_id"] ||= row["player_id"]
          merged[key].merge!(row.except("player_display_name", "player_id"))
        end
      end

      order.map { |key| merged[key] }
    end

    def build_row(team, active_players, row)
      matched = active_players.find { |p| p[:id] == row["player_id"] }
      position = row["position"] == UNKNOWN_POSITION ? nil : row["position"]
      board_id = resolve_board(team, position)

      {
        display_name: row["player_display_name"],
        name: matched ? matched[:name] : row["player_display_name"],
        player_id: matched&.dig(:id),
        class_year: row["class_year"],
        overall: row["overall"],
        nil_amount: row["nil_amount"],
        position_raw: position,
        position_board_id: board_id,
        attribute_values: row.slice(*ATTRIBUTE_FIELDS.map(&:to_s)).compact
      }
    end

    def resolve_board(team, position_raw)
      return nil if position_raw.blank?

      code = position_raw.to_s.strip.upcase
      exact = team_boards(team).find { |b| b[:name].upcase == code }
      return exact[:id] if exact

      meta = PositionBoardMapping.resolve(code)
      return nil if meta.blank?

      team_boards(team).find { |b| b[:squad_name] == meta[:squad] && b[:name].upcase == meta[:board].upcase }&.dig(:id)
    end

    def team_boards(team)
      @team_boards ||= {}
      @team_boards[team.id] ||= team.position_boards.includes(:squad).map do |board|
        { id: board.id, name: board.name, squad_id: board.squad_id, squad_name: board.squad.name }
      end
    end

    def board_options(team)
      team_boards(team)
    end

    def active_players(team)
      team.players.where(status: %i[recruit rostered]).includes(:position_board).map do |player|
        {
          id: player.id,
          name: player.name,
          position: player.position_board&.name || "unassigned",
          class_year: player.class_year,
          overall: player.overall,
          position_board_id: player.position_board_id,
          position_board_name: player.position_board&.name
        }
      end
    end

    def existing_players_json(active_players)
      active_players.map { |p| p.slice(:id, :name, :class_year, :overall, :position_board_id, :position_board_name) }
    end
  end
end
