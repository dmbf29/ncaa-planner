module TeamStats
  # Persists a (possibly user-edited) team offense/defense stats table for
  # one season. Purely team-level data — no Student/StudentSeason involved —
  # so each row just finds-or-creates the CollegeSeason (same reasoning as
  # ConferenceStandings/NilSpend: a freshly-started season won't have one
  # yet for anything but the coached teams) and overwrites only that stat
  # type's columns with this upload, since it's meant to be the definitive
  # current status, not a merge. Offense and defense are uploaded/committed
  # independently, so committing one never touches the other's columns.
  #
  # Each row commits independently and a validation failure is caught and
  # reported as a warning rather than aborting the rest of the batch,
  # mirroring the other CommitServices.
  class CommitService
    FIELDS_BY_TYPE = {
      "offense" => %i[
        points_scored total_offensive_yards yards_per_play passing_yards
        passing_touchdowns rushing_yards rushing_touchdowns first_downs
      ],
      "defense" => %i[
        points_allowed total_yards_allowed passing_yards_allowed rushing_yards_allowed
        defensive_sacks fumble_recoveries defensive_interceptions
      ]
    }.freeze

    def initialize(season, stat_type)
      @season = season
      @fields = FIELDS_BY_TYPE.fetch(stat_type)
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { team: symbolized[:college_raw_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      college = College.find_by(id: row[:college_id])
      return if college.blank?

      college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
      college_season.update!(row.slice(*@fields))
    end
  end
end
