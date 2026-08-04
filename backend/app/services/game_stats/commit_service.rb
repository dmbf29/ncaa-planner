module GameStats
  # Persists a (possibly user-edited) confirmed extraction: attaches the
  # already-uploaded screenshots, updates the Game's narrative fields, and
  # upserts CollegeGameStat / StudentGameStat rows. A player who appears in
  # multiple category rows (e.g. a rushing QB) naturally merges onto one
  # StudentGameStat record since each row only touches the columns it has
  # values for.
  class CommitService
    def initialize(game)
      @game = game
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
        next if row[:student_season_id].blank?

        stat = StudentGameStat.find_or_initialize_by(game: @game, student_season_id: row[:student_season_id])
        stat.assign_attributes(row[:fields].slice(*StatFields::PLAYER_FIELDS))
        stat.save!
      end
    end

    def resolve_college(team_name)
      [ @game.home_college, @game.away_college ].find { |college| college.name == team_name }
    end
  end
end
