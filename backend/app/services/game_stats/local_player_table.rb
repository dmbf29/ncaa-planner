module GameStats
  # Turns what tools/capture/read_table.py read off a Player Stats table (a name and a number under each
  # column header, per row) into the same rows PlayerCategoryExtractor gets back from the AI: a display
  # name, the roster id when the name matches exactly one player, and one value per requested field.
  #
  # Returns nil (so the caller asks the AI instead) unless every table was read completely and each row's
  # numbers agree with each other: TAK = SOLO + ASSISTS, the averages equal yards / count, COMP% equals
  # COMP / ATT. A misread digit breaks one of those almost every time.
  class LocalPlayerTable
    HEADER_FIELDS = {
      "passing" => {
        "COMP" => :passing_completions, "ATT" => :passing_attempts, "YARDS" => :passing_yards, "TD" => :passing_tds,
        "INT" => :passing_interceptions, "RATING" => :passing_rating, "LONG" => :passing_longest,
        "SACKS" => :passing_sacks_taken, "COMP%" => :passing_avg
      },
      "rushing" => {
        "CAR" => :rushing_carries, "YARDS" => :rushing_yards, "AVG" => :rushing_avg, "TD" => :rushing_tds,
        "FUMB" => :rushing_fumbles, "YAC" => :rushing_yac, "LONG" => :rushing_longest
      },
      "receiving" => {
        "REC" => :receiving_receptions, "YARDS" => :receiving_yards, "AVG" => :receiving_avg, "TD" => :receiving_tds,
        "RAC" => :receiving_rac, "LONG" => :receiving_longest, "DROPS" => :receiving_drop
      },
      "defense" => {
        "SOLO" => :defense_solo_tackles, "ASSISTS" => :defense_assist_tackles, "TAK" => :defense_tackles, "TFL" => :defense_tfl,
        "SACK" => :defense_sacks, "INT" => :defense_interceptions, "INT YDS" => :defense_interceptions_yards,
        "INT AVG" => :defense_interceptions_avg, "INT LG" => :defense_interceptions_longest, "DEFL" => :defense_deflections,
        "FFUMB" => :defense_forced_fumbles, "FMBREC" => :defense_fumble_recoveries, "FMBYDS" => :defense_fumble_return_yards,
        "BLOCK" => :defense_blocks, "SFTY" => :defense_safeties, "TD" => :defense_touchdowns
      }
    }.freeze
    # On the name-grafted scrolled-right Defense screens INT is only there to check the rows line up.
    EXTRA_HEADER_FIELDS = HEADER_FIELDS["defense"].slice("FFUMB", "FMBREC", "FMBYDS", "BLOCK", "SFTY", "TD").merge("INT" => :check_interceptions).freeze

    # How far an average may sit from yards / count (the game rounds to one decimal).
    AVERAGE_TOLERANCE = 0.06

    attr_reader :reason, :warnings

    # Which stat category a raw table is, from the headers it has ("SOLO" only exists on Defense), or nil.
    # Lets a screenshot the capture couldn't label skip the AI classifier.
    def self.category_of(table)
      return nil unless table.is_a?(Array) && table.any?

      headers = table.first["cells"].keys
      return "passing" if (headers & %w[RATING COMP%]).any?
      return "rushing" if headers.include?("CAR")
      return "receiving" if headers.include?("REC")

      "defense" if headers.include?("SOLO")
    end

    def initialize(category:, roster:, float_fields:)
      @category = category
      @roster = roster
      @float_fields = float_fields
      @warnings = []
    end

    # tables: one raw read_table result per screenshot. fields: the fields wanted (the caller's group).
    def call(tables, fields:, extra: false)
      tables = Array(tables)
      return fail_with("nothing was read") if tables.empty? || tables.any? { |table| !table.is_a?(Array) || table.empty? }

      mapping = extra ? EXTRA_HEADER_FIELDS : HEADER_FIELDS.fetch(@category)
      wanted = fields.to_set + (extra ? [ :check_interceptions ] : [])
      rows = tables.flat_map { |table| table.map { |row| build_row(row, mapping, wanted) } }
      return nil if rows.any?(&:nil?)

      rows = rows.select { |row| row["player_display_name"].match?(/[A-Za-z]{2}/) }
      return fail_with("no players found") if rows.empty?

      rows.each { |row| return nil unless consistent?(row, extra) }
      rows
    end

    private

    def fail_with(message)
      @reason = message
      nil
    end

    def build_row(raw, mapping, wanted)
      cells = raw["cells"]
      name = raw["name"].to_s.strip
      row = { "player_display_name" => name, "student_season_id" => match_roster(name) }
      mapping.each do |header, field|
        next unless wanted.include?(field)

        value = cells[header]
        return fail_with("#{name}: no #{header} value") if value.nil?

        row[field.to_s] = coerce(field, value) or return fail_with("#{name}: #{header} #{value} isn't a whole number")
      end
      missing = wanted.reject { |field| row.key?(field.to_s) }
      return fail_with("no #{missing.join(', ')} column on the screen") if missing.any?

      row
    end

    def coerce(field, value)
      return value.to_f if @float_fields.include?(field)

      value.to_f == value.to_f.round ? value.to_f.round : nil
    end

    def consistent?(row, extra)
      checks = extra ? {} : self.class.checks_for(@category, row)
      failed = checks.reject { |_name, ok| ok }.keys
      @reason ||= "#{row['player_display_name']}: #{failed.join('; ')} doesn't hold" if failed.any?
      failed.empty?
    end

    def self.checks_for(category, row)
      average_ok = ->(total, count, average) { count.to_i.zero? ? average.to_f.zero? : (total.to_f / count - average.to_f).abs <= AVERAGE_TOLERANCE }
      case category
      when "passing"
        attempts = row["passing_attempts"]
        { "COMP% = COMP / ATT" => attempts.zero? ? row["passing_avg"].zero? : (row["passing_completions"].to_f / attempts * 100 - row["passing_avg"]).abs <= 1.0 }
      when "rushing"
        { "AVG = YARDS / CAR" => average_ok.(row["rushing_yards"], row["rushing_carries"], row["rushing_avg"]) }
      when "receiving"
        { "AVG = YARDS / REC" => average_ok.(row["receiving_yards"], row["receiving_receptions"], row["receiving_avg"]) }
      when "defense"
        {
          "TAK = SOLO + ASSISTS" => row["defense_tackles"] == row["defense_solo_tackles"] + row["defense_assist_tackles"],
          "INT AVG = INT YDS / INT" => average_ok.(row["defense_interceptions_yards"], row["defense_interceptions"], row["defense_interceptions_avg"])
        }
      else
        {}
      end
    end

    # The roster player this on-screen name ("H.Crandall", "E. Willor Jr.") is, if exactly one fits.
    # A name whose initial Vision dropped (".Williams") is matched on the last name alone.
    def match_roster(display_name)
      initial, last = display_parts(display_name)
      return nil if last.blank?

      hits = @roster.select do |player|
        first, roster_last = Student.split_full_name(player[:name])
        squash(roster_last) == squash(last) && (initial.blank? || squash(first.to_s[0]) == squash(initial))
      end
      if hits.size > 1
        names = hits.map { |player| "#{player[:name]} (#{player[:position]})" }.to_sentence(last_word_connector: " or ")
        @warnings << "#{display_name} could be #{names}; pick the right player in the review, or both lines get saved to one new player." unless @warnings.any? { |w| w.start_with?("#{display_name} could be") }
      end
      hits.one? ? hits.first[:id] : nil
    end

    def display_parts(name)
      match = name.match(/\A([A-Za-z]?)\.\s*(.+)\z/)
      match ? [ match[1], match[2] ] : [ nil, nil ]
    end

    # Vision's look-alikes (capital I / lowercase l / 1, O / 0) must not keep a name from matching.
    def squash(text)
      text.to_s.downcase.gsub(/[^a-z0-9]/, "").tr("l1", "ii").tr("0", "o")
    end
  end
end
