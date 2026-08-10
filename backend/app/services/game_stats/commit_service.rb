module GameStats
  # Persists a (possibly user-edited) confirmed extraction: attaches the
  # already-uploaded screenshots, updates the Game's narrative fields, and
  # upserts CollegeGameStat / StudentGameStat rows. A player who appears in
  # multiple category rows (e.g. a rushing QB) naturally merges onto one
  # StudentGameStat record since each row only touches the columns it has
  # values for.
  class CommitService
    # Rough fallback when a newly-created player's position can't be known
    # from a stat screenshot alone — the category at least narrows it down.
    # Purely a starting point: position is free text, so the user can
    # correct it in the review form before saving.
    DEFAULT_POSITION_BY_CATEGORY = { "passing" => "QB", "rushing" => "HB", "receiving" => "WR", "defense" => "MLB" }.freeze

    def initialize(game)
      @game = game
      # Dedupes a player who shows up unmatched in more than one category
      # row within the same commit (e.g. a rushing QB's passing + rushing
      # rows) so they land on one StudentSeason instead of two.
      @created_student_seasons = {}
    end

    def call(screenshot_signed_ids:, narrative:, college_stats:, player_stats:)
      ActiveRecord::Base.transaction do
        attach_screenshots(screenshot_signed_ids)
        update_narrative(narrative)
        upsert_college_stats(college_stats)
        upsert_player_stats(player_stats)
      end
      @game
    end

    private

    def attach_screenshots(signed_ids)
      return if signed_ids.blank?

      blobs = Array(signed_ids).filter_map { |signed_id| ActiveStorage::Blob.find_signed(signed_id) }
      @game.stat_screenshots.attach(blobs) if blobs.any?
    end

    def update_narrative(narrative)
      return if narrative.blank?

      @game.update!(
        narrative_summary: narrative[:narrative_summary].presence,
        offensive_player_of_game_id: narrative[:offense_player_of_game_id].presence,
        offensive_player_stat_line: narrative[:offense_player_stat_line].presence,
        defensive_player_of_game_id: narrative[:defense_player_of_game_id].presence,
        defensive_player_stat_line: narrative[:defense_player_stat_line].presence
      )
    end

    def upsert_college_stats(rows)
      Array(rows).each do |row|
        college = resolve_college(row[:team])
        next unless college

        stat = CollegeGameStat.find_or_initialize_by(game: @game, college: college)
        stat.assign_attributes(row[:fields].slice(*StatFields::COLLEGE_FIELDS))
        stat.save!
      end
    end

    def upsert_player_stats(rows)
      Array(rows).each do |row|
        student_season = resolve_student_season(row)
        next unless student_season

        stat = StudentGameStat.find_or_initialize_by(game: @game, student_season: student_season)
        stat.assign_attributes(row[:fields].slice(*StatFields::PLAYER_FIELDS))
        stat.save!
      end
    end

    def resolve_student_season(row)
      return StudentSeason.find_by(id: row[:student_season_id]) if row[:student_season_id].present?

      create_or_reuse_student_season(row)
    end

    # A player the AI couldn't confidently match to the existing roster —
    # rather than discard their stats, create the Student/StudentSeason so
    # the data isn't lost. Reuses Student.find_or_create_for_college (the
    # same dedupe-by-name-within-college helper ScrapeStudentsJob uses) so
    # this player is found instead of re-created next time they show up.
    def create_or_reuse_student_season(row)
      name = row[:display_name].to_s.strip
      team = row[:team]
      return nil if name.blank? || team.blank?

      college = resolve_college(team)
      return nil unless college

      first_name, last_name = split_display_name(name)
      return nil if last_name.blank?

      cache_key = [ college.id, "#{first_name} #{last_name}".downcase ]
      return @created_student_seasons[cache_key] if @created_student_seasons.key?(cache_key)

      college_season = CollegeSeason.find_or_create_by!(college: college, season: @game.week.season)
      student = Student.find_or_create_for_college(first_name: first_name, last_name: last_name, college: college)
      student_season = student.student_seasons.find_or_initialize_by(college_season: college_season)
      if student_season.new_record?
        student_season.position = row[:position].presence || DEFAULT_POSITION_BY_CATEGORY[row[:category]] || "HB"
        student_season.class_year = row[:class_year].presence || "FR"
        student_season.save!
      end

      @created_student_seasons[cache_key] = student_season
    end

    # AI-extracted names come as "H.Crandall" (first-initial + last name,
    # per PlayerCategoryExtractor's prompt) unless the user edited the
    # review field to a full name — handle both. Full-name splitting
    # matches ScrapeStudentsJob#split_name (last word = last name) so the
    # same person resolves to the same Student either way.
    def split_display_name(name)
      match = name.match(/\A([A-Za-z])\.\s*(.+)\z/)
      return [ match[1], match[2].strip ] if match

      parts = name.split(/\s+/)
      return [ parts.first, "" ] if parts.size == 1

      [ parts[0..-2].join(" "), parts[-1] ]
    end

    def resolve_college(team_name)
      [ @game.home_college, @game.away_college ].find { |college| college.name == team_name }
    end
  end
end
