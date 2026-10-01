module SignedRecruitOveralls
  # Saves the hand-entered overall for high school / JUCO signees. A blank
  # overall clears it (the NSD breakdown then falls back to star tier). Rows
  # are looked up inside the season's college_seasons so a stale or foreign
  # id can't touch another dynasty's recruit, and transfers are skipped —
  # theirs comes from their StudentSeason, never from typing.
  class CommitService
    def initialize(season)
      @recruits = SignedRecruit.where(college_season_id: season.college_seasons.select(:id))
    end

    def call(rows)
      Array(rows).filter_map do |row|
        recruit = @recruits.find_by(id: row[:id])
        next { recruit: "id #{row[:id]}", error: "not found" } unless recruit
        next { recruit: recruit.name, error: "transfer overalls come from the roster" } if recruit.transfer

        recruit.update!(overall: row[:overall].presence)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { recruit: recruit.name, error: e.message }
      end
    end
  end
end
