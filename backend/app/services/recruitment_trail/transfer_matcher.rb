module RecruitmentTrail
  # Links a portal-transfer signee to the Student they were on their
  # previous college's roster, so the transfer's overall can be read from
  # that student's StudentSeason for the same season (the NSD breakdown
  # compares it to the starter the team lost). Overall is NOT copied onto
  # the signed_recruit: ratings only move at offseason progression, so
  # reading it live keeps one source of truth.
  #
  # Matching is league-wide for the season (first initial, last name) since
  # we don't know which school they left. Position narrows it but isn't
  # required to be a candidate — the recruit screen uses newer labels
  # (REDG, ...) that PositionBoardMapping.canonical reconciles, and a player
  # can be listed at a different spot. Auto-link only happens when exactly
  # one candidate also shares the canonical position; anything else is left
  # for the reviewer to pick by hand, because a wrong link would put someone
  # else's overall in the podcast.
  class TransferMatcher
    SUFFIXES = %w[jr sr ii iii iv v].freeze
    # Most candidates offered when nothing matches by name and the reviewer
    # has to browse by initials + position instead.
    LOOSE_LIMIT = 40

    def initialize(season)
      student_seasons = StudentSeason.joins(:college_season, :student)
                                     .where(college_seasons: { season_id: season.id })
                                     .includes(:student, college_season: :college)
      @entries = student_seasons.map { |ss| { student_season: ss, tokens: name_tokens("#{ss.student.first_name} #{ss.student.last_name}") } }
      @by_last_token = @entries.group_by { |entry| entry[:tokens].last }
    end

    # Review-screen fields for one extracted transfer row. When nothing fits
    # by name, falls back to everyone sharing first initial, last initial and
    # position so the reviewer can still link by hand.
    def resolve(first_initial:, last_name:, position:)
      initial = first_initial.to_s.strip[0]&.downcase
      last_tokens = name_tokens(last_name)
      candidates = candidates_for(initial, last_tokens)
      loose = candidates.empty?
      candidates = loose_candidates_for(initial, last_tokens, position) if loose

      exact = loose ? [] : candidates.select { |ss| same_position?(ss, position) }
      student_id = exact.first.student_id if exact.size == 1
      {
        student_id: student_id,
        match_status: if student_id then "matched" elsif candidates.empty? || loose then "unmatched" else "ambiguous" end,
        candidates: candidates.map { |ss| candidate_json(ss, last_tokens.size) },
        loose_candidates: loose && candidates.any?
      }
    end

    # The Student for an already-saved recruit (backfill), nil unless unambiguous.
    def student_for(recruit)
      resolve(first_initial: recruit.first_name, last_name: recruit.last_name, position: recruit.position)[:student_id]
    end

    private

    # The roster stores some multi-word surnames split across first_name and
    # last_name ("Michael Van" / "Buren Jr."), so names are compared as whole
    # token lists (suffixes and punctuation dropped) instead of by the stored
    # last_name: the screen's surname must be the tail of the roster's full
    # name, and the first initial must start it.
    def candidates_for(initial, last_tokens)
      return [] if last_tokens.empty?

      Array(@by_last_token[last_tokens.last]).select do |entry|
        entry[:tokens].first&.start_with?(initial.to_s) && entry[:tokens].last(last_tokens.size) == last_tokens
      end.map { |entry| entry[:student_season] }
    end

    def loose_candidates_for(initial, last_tokens, position)
      last_initial = last_tokens.first&.first
      return [] if initial.blank? || last_initial.nil?

      @entries.select do |entry|
        tokens = entry[:tokens]
        tokens.first&.start_with?(initial) && tokens.size > 1 && tokens[1..].any? { |t| t.start_with?(last_initial) } &&
          same_position?(entry[:student_season], position)
      end.map { |entry| entry[:student_season] }.sort_by { |ss| -(ss.overall || 0) }.first(LOOSE_LIMIT)
    end

    def name_tokens(text)
      tokens = text.to_s.downcase.gsub(/[^a-z\s'-]/, " ").split
      tokens.pop while tokens.size > 1 && SUFFIXES.include?(tokens.last)
      tokens
    end

    def same_position?(student_season, position)
      PositionBoardMapping.canonical(student_season.position) == PositionBoardMapping.canonical(position)
    end

    # The roster's first_name can hold half a multi-word surname, so the
    # real first name is the full name minus the screen's surname words
    # (and any Jr./III suffix).
    def first_name_for(student_season, surname_word_count)
      words = "#{student_season.student.first_name} #{student_season.student.last_name}".split
      words.pop while words.size > 1 && SUFFIXES.include?(words.last.downcase.delete("."))
      surname_word_count.positive? ? words.first([ words.size - surname_word_count, 1 ].max).join(" ") : words.first
    end

    def candidate_json(student_season, surname_word_count)
      {
        student_id: student_season.student_id,
        first_name: first_name_for(student_season, surname_word_count),
        name: "#{student_season.student.first_name} #{student_season.student.last_name}".strip,
        position: student_season.position,
        class_year: student_season.class_year,
        overall: student_season.overall,
        college: student_season.college_season.college.name
      }
    end
  end
end
