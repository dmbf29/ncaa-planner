module PortalTransfers
  # Flags the reviewed transfer rows in_portal and writes the ratings read off the screen onto the player's
  # StudentSeason (overall and the six attribute tiles shown for their position). No players are created, and only rows
  # for this season's rosters are touched. A row that fails validation is reported as a warning instead of
  # aborting the batch, like the other CommitServices.
  #
  # clear_first: true un-flags everyone in the season first, for re-recording the whole portal from scratch;
  # without it recordings accumulate, so several partial videos can be committed one after another.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(rows, clear_first: false)
      scope = StudentSeason.joins(:college_season).where(college_seasons: { season_id: @season.id })
      scope.where(in_portal: true).update_all(in_portal: false) if clear_first

      Array(rows).filter_map do |row|
        student_season = scope.find_by(id: row[:student_season_id])
        next { player: row[:name], error: "player not found in this season" } unless student_season

        attributes = Matcher::STAT_FIELDS.each_with_object({ in_portal: true }) do |field, hash|
          hash[field] = row[field.to_sym].to_i if row[field.to_sym].present?
        end
        Matcher::BIO_FIELDS.each { |field| attributes[field] = row[field.to_sym] if row[field.to_sym].present? }
        # Position-specific tiles merge into what's on file, so a rating the screen didn't show this time is kept.
        attributes[:ratings] = student_season.ratings.merge(row[:ratings].to_h.transform_keys(&:to_s).transform_values(&:to_i)) if row[:ratings].present?
        student_season.update!(attributes)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: row[:name], error: e.message }
      end
    end
  end
end
