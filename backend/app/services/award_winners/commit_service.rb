module AwardWinners
  # Persists the (user-edited) set of award winners for one season. One row
  # per award the page submitted:
  #   - player award  -> { award_id, student_season_id }
  #   - coach award    -> { award_id, coach_id }  OR  { award_id, coach_name }
  #     (a name with no id spins up / reuses a CPU coach for the dynasty)
  #   - cleared        -> { award_id } with no recipient -> removes the winner
  #
  # Each row is independent: a validation failure is caught and reported as a
  # warning rather than aborting the batch, matching the other season commit
  # services.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(rows)
      Array(rows).filter_map { |row| commit_row(row.deep_symbolize_keys) }
    end

    private

    def commit_row(row)
      award = Award.find_by(id: row[:award_id])
      return { award: nil, error: "Award not found" } unless award

      season_award = @season.season_awards.find_or_initialize_by(award_id: award.id)
      student_season, coach = resolve_recipient(award, row)

      if student_season.nil? && coach.nil?
        season_award.destroy if season_award.persisted?
        return nil
      end

      season_award.update!(student_season: student_season, coach: coach, stat_line: row[:stat_line].presence)
      nil
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      { award: award&.name, error: e.message }
    end

    # Returns [student_season, coach] with exactly one set, or [nil, nil] to
    # clear the award.
    def resolve_recipient(award, row)
      if award.coach_award?
        [ nil, resolve_coach(row) ]
      else
        [ resolve_student_season(row), nil ]
      end
    end

    def resolve_coach(row)
      return Coach.find_by(id: row[:coach_id]) if row[:coach_id].present?
      return nil if row[:coach_name].blank?

      Coach.find_or_create_for_dynasty!(dynasty: @season.dynasty, name: row[:coach_name])
    end

    def resolve_student_season(row)
      return nil if row[:student_season_id].blank?

      student_season = StudentSeason.joins(:college_season)
                                    .where(college_seasons: { season_id: @season.id })
                                    .find_by(id: row[:student_season_id])
      return student_season if student_season

      raise ActiveRecord::RecordNotFound, "Player is not part of this season"
    end
  end
end
