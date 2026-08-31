# Everything the Award Winners page needs: the full award catalog (with the
# winner already recorded for this season, if any), the season's teams that
# have a roster to pick from, and the dynasty's existing coaches. Player
# rosters themselves are fetched per-team on demand by the page, not bundled
# here — 100+ teams x 85 players is too much to ship up front.
class SeasonAwardWinnersSerializer
  def initialize(season)
    @season = season
  end

  def as_json
    {
      awards: awards_json,
      teams: teams_json,
      coaches: coaches_json
    }
  end

  private

  def season_awards_by_award_id
    @season_awards_by_award_id ||= @season.season_awards
                                          .includes(:coach, student_season: [ :student, { college_season: :college } ])
                                          .index_by(&:award_id)
  end

  def awards_json
    Award.ordered.map do |award|
      {
        id: award.id,
        name: award.name,
        description: award.description,
        recipient_type: award.recipient_type,
        winner: winner_json(season_awards_by_award_id[award.id])
      }
    end
  end

  def winner_json(season_award)
    return nil if season_award.nil?

    if (student_season = season_award.student_season)
      {
        type: "player",
        student_season_id: student_season.id,
        college_season_id: student_season.college_season_id,
        name: student_season.student.name,
        position: student_season.position,
        class_year: student_season.class_year,
        overall: student_season.overall,
        stat_line: season_award.stat_line,
        college: {
          id: student_season.college_season.college.id,
          name: student_season.college_season.college.name
        }
      }
    elsif (coach = season_award.coach)
      { type: "coach", coach_id: coach.id, name: coach.name, stat_line: season_award.stat_line }
    end
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def teams_json
    @season.college_seasons
           .joins(:student_seasons)
           .distinct
           .includes(:college)
           .sort_by { |cs| [ coached_college_ids.include?(cs.college_id) ? 0 : 1, cs.college.name ] }
           .map do |college_season|
      {
        college_season_id: college_season.id,
        name: college_season.college.name,
        coached: coached_college_ids.include?(college_season.college_id)
      }
    end
  end

  def coaches_json
    @season.dynasty.coaches.order(:name).map { |coach| { id: coach.id, name: coach.name } }
  end
end
