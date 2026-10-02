module RosterImport
  # Links a roster player who has no record last season to the Student they
  # actually were last season, so season-over-season comparisons (progression,
  # "transferred from X") can find them.
  #
  # Why it's needed: the roster import checks THIS season's roster first and,
  # on a name hit, treats the row as a refresh of that player without ever
  # looking at last season. A player created earlier this season by another
  # upload (the All-Americans upload creates players that aren't on a roster
  # yet) is therefore a brand-new Student with no history even though they were
  # on a roster last year.
  #
  # Deliberately conservative, since a wrong link would hand one player's
  # history to another. A link needs ALL of:
  #  - the same full first and last name as exactly one previous-season player
  #    (or, when several share the name, exactly one of them being a transfer
  #    this college signed last cycle — the signing carries the right Student);
  #  - a class year that is a legal step on from theirs last year;
  #  - the same side of the ball (offense/defense) and an overall within
  #    MAX_OVERALL_JUMP of last year's;
  #  - the previous Student not already on a roster this season.
  # Anything else is reported as skipped, never guessed.
  #
  # A freshman never has history, so true freshmen are left alone.
  class HistoryLinker
    MAX_OVERALL_JUMP = 15

    Link = Struct.new(:student_season, :from_student, :to_student, :previous, :reason, keyword_init: true)
    Skip = Struct.new(:student_season, :candidates, :reason, keyword_init: true)

    def self.for_season(season)
      season.college_seasons.map { |college_season| new(college_season) }
    end

    def initialize(college_season)
      @college_season = college_season
      @season = college_season.season
      @previous_season = @season.previous_season
    end

    # Returns { links: [Link], skipped: [Skip] } without changing anything.
    def plan
      return { links: [], skipped: [] } unless @previous_season

      links = []
      skipped = []
      unlinked_student_seasons.each do |student_season|
        candidates = candidates_for(student_season)
        next if candidates.empty?

        link = resolve(student_season, candidates)
        link ? links << link : skipped << Skip.new(student_season: student_season, candidates: candidates, reason: "several players share this name")
      end
      { links: links, skipped: skipped }
    end

    # Applies the plan; returns the links that were made.
    def call
      plan[:links].each { |link| apply(link) }
    end

    private

    def apply(link)
      ActiveRecord::Base.transaction do
        orphan = link.from_student
        link.student_season.update!(student_id: link.to_student.id)
        SignedRecruit.where(student_id: orphan.id).update_all(student_id: link.to_student.id)
        orphan.destroy! if orphan.student_seasons.none? && SignedRecruit.where(student_id: orphan.id).none?
      end
    end

    def unlinked_student_seasons
      @college_season.student_seasons.includes(:student).reject do |student_season|
        student_season.class_year == "FR" || previous_student_ids.include?(student_season.student_id)
      end
    end

    def previous_student_seasons
      @previous_student_seasons ||= StudentSeason.where(college_season_id: @previous_season.college_seasons.select(:id))
                                                 .preload(:student, college_season: :college).to_a
    end

    def previous_student_ids
      @previous_student_ids ||= previous_student_seasons.to_set(&:student_id)
    end

    # Previous-season Students who already have a roster spot this season.
    def claimed_student_ids
      @claimed_student_ids ||= StudentSeason.where(college_season_id: @season.college_seasons.select(:id)).pluck(:student_id).to_set
    end

    def previous_by_name
      @previous_by_name ||= previous_student_seasons.group_by { |ss| name_key(ss.student) }
    end

    def candidates_for(student_season)
      Array(previous_by_name[name_key(student_season.student)]).select do |previous|
        !claimed_student_ids.include?(previous.student_id) &&
          plausible_step?(student_season, previous)
      end
    end

    def resolve(student_season, candidates)
      if candidates.size == 1
        return build_link(student_season, candidates.first, "only player with this name and a matching progression")
      end

      signed = signed_transfer_student_ids
      narrowed = candidates.select { |previous| signed.include?(previous.student_id) }
      build_link(student_season, narrowed.first, "the only candidate this college signed as a transfer") if narrowed.size == 1
    end

    def build_link(student_season, previous, reason)
      Link.new(student_season: student_season, from_student: student_season.student, to_student: previous.student, previous: previous, reason: reason)
    end

    def signed_transfer_student_ids
      @signed_transfer_student_ids ||= begin
        previous_college_season = @previous_season.college_seasons.find_by(college_id: @college_season.college_id)
        previous_college_season ? previous_college_season.signed_recruits.where(transfer: true).where.not(student_id: nil).pluck(:student_id).to_set : Set.new
      end
    end

    def plausible_step?(student_season, previous)
      RosterImport::Matcher::CLASS_YEAR_PREDECESSORS.fetch(student_season.class_year, []).include?(previous.class_year) &&
        same_side?(student_season.position, previous.position) &&
        overall_close?(student_season.overall, previous.overall)
    end

    def same_side?(position, previous_position)
      squad = squad_of(position)
      previous_squad = squad_of(previous_position)
      squad.nil? || previous_squad.nil? || squad == previous_squad
    end

    def squad_of(position)
      PositionBoardMapping.resolve(PositionBoardMapping.canonical(position))&.dig(:squad)
    end

    def overall_close?(overall, previous_overall)
      overall.nil? || previous_overall.nil? || (overall - previous_overall).abs <= MAX_OVERALL_JUMP
    end

    def name_key(student)
      [ student.first_name.to_s.strip.downcase, student.last_name.to_s.strip.downcase ]
    end
  end
end
