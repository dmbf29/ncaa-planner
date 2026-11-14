module DynastyRewired
  # One poll from the rankings dataset as CollegeWeekRanking rows. The table holds a single Top 25 per
  # week with no poll type, so the caller picks which poll that is ("media", "coaches" or "playoff").
  # A poll's `previousRank` column is the same poll one week earlier, which is how week-to-week
  # continuity with the rankings already saved can be checked before importing.
  class WeekRankings
    Result = Struct.new(:week, :rows, :unmatched, :continuity_mismatches, keyword_init: true)

    def initialize(rankings_week, poll:, season:, colleges: CollegeLookup.new)
      @rankings_week = rankings_week
      @poll_name = poll
      @season = season
      @colleges = colleges
    end

    def call
      number = WeekResults.week_number(@rankings_week.dig("stage", "label")) or raise ArgumentError, "#{@rankings_week.dig('stage', 'label')} isn't a regular-season week"
      week = @season.weeks.find_by!(number: number)
      poll = @rankings_week["polls"].find { |p| p["poll"] == @poll_name }
      raise ArgumentError, "no #{@poll_name} poll for Week #{number} yet" unless poll && poll["state"] == "available"

      result = Result.new(week: week, rows: [], unmatched: [], continuity_mismatches: [])
      poll["rows"].each do |row|
        college = @colleges.find(row["school"])
        next result.unmatched << row unless college

        result.rows << { college: college, ranking: row["rank"], school: row["school"], previous_rank: row["previousRank"] }
      end
      result.continuity_mismatches = continuity_mismatches(week, result.rows)
      result
    end

    def self.commit(week, rows)
      ActiveRecord::Base.transaction do
        CollegeWeekRanking.where(week: week).delete_all
        rows.each { |row| CollegeWeekRanking.create!(week: week, college: row[:college], ranking: row[:ranking]) }
      end
    end

    private

    def continuity_mismatches(week, rows)
      earlier = @season.weeks.find_by(number: week.number - 1)
      saved = CollegeWeekRanking.where(week: earlier).index_by(&:ranking)
      rows.select { |row| row[:previous_rank] && saved[row[:previous_rank]]&.college_id != row[:college].id }
    end
  end
end
