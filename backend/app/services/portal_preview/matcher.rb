module PortalPreview
  # Resolves an extracted "players leaving" row to an existing StudentSeason
  # on this specific college_season's current roster. Unlike
  # RosterImport::Matcher there's no previous-season fallback — every name
  # on this screen should already be on THIS season's tracked roster, since
  # it's read at the end of that same season. The screen shows position and
  # class year alongside the name, so matching on (last name, first
  # initial, position) is reliable without needing that fallback.
  #
  # Failing to match is expected and fine (a stale/test screenshot, or a
  # player never scraped onto the roster) — an unmatched row is still worth
  # keeping with its raw fields, just without a student_season link.
  class Matcher
    def initialize(college_season)
      @student_seasons = college_season.student_seasons.includes(:student).to_a
    end

    def resolve_each(rows)
      Array(rows).map { |row| row.merge(match_fields(row)) }
    end

    private

    def match_fields(row)
      candidates = candidates_for(row)
      case candidates.size
      when 0
        { student_season_id: nil, match_status: "unmatched" }
      when 1
        { student_season_id: candidates.first.id, match_status: "matched" }
      else
        best = candidates.find { |ss| ss.class_year == row[:class_year] } || candidates.first
        { student_season_id: best.id, match_status: "ambiguous" }
      end
    end

    def candidates_for(row)
      initial = row[:first_initial].to_s.strip[0]&.downcase
      last = row[:last_name].to_s.strip.downcase
      position = row[:position].to_s.strip.downcase

      @student_seasons.select do |ss|
        ss.student.last_name.to_s.strip.downcase == last &&
          ss.student.first_name.to_s.strip[0]&.downcase == initial &&
          ss.position.to_s.strip.downcase == position
      end
    end
  end
end
