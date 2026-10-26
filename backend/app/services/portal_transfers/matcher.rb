module PortalTransfers
  # Resolves the players tools/transfer_video read off a "players leaving" recording to StudentSeasons on this
  # season's rosters, so Mark Transfers can flag them in_portal and refresh their ratings.
  #
  # Nothing here creates players: a row that can't be tied to exactly one existing StudentSeason comes back
  # "unmatched" (or "ambiguous") for the reviewer to see. The screen shows the *current* team, so a player is only
  # looked for on that team's roster for this season; names are full (first and last) because the right-hand pane is
  # read, the same as the roster-video import.
  #
  # "unhighlighted" rows are Transfer rows the video saw in the table but never had selected, so only an initial,
  # last name and overall are known. They are matched on that and can be flagged, but their attribute ratings are
  # left alone.
  class Matcher
    include CollegeMatching

    STAT_FIELDS = %w[overall speed acceleration agility change_of_direction strength awareness].freeze
    BIO_FIELDS = %w[archetype height_inches weight_lbs].freeze

    def initialize(season)
      @season = season
      @college_seasons = season.college_seasons.to_a.index_by(&:college_id)
      @rosters = {}
    end

    def call(extraction)
      rows = Array(extraction["players"]).map { |row| resolve(row.with_indifferent_access, partial: false) } +
             Array(extraction["unhighlighted"]).map { |row| resolve(row.with_indifferent_access, partial: true) }
      { rows: rows, summary: summary(rows) }
    end

    private

    def resolve(row, partial:)
      college = resolve_team(row[:team])
      college_season = college && @college_seasons[college.id]
      college_season ||= unique_roster_for(row) unless college
      college ||= college_season&.college
      base = {
        team: row[:team], college_id: college&.id, college_name: college&.name, college_season_id: college_season&.id,
        name: partial ? "#{row[:first_initial]}. #{row[:last_name]}" : "#{row[:first_name]} #{row[:last_name]}",
        position: row[:position], class_year: row[:class_year], transfer_reason: row[:transfer_reason],
        partial: partial, needs_review: Array(row[:needs_review])
      }
      return base.merge(status: "unmatched_team") unless college_season

      candidates = candidates_for(college_season, row, partial: partial)
      return base.merge(status: "unmatched") if candidates.empty?
      return base.merge(status: "ambiguous", candidates: candidates.map { |ss| describe(ss) }) if candidates.size > 1

      match = candidates.first
      incoming = incoming_values(row, partial: partial)
      ratings = partial ? {} : row[:ratings].to_h.transform_values(&:to_i)
      base.merge(status: "matched", student_season_id: match.id, matched_name: match.student.name,
                 already_in_portal: match.in_portal, current: current_values(match), incoming: incoming,
                 current_ratings: match.ratings.slice(*ratings.keys), incoming_ratings: ratings,
                 changed: (incoming.reject { |field, value| match[field] == value }.keys +
                          ratings.reject { |key, value| match.ratings[key] == value }.keys).uniq)
    end

    # An unreadable banner: if exactly one college_season has a roster player with this name and position, that's the team.
    def unique_roster_for(row)
      hits = @season.college_seasons.includes(:college).select do |cs|
        candidates_for(cs, row, partial: row[:first_name].blank?).size == 1
      end
      hits.first if hits.one?
    end

    # The banner OCR picks up stray marks ("• MIAMI UNIVERSITY", "- TEXAS", "7 GEORGIA STATE") and drops punctuation
    # ("Hawai'i", "Texas A&M" -> "TEXAS ASM"), so after the exact lookup the names are compared as bare letters,
    # allowing one slip on longer names when only one college is that close.
    def resolve_team(raw)
      cleaned = raw.to_s.sub(/\A[^A-Za-z]+/, "").strip
      resolve_college(cleaned) || begin
        key = fold(cleaned)
        keyed = colleges_by_matchable_name.transform_keys { |name| fold(name) }
        keyed[key] || fuzzy_unique(keyed, key)
      end
    end

    def fuzzy_unique(keyed, key)
      return if key.length < 6

      close = keyed.select { |name, _| name.length >= 6 && StringDistance.levenshtein(name, key) <= 1 }.values.uniq
      close.first if close.one?
    end

    def candidates_for(college_season, row, partial:)
      roster = (@rosters[college_season.id] ||= college_season.student_seasons.includes(:student).to_a)
      last = fold(row[:last_name])
      position = PositionBoardMapping.canonical(row[:position]) if row[:position].present?

      by_name = roster.select do |ss|
        (last_names_match?(fold(ss.student.last_name), last) || same_first_and_close_last?(ss, row, last, partial)) &&
          (partial ? first_initial(ss) == row[:first_initial].to_s.strip.downcase[0] : RosterImport::Matcher.same_first_name?(ss.student.first_name, row[:first_name]))
      end
      by_name = by_name.select { |ss| PositionBoardMapping.canonical(ss.position) == position } if position && by_name.size > 1
      return by_name if by_name.size < 2 || partial

      exact = by_name.select { |ss| ss.student.first_name.to_s.strip.downcase == row[:first_name].to_s.strip.downcase }
      exact.any? ? exact : by_name
    end

    def first_initial(student_season)
      student_season.student.first_name.to_s.strip.downcase[0]
    end

    # One OCR slip is tolerated on longer names; the I/l/1 and O/0 lookalikes are folded first.
    def last_names_match?(a, b)
      a == b || (a.length >= 6 && b.length >= 6 && StringDistance.levenshtein(a, b) <= 1)
    end

    # "Elijah Hrown" for "Elijah Brown": a short last name can't take a one-letter slip on its own, but an exact
    # first name on the same roster makes it safe.
    def same_first_and_close_last?(student_season, row, last, partial)
      return false if partial

      mine = fold(student_season.student.last_name)
      mine.length >= 4 && last.length >= 4 && StringDistance.levenshtein(mine, last) <= 1 &&
        student_season.student.first_name.to_s.strip.casecmp?(row[:first_name].to_s.strip)
    end

    def fold(text)
      text.to_s.downcase.gsub(/\s+(jr|sr|ii|iii|iv)\.?\z/, "").gsub(/[^a-z0-9]/, "")
    end

    def incoming_values(row, partial:)
      fields = partial ? %w[overall] : STAT_FIELDS
      values = fields.each_with_object({}) { |field, hash| hash[field] = row[field].to_i if row[field].present? }
      return values if partial

      BIO_FIELDS.each { |field| values[field] = (field == "archetype" ? row[field].to_s : row[field].to_i) if row[field].present? }
      values
    end

    def current_values(student_season)
      (STAT_FIELDS + BIO_FIELDS).index_with { |field| student_season[field] }
    end

    def describe(student_season)
      { student_season_id: student_season.id, name: student_season.student.name, position: student_season.position,
        class_year: student_season.class_year, overall: student_season.overall }
    end

    def summary(rows)
      counts = rows.group_by { |row| row[:status] }.transform_values(&:size)
      { total: rows.size, matched: counts["matched"].to_i, ambiguous: counts["ambiguous"].to_i,
        unmatched: counts["unmatched"].to_i, unmatched_team: counts["unmatched_team"].to_i }
    end
  end
end
