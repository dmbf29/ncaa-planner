# Every college — and every conference those colleges have played in — that
# has appeared in this dynasty (any season), for the player-stats scope
# picker. Coached colleges are called out separately (alphabetical), then
# everyone else (alphabetical), so a user's own teams are easy to find in a
# league-wide list. Conferences are every distinct conference name any
# CollegeSeason in this dynasty has carried, since membership can change
# season to season.
class DynastyTeamsSerializer
  def initialize(dynasty)
    @dynasty = dynasty
  end

  def as_json
    {
      teams: coached_colleges.map { |c| team_json(c, coached: true) } +
        other_colleges.map { |c| team_json(c, coached: false) },
      conferences: conferences
    }
  end

  private

  def college_seasons
    @college_seasons ||= CollegeSeason.joins(:season).where(seasons: { dynasty_id: @dynasty.id })
  end

  def conferences
    @conferences ||= college_seasons.where.not(conference: [ nil, "" ]).distinct.order(:conference).pluck(:conference)
  end

  def coached_college_ids
    @coached_college_ids ||= college_seasons.where.not(coach_id: nil).distinct.pluck(:college_id)
  end

  def all_colleges
    @all_colleges ||= College.where(id: college_seasons.distinct.select(:college_id)).order(:name)
  end

  def coached_colleges
    all_colleges.select { |college| coached_college_ids.include?(college.id) }
  end

  def other_colleges
    all_colleges.reject { |college| coached_college_ids.include?(college.id) }
  end

  def team_json(college, coached:)
    { id: college.id, name: college.name, coached: coached }
  end
end
