# Full All-American list for a season — every honoree, not just ones tied
# to coached teams, since these are league-wide honors. Split into the
# national team and each conference's team, tier 1/2 within each.
class SeasonAllAmericansSerializer
  POSITION_ORDER = %w[
    QB HB WR TE LT LG C RG RT LE RE DT LOLB MLB ROLB CB FS SS K P
  ].freeze

  def initialize(season)
    @season = season
  end

  def as_json
    {
      season: { id: @season.id, year: @season.year },
      national: tiered(all_americans.select(&:national)),
      conferences: conference_names.map { |conference| conference_json(conference) }
    }
  end

  private

  def all_americans
    @all_americans ||= AllAmerican.where(student_season: StudentSeason.where(college_season: @season.college_seasons))
                                   .includes(student_season: [ :student, { college_season: :college } ])
                                   .to_a
  end

  # Only conferences that actually have an honoree — an empty section per
  # conference (there are ~11) would just be noise on the page.
  def conference_names
    all_americans.reject(&:national).filter_map(&:conference).uniq.sort
  end

  def coached_college_ids
    @coached_college_ids ||= @season.college_seasons.where.not(coach_id: nil).pluck(:college_id).to_set
  end

  def conference_json(conference)
    honorees = all_americans.select { |aa| !aa.national && aa.conference == conference }
    { conference: conference, tiers: tiered(honorees) }
  end

  def tiered(honorees)
    AllAmerican::TIERS.index_with do |tier|
      honorees.select { |aa| aa.tier == tier }
              .sort_by { |aa| [ position_rank(aa.student_season.position), aa.student_season.student.name ] }
              .map { |aa| honoree_json(aa) }
    end
  end

  # Unrecognized positions sort after every known one rather than raising,
  # so a data-entry typo doesn't break the whole list.
  def position_rank(position)
    rank = POSITION_ORDER.index(position)
    rank || POSITION_ORDER.length
  end

  def honoree_json(all_american)
    student_season = all_american.student_season
    college = student_season.college_season.college
    {
      id: all_american.id,
      name: student_season.student.name,
      position: student_season.position,
      class_year: student_season.class_year,
      overall: student_season.overall,
      college: { id: college.id, name: college.name },
      coached_by_us: coached_college_ids.include?(college.id),
      preseason: all_american.preseason
    }
  end
end
