module GameStats
  # Persists a (possibly user-edited) confirmed extraction: attaches the
  # already-uploaded screenshots, updates the Game's narrative fields, and
  # upserts CollegeGameStat / StudentGameStat rows (player lines only for players already on a roster). A player who appears in
  # multiple category rows (e.g. a rushing QB) naturally merges onto one
  # StudentGameStat record since each row only touches the columns it has
  # values for.
  class CommitService
    def initialize(game)
      @game = game
    end

    # replace_screenshot_sections ("box_score" / "home" / "away"): for those sections the newly
    # attached screenshots replace whatever was attached before (a fresh capture of the whole
    # section, so keeping the old ones would only clutter the gallery and inflate any
    # "re-analyze existing"). The old ones are removed only after the whole commit succeeds.
    def call(box_score_screenshot_signed_ids:, home_screenshot_signed_ids:, away_screenshot_signed_ids:, narrative:, college_stats:, player_stats:,
             replace_screenshot_sections: [])
      replace = Array(replace_screenshot_sections).map(&:to_s)
      @stale_attachments = []
      ActiveRecord::Base.transaction do
        attach_screenshots(@game.box_score_screenshots, box_score_screenshot_signed_ids, replace: replace.include?("box_score"))
        attach_screenshots(@game.home_stat_screenshots, home_screenshot_signed_ids, replace: replace.include?("home"))
        attach_screenshots(@game.away_stat_screenshots, away_screenshot_signed_ids, replace: replace.include?("away"))
        update_narrative(narrative)
        upsert_college_stats(college_stats)
        upsert_player_stats(player_stats)
      end
      @stale_attachments.each(&:purge_later)
      @game
    end

    private

    def attach_screenshots(attachment, signed_ids, replace: false)
      return if signed_ids.blank?

      blobs = Array(signed_ids).filter_map { |signed_id| ActiveStorage::Blob.find_signed(signed_id) }
      return if blobs.empty?

      @stale_attachments.concat(attachment.attachments.to_a.reject { |existing| blobs.include?(existing.blob) }) if replace
      attachment.attach(blobs)
    end

    def update_narrative(narrative)
      return if narrative.blank?

      @game.update!(
        narrative_summary: narrative[:narrative_summary].presence,
        additional_context: narrative[:additional_context].presence,
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
        fields = row[:fields].slice(*StatFields::PLAYER_FIELDS)
        # An all-zero line for someone with no saved stats yet isn't worth recording. If they
        # already have a line, still apply it so a wrong value can be corrected back down to 0.
        next if StatFields.empty_line?(fields) && !saved_stat?(row)

        student_season = resolve_student_season(row)
        next unless student_season

        stat = StudentGameStat.find_or_initialize_by(game: @game, student_season: student_season)
        stat.assign_attributes(fields)
        stat.save!
      end
    end

    def saved_stat?(row)
      row[:student_season_id].present? && StudentGameStat.exists?(game: @game, student_season_id: row[:student_season_id])
    end

    # Rosters are imported at the start of the season, so a line only lands on an existing player. A row
    # nobody was picked for in the review is skipped rather than creating a new player.
    def resolve_student_season(row)
      StudentSeason.find_by(id: row[:student_season_id]) if row[:student_season_id].present?
    end

    def resolve_college(team_name)
      [ @game.home_college, @game.away_college ].find { |college| college.name == team_name }
    end
  end
end
