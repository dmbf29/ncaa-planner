module PortalPreview
  # Formats a college_season's already-saved PortalStatus rows in the same
  # shape Extractor#call's players array uses, so the frontend can load
  # existing data into the exact same editable review table an upload
  # produces — e.g. to record what happened after a coach tries to
  # persuade a few players to stay, without needing a fresh screenshot.
  class CurrentStatuses
    def call(college_season)
      college_season.portal_statuses.order(:last_name).map { |ps| row_json(ps) }
    end

    private

    def row_json(portal_status)
      {
        id: portal_status.id,
        student_season_id: portal_status.student_season_id,
        first_initial: portal_status.first_initial,
        last_name: portal_status.last_name,
        position: portal_status.position,
        class_year: portal_status.class_year,
        overall: portal_status.overall,
        status: portal_status.status,
        transfer_reason: portal_status.transfer_reason,
        projected_draft_round: portal_status.projected_draft_round,
        persuasion_chance: portal_status.persuasion_chance,
        match_status: portal_status.student_season_id.present? ? "matched" : "unmatched"
      }
    end
  end
end
