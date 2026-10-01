# Coached teams' signed recruits with the overall to display/edit. HS/JUCO
# overalls are hand-entered (signed_recruits.overall); a transfer's is the
# overall of its linked student's StudentSeason this season, or nil when it
# couldn't be matched.
class SignedRecruitOverallsSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    college_seasons = @season.college_seasons.where.not(coach_id: nil)
                             .includes(:college, signed_recruits: :student).order("colleges.name")
                             .references(:colleges)
    overalls = transfer_overalls(college_seasons)

    college_seasons.map do |college_season|
      recruits = college_season.signed_recruits.sort_by { |sr| [ sr.transfer ? 1 : 0, -(sr.star_rating || 0), sr.last_name.to_s.downcase ] }
      {
        college: { id: college_season.college.id, name: college_season.college.name },
        recruits: recruits.map { |sr| recruit_json(sr, overalls) }
      }
    end
  end

  private

  def transfer_overalls(college_seasons)
    student_ids = college_seasons.flat_map(&:signed_recruits).select(&:transfer).filter_map(&:student_id)
    StudentSeason.where(college_season_id: @season.college_seasons.select(:id), student_id: student_ids)
                 .pluck(:student_id, :overall).to_h
  end

  def recruit_json(recruit, transfer_overalls)
    {
      id: recruit.id,
      name: recruit.name,
      position: recruit.position,
      star_rating: recruit.star_rating,
      class_year: recruit.class_year,
      state: recruit.state,
      national_rank: recruit.national_rank,
      transfer: recruit.transfer,
      overall: recruit.transfer ? transfer_overalls[recruit.student_id] : recruit.overall,
      matched: recruit.transfer ? recruit.student_id.present? : nil
    }
  end
end
