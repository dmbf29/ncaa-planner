# One coached team's signing class for a season: every signee (HS, JUCO and
# portal transfer) with, for transfers, the school they left and the overall
# they bring, both read from the linked student's StudentSeason this season
# (see RecruitmentTrail::TransferMatcher). `matched` is false for a transfer
# that was never linked, so the page can show its origin as unknown.
#
# Signees are recorded against the season they signed in and enroll the
# following one, so `previous_season` / `next_season` let the page flip between
# this college's classes.
class SigningClassSerializer
  def initialize(college_season)
    @college_season = college_season
  end

  def as_json
    season = @college_season.season
    recruits = @college_season.signed_recruits.includes(:student).to_a
    seasons = transfer_seasons(recruits)

    {
      college: { id: @college_season.college.id, name: @college_season.college.name },
      season: { id: season.id, year: season.year },
      previous_season: adjacent(season.year - 1),
      next_season: adjacent(season.year + 1),
      signees: recruits.sort_by { |sr| [ type_order(sr), -(sr.star_rating || 0), sr.last_name.to_s.downcase ] }
                       .map { |sr| signee_json(sr, seasons[sr.student_id]) }
    }
  end

  private

  def adjacent(year)
    season = @college_season.season.dynasty.seasons.find_by(year: year)
    college_season = season && season.college_seasons.find_by(college_id: @college_season.college_id)
    college_season && { season_id: season.id, college_season_id: college_season.id, year: year }
  end

  def transfer_seasons(recruits)
    student_ids = recruits.select(&:transfer).filter_map(&:student_id)
    StudentSeason.where(college_season_id: @college_season.season.college_seasons.select(:id), student_id: student_ids)
                 .includes(college_season: :college).index_by(&:student_id)
  end

  def type_for(recruit)
    return "transfer" if recruit.transfer

    recruit.class_year.to_s.start_with?("JC") ? "juco" : "high_school"
  end

  def type_order(recruit)
    { "transfer" => 0, "high_school" => 1, "juco" => 2 }.fetch(type_for(recruit))
  end

  def signee_json(recruit, previous)
    {
      id: recruit.id,
      name: recruit.name,
      position: recruit.position,
      type: type_for(recruit),
      star_rating: recruit.star_rating,
      class_year: recruit.class_year.to_s[/\(([^)]+)\)/, 1] || recruit.class_year,
      overall: recruit.transfer ? previous&.overall : recruit.overall,
      from_college: previous&.college_season&.college&.name,
      matched: recruit.transfer ? previous.present? : nil,
      national_rank: recruit.national_rank,
      state: recruit.state,
      nil_amount: recruit.nil_amount
    }
  end
end
