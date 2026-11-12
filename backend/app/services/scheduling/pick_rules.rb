module Scheduling
  # A coached team's non-conference scheduling rules, evaluated against everything already booked this season:
  #
  # * a pick must be an open week (not a bye or a fixed game) and one of that week's registered possible opponents;
  # * a team can't be on one schedule twice, or play two games in a week;
  # * a team another coach already has can only be added in a LATER week than that coach's earliest one, with a
  #   warning naming them (so the coach who chose first gets the team first);
  # * picking another coach's team makes one shared game, shown on both schedules (see SchedulePick);
  # * to confirm: every open week filled, and at least 1 non-conference road game (2 for the reigning champion).
  class PickRules
    Error = Class.new(StandardError)

    def initialize(college_season)
      @cs = college_season
      @season = college_season.season
      load_season_data
    end

    attr_reader :cs

    # { status: :ok | :warning | :blocked, reasons: [...] }
    def evaluate(week, opponent_id)
      return blocked("Week #{week.number} isn't open.") unless open_week?(week)
      return blocked("That's your own team.") if opponent_id == @cs.college_id
      return blocked("Not one of the possible opponents for this week.") unless option?(week, opponent_id)

      repeat = own_other_week(week, opponent_id)
      return blocked("Already on your schedule in Week #{repeat}.") if repeat

      plays = plays_in_week(opponent_id, week.id)
      return blocked("Already plays #{plays} in Week #{week.number}.") if plays

      shared = blocked_by_coached_team(week, opponent_id)
      return shared if shared

      bookings = bookings_of(opponent_id)
      return { status: :ok, reasons: [] } if bookings.empty?

      earliest = bookings.min_by { |booking| booking[:week_number] }
      if week.number <= earliest[:week_number]
        return blocked("#{earliest[:coach]} has them in Week #{earliest[:week_number]} — you can only add them after that week.")
      end

      { status: :warning, reasons: bookings.sort_by { |b| b[:week_number] }.map { |b| "Already on #{b[:coach]}'s schedule (Week #{b[:week_number]})." } }
    end

    def set_pick!(week, opponent_id, is_away)
      existing = pick_for(week)
      raise Error, "That game was set by #{mirror_owner(existing)} — only they can change it." if existing&.mirrored?

      if existing && existing.opponent_college_id == opponent_id
        update_away!(existing, is_away)
        return existing
      end

      result = evaluate(week, opponent_id)
      raise Error, result[:reasons].first if result[:status] == :blocked

      ActiveRecord::Base.transaction do
        remove_pick!(week) if existing
        pick = @cs.schedule_picks.create!(week: week, opponent_college_id: opponent_id, is_away: is_away)
        create_mirror!(pick) if (other = coached_by_college[opponent_id])
        other&.update!(schedule_confirmed_at: nil)
        @cs.update!(schedule_confirmed_at: nil)
        pick
      end
    end

    def remove_pick!(week)
      pick = pick_for(week)
      return unless pick
      raise Error, "That game was set by #{mirror_owner(pick)} — only they can change it." if pick.mirrored?

      ActiveRecord::Base.transaction do
        coached_by_college[pick.opponent_college_id]&.update!(schedule_confirmed_at: nil)
        pick.destroy!
        @cs.update!(schedule_confirmed_at: nil)
      end
    end

    def road_count
      locked_away = locked_games.count { |game| game.away_college_id == @cs.college_id && non_conference?(game.home_college_id) }
      picked_away = picks.count { |pick| pick.is_away && non_conference?(pick.opponent_college_id) }
      locked_away + picked_away
    end

    def road_required = Rules.road_games_required(@cs)

    def open_weeks
      @open_weeks ||= @weeks.select { |week| open_week?(week) }
    end

    def missing_weeks
      open_weeks.reject { |week| pick_for(week) }
    end

    def confirmable_problems
      problems = []
      problems << "Pick an opponent for week#{'s' if missing_weeks.size > 1} #{missing_weeks.map(&:number).join(', ')}." if missing_weeks.any?
      problems << "You need at least #{road_required} non-conference road game#{'s' if road_required > 1} (you have #{road_count})." if road_count < road_required
      problems
    end

    # Makes the picks real: a Game per pick (and the commissioner's byes), then marks the schedule confirmed.
    def confirm!
      problems = confirmable_problems
      raise Error, problems.join(" ") if problems.any?

      rows = picks.map { |pick| { week_id: pick.week_id, opponent_college_id: pick.opponent_college_id, is_away: pick.is_away, week_label: weeks_by_id[pick.week_id].number.to_s } }
      rows += @weeks.select { |week| @season.schedule_bye_week_numbers.include?(week.number) }.map { |week| { week_id: week.id, is_bye: true, week_label: week.number.to_s } }
      warnings = TeamSchedule::CommitService.new(@cs).call({}, rows)
      raise Error, warnings.map { |w| "Week #{w[:week_label]}: #{w[:error]}" }.join(" ") if warnings.any?

      @cs.update!(schedule_confirmed_at: Time.current)
    end

    def pick_for(week) = picks.find { |pick| pick.week_id == week.id }

    def picks
      @picks.select { |pick| pick.college_season_id == @cs.id }
    end

    private

    def load_season_data
      @weeks = @season.weeks.where(number: Rules::WEEK_NUMBERS).order(:number).to_a
      @weeks_by_id = @weeks.index_by(&:id)
      @games = Game.where(week_id: @weeks_by_id.keys).to_a
      @picks = SchedulePick.joins(:college_season).where(college_seasons: { season_id: @season.id }).to_a
      @options = ScheduleOption.where(college_season_id: @cs.id).to_a
      season_college_seasons = @season.college_seasons.includes(:coach).to_a
      @coached_by_college = season_college_seasons.select(&:coach_id).index_by(&:college_id)
      @coached_by_id = @coached_by_college.values.index_by(&:id)
      @conference_by_college = season_college_seasons.to_h { |college_season| [ college_season.college_id, college_season.conference ] }
      @college_names = College.pluck(:id, :name).to_h
    end

    attr_reader :weeks_by_id, :coached_by_college

    def open_week?(week)
      Rules::WEEK_NUMBERS.cover?(week.number) && !@season.schedule_bye_week_numbers.include?(week.number) && !@cs.schedule_locked_week_ids.include?(week.id)
    end

    def option?(week, opponent_id)
      @options.any? { |option| option.week_id == week.id && option.opponent_college_id == opponent_id }
    end

    def locked_games
      @locked_games ||= @games.select { |game| @cs.schedule_locked_week_ids.include?(game.week_id) && involves?(game, @cs.college_id) }
    end

    def involves?(game, college_id) = game.home_college_id == college_id || game.away_college_id == college_id

    def own_other_week(week, opponent_id)
      other = picks.find { |pick| pick.opponent_college_id == opponent_id && pick.week_id != week.id }
      return weeks_by_id[other.week_id].number if other

      game = locked_games.find { |g| involves?(g, opponent_id) }
      game && weeks_by_id[game.week_id].number
    end

    def plays_in_week(opponent_id, week_id)
      game = @games.find { |g| g.week_id == week_id && involves?(g, opponent_id) && !involves?(g, @cs.college_id) }
      return nil unless game

      @college_names[game.home_college_id == opponent_id ? game.away_college_id : game.home_college_id]
    end

    # When the opponent is another coach's team, that team must have the week free for the shared game.
    def blocked_by_coached_team(week, opponent_id)
      other = coached_by_college[opponent_id]
      return nil unless other

      if other.schedule_locked_week_ids.include?(week.id)
        return blocked("#{other.coach.name} has a fixed game in Week #{week.number}.")
      end

      taken = @picks.find { |pick| pick.college_season_id == other.id && pick.week_id == week.id }
      blocked("#{other.coach.name} already has #{@college_names[taken.opponent_college_id]} in Week #{week.number}.") if taken
    end

    # Other coaches' games and picks against this team (not counting the shared game with this coach).
    def bookings_of(opponent_id)
      from_games = @games.filter_map do |game|
        next unless involves?(game, opponent_id)

        other_id = game.home_college_id == opponent_id ? game.away_college_id : game.home_college_id
        other = coached_by_college[other_id]
        { week_number: weeks_by_id[game.week_id].number, coach: other.coach.name, college_season_id: other.id } if other && other.id != @cs.id
      end
      from_picks = @picks.filter_map do |pick|
        next unless pick.opponent_college_id == opponent_id && pick.college_season_id != @cs.id

        other = @coached_by_id[pick.college_season_id]
        { week_number: weeks_by_id[pick.week_id].number, coach: other.coach.name, college_season_id: other.id } if other
      end
      (from_games + from_picks).uniq { |booking| [ booking[:week_number], booking[:college_season_id] ] }
    end

    def create_mirror!(pick)
      other = coached_by_college[pick.opponent_college_id]
      other.schedule_picks.create!(week_id: pick.week_id, opponent_college_id: @cs.college_id, is_away: !pick.is_away, mirrored_from: pick)
    end

    def update_away!(pick, is_away)
      pick.update!(is_away: is_away)
      pick.mirror&.update!(is_away: !is_away)
      @cs.update!(schedule_confirmed_at: nil)
    end

    def mirror_owner(pick)
      @coached_by_id[SchedulePick.find(pick.mirrored_from_id).college_season_id]&.coach&.name || "the other coach"
    end

    def non_conference?(opponent_id)
      @conference_by_college[opponent_id] != @cs.conference
    end

    def blocked(reason) = { status: :blocked, reasons: [ reason ] }
  end
end
