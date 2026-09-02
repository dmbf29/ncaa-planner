module PortalPreview
  # Persists a (user-reviewed) roster-outlook snapshot for one coached
  # program in one season. A full 85-man roster's "players leaving" screen
  # is many pages long, so this is expected to get uploaded across several
  # separate sessions rather than always as one complete batch — each row
  # upserts rather than the whole set replacing what's already there, so
  # an earlier upload's players survive a later, different upload for the
  # same team. Re-uploading a row for a player already on file (e.g. a
  # corrected screenshot, or an overlapping page seen again) updates that
  # existing row in place instead of duplicating it.
  #
  # Matched rows upsert on student_season_id (one row per player, however
  # many times they show up across uploads). Unmatched rows upsert on
  # (last_name, position, class_year) — the same natural key
  # Extractor#dedupe already collapses same-upload repeats on — which is
  # the best identity available for a player the app can't link to an
  # actual roster record.
  #
  # Each row commits independently; a validation failure is caught and
  # reported as a warning rather than aborting the rest of the batch,
  # mirroring the other CommitServices.
  #
  # Since a commit no longer wholesale-replaces the set, an explicit
  # removal (the reviewer deleting a row that shouldn't be tracked at all)
  # needs its own signal — removed_ids, PortalStatus primary keys, scoped
  # to this college_season so a stray id can't reach into another team's
  # rows.
  class CommitService
    def initialize(college_season)
      @college_season = college_season
    end

    def call(rows, removed_ids: [])
      @college_season.portal_statuses.where(id: Array(removed_ids)).destroy_all

      Array(rows).filter_map do |raw_row|
        row = raw_row.deep_symbolize_keys
        commit_row(row)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { player: row[:last_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      return if row[:last_name].blank? || row[:position].blank? || row[:status].blank?

      portal_status = find_or_initialize(row)
      portal_status.assign_attributes(
        student_season_id: row[:student_season_id],
        first_initial: row[:first_initial],
        last_name: row[:last_name],
        position: row[:position],
        class_year: row[:class_year],
        overall: row[:overall],
        status: row[:status],
        transfer_reason: row[:transfer_reason],
        projected_draft_round: row[:projected_draft_round],
        persuasion_chance: row[:persuasion_chance]
      )
      portal_status.save!
    end

    def find_or_initialize(row)
      if row[:student_season_id].present?
        @college_season.portal_statuses.find_or_initialize_by(student_season_id: row[:student_season_id])
      else
        @college_season.portal_statuses.find_or_initialize_by(
          student_season_id: nil, last_name: row[:last_name], position: row[:position], class_year: row[:class_year]
        )
      end
    end
  end
end
