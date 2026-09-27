module PortalPreview
  # Formats a college_season's already-saved PortalStatus rows in the same
  # shape Extractor#call's players array uses, so the frontend can load
  # existing data into the exact same editable review table an upload
  # produces — e.g. to record what happened after a coach tries to
  # persuade a few players to stay, without needing a fresh screenshot.
  #
  # Saved rows that were never linked to a roster record get another pass
  # through Matcher, so a row saved before a matching fix (or before the
  # player was on the roster) comes back with a suggested link the
  # reviewer can keep by saving. The roster itself is returned alongside
  # so the reviewer can link any remaining rows by hand.
  class CurrentStatuses
    def call(college_season)
      matcher = Matcher.new(college_season)
      college_season.portal_statuses.order(:last_name).map do |ps|
        row = row_json(ps)
        row[:student_season_id].present? ? row : matcher.resolve_each([ row ]).first
      end
    end

    def roster(college_season)
      college_season.student_seasons.includes(:student).map do |ss|
        {
          student_season_id: ss.id,
          first_name: ss.student.first_name,
          last_name: ss.student.last_name,
          position: ss.position,
          class_year: ss.class_year,
          overall: ss.overall
        }
      end.sort_by { |player| [ player[:last_name].to_s.downcase, player[:first_name].to_s.downcase ] }
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
        match_status: portal_status.student_season_id.present? ? "matched" : "unmatched"
      }
    end
  end
end
