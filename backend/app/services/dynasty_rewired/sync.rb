module DynastyRewired
  # Compares what Dynasty Rewired has for a season with what's saved here (#preview) and saves the
  # parts of that the user ticked (#apply). Nothing is ever overwritten: a score or Top 25 that
  # disagrees with what's saved is reported, and a box score with a player who can't be matched to
  # exactly one roster spot is held back with the names listed, so it can't be half-imported.
  #
  #   results    - final scores for every game of each week, bowls included (the CPU games' only data)
  #   box_scores - team and player stats for games with a box score (user-team games)
  #   rankings   - the Top 25 for the week: media poll before CFP_FIRST_WEEK, the CFP poll from then on
  #   recruiting - the national recruiting class rankings, kept current until the class is finalized
  class Sync
    SECTIONS = %w[results box_scores rankings recruiting].freeze
    CFP_FIRST_WEEK = 10

    def initialize(season, client: Client.new)
      @season = season
      @client = client
    end

    def preview
      {
        league_id: @client.league_id,
        stage: plan[:stage],
        results: results_json,
        box_scores: box_scores_json,
        rankings: rankings_json,
        recruiting: recruiting_json
      }
    end

    # Returns how much of each ticked section was saved; call #preview again for what's left.
    def apply(sections)
      sections = Array(sections).map(&:to_s) & SECTIONS
      saved = {}
      saved[:results] = apply_results if sections.include?("results")
      saved[:box_scores] = apply_box_scores if sections.include?("box_scores")
      saved[:rankings] = apply_rankings if sections.include?("rankings")
      saved[:recruiting] = apply_recruiting if sections.include?("recruiting")
      @plan = nil
      saved
    end

    private

    def plan
      @plan ||= begin
        colleges = CollegeLookup.new
        schedule = @client.schedule(@season.year)
        {
          stage: schedule.dig("currentStage", "label"),
          results: week_results(schedule, colleges),
          box_scores: box_score_plans(@client.box_scores(@season.year), colleges),
          rankings: ranking_plans(@client.rankings(@season.year), colleges),
          recruiting: ClassRankings.new(@client.recruiting(@season.year), season: @season, colleges: colleges).call
        }
      end
    end

    def week_results(schedule, colleges)
      schedule["weeks"].filter_map do |week|
        next unless WeekResults.game_week_number(week["label"])

        WeekResults.new(week, season: @season, colleges: colleges).call
      rescue ActiveRecord::RecordNotFound
        nil # the API has a week this season doesn't
      end
    end

    def box_score_plans(boxes, colleges)
      with_stats = CollegeGameStat.where.not(total_offense: nil).distinct.pluck(:game_id).to_set
      boxes.map do |box|
        mapped = BoxScoreMapper.new(box, season: @season, colleges: colleges).call
        label = "#{box.dig('game', 'awayName')} @ #{box.dig('game', 'homeName')}"
        status, reason =
          if mapped.game.nil? then [ :problem, "No game between these teams in this season's schedule" ]
          elsif with_stats.include?(mapped.game.id) then [ :saved, nil ]
          elsif mapped.unmatched.any? || mapped.ambiguous.any? then [ :attention, "Players that don't match exactly one roster spot" ]
          else [ :new, nil ]
          end
        { box: box, mapped: mapped, label: label, status: status, reason: reason }
      end
    end

    def ranking_plans(rankings, colleges)
      rankings["weeks"].filter_map do |week|
        number = WeekResults.week_number(week.dig("stage", "label")) or next
        poll = number >= CFP_FIRST_WEEK ? "playoff" : "media"
        begin
          result = WeekRankings.new(week, poll: poll, season: @season, colleges: colleges).call
        rescue ArgumentError, ActiveRecord::RecordNotFound => e
          next { week_number: number, poll: poll, status: :unavailable, message: e.message }
        end

        saved = CollegeWeekRanking.where(week: result.week).pluck(:college_id, :ranking).to_h
        incoming = result.rows.to_h { |row| [ row[:college].id, row[:ranking] ] }
        status =
          if result.unmatched.any? || result.rows.size != 25 then :attention
          elsif saved.empty? then :new
          elsif saved == incoming then :saved
          else :differs
          end
        { week_number: number, poll: poll, status: status, result: result }
      end
    end

    def results_json
      weeks = plan[:results].filter_map do |week|
        next if week.new_scores.empty? && week.conflicts.empty? && week.unmatched.empty?

        {
          week_number: week.week_number,
          new_games: week.new_scores.map { |row| row[:game] }.uniq.size,
          conflicts: week.conflicts.map { |row| { game: row[:label], team: row[:college].name, saved: row[:saved], api: row[:score] } },
          unmatched: week.unmatched.map { |game| "#{game['awayName']} @ #{game['homeName']}" }
        }
      end
      { weeks: weeks, new_games: weeks.sum { |week| week[:new_games] } }
    end

    def box_scores_json
      by_status = plan[:box_scores].group_by { |item| item[:status] }
      {
        new: Array(by_status[:new]).map { |item| game_json(item) },
        held: Array(by_status[:attention]).map { |item| game_json(item).merge(reason: item[:reason], players: (item[:mapped].unmatched + item[:mapped].ambiguous).map { |p| "#{p[:name]} (#{p[:team]})" }) } +
              Array(by_status[:problem]).map { |item| { label: item[:label], reason: item[:reason], players: [] } },
        saved: Array(by_status[:saved]).size
      }
    end

    def game_json(item)
      game = item[:mapped].game
      {
        game_id: game.id,
        label: item[:label],
        week_number: game.week.number,
        score: item[:mapped].college_stats.map { |stat| stat[:fields][:final_score] }.join("-"),
        player_lines: item[:mapped].player_stats.count { |row| !GameStats::StatFields.empty_line?(row[:fields]) }
      }
    end

    def rankings_json
      plan[:rankings].map do |item|
        json = item.slice(:week_number, :poll, :status, :message)
        next json unless item[:result]

        json.merge(
          top: item[:result].rows.first(5).map { |row| "#{row[:ranking]}. #{row[:college].name}" },
          unmatched_schools: item[:result].unmatched.map { |row| row["school"] },
          continuity_mismatches: item[:result].continuity_mismatches.size
        )
      end
    end

    def recruiting_json
      result = plan[:recruiting]
      by_status = result.rows.group_by { |row| row[:status] }
      {
        stage: result.stage,
        class_year: result.class_year,
        finalized: result.finalized,
        new: Array(by_status[:new]).size,
        changed: Array(by_status[:changed]).size,
        same: Array(by_status[:same]).size,
        top: result.rows.sort_by { |row| row[:entry]["rank"] }.first(5).map { |row| "#{row[:entry]['rank']}. #{row[:college].name}" },
        unmatched_schools: result.unmatched
      }
    end

    def apply_results
      rows = plan[:results].flat_map(&:new_scores)
      WeekResults.commit(rows)
      rows.map { |row| row[:game] }.uniq.size
    end

    def apply_box_scores
      imports = plan[:box_scores].select { |item| item[:status] == :new }
      imports.each do |item|
        mapped = item[:mapped]
        GameStats::CommitService.new(mapped.game).call(
          box_score_screenshot_signed_ids: [], home_screenshot_signed_ids: [], away_screenshot_signed_ids: [],
          narrative: nil, college_stats: mapped.college_stats, player_stats: mapped.player_stats
        )
      end
      imports.size
    end

    def apply_recruiting
      ClassRankings.commit(@season, plan[:recruiting].rows)
    end

    def apply_rankings
      imports = plan[:rankings].select { |item| item[:status] == :new }
      imports.each { |item| WeekRankings.commit(item[:result].week, item[:result].rows) }
      imports.size
    end
  end
end
