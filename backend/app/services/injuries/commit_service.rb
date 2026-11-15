module Injuries
  # Persists the reviewed injury rows from the injury report upload. A row for a player who already has an injury
  # with the same description this season is skipped (the same injury, re-uploaded), so the earlier record and its
  # starting week stay as they were. Each row commits on its own and a validation failure is reported as a warning
  # instead of aborting the batch, like the other CommitServices.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: symbolized[:raw_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      student_season = StudentSeason.joins(college_season: :season)
                                    .where(seasons: { id: @season.id }).find_by(id: row[:student_season_id])
      return if student_season.blank? || row[:game_id].blank?

      key = Student.match_key(row[:description])
      return if student_season.injuries.any? { |injury| Student.match_key(injury.description) == key }

      student_season.injuries.create!(game_id: row[:game_id], description: row[:description], weeks_out: row[:weeks_out])
    end
  end
end
