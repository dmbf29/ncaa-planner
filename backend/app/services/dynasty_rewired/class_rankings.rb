module DynastyRewired
  # The national recruiting class rankings (Dynasty Rewired's `top_classes` capture, taken weekly) as the
  # rows Recruiting::CommitService keeps in RecruitingSeason: rank, points, commits and the star counts.
  # The class keeps changing until signing day, so a row that differs from what's saved is an update, not
  # a conflict. nil_spent isn't in the API and is never touched. Schools we have no College for are
  # returned in `unmatched`; a school with no CollegeSeason this season gets one, as the screenshot
  # upload does.
  class ClassRankings
    Result = Struct.new(:stage, :class_year, :finalized, :rows, :unmatched, keyword_init: true)

    def initialize(captures, season:, colleges: CollegeLookup.new)
      @captures = captures
      @season = season
      @colleges = colleges
    end

    def call
      capture = @captures.select { |c| c["dataset"] == "top_classes" && c["classYear"] == @season.year }.max_by { |c| c["capturedAt"].to_i }
      return Result.new(rows: [], unmatched: []) unless capture

      college_seasons = CollegeSeason.where(season: @season).includes(:recruiting_season).index_by(&:college_id)
      result = Result.new(stage: capture.dig("stage", "label"), class_year: capture["classYear"], finalized: capture["finalized"], rows: [], unmatched: [])

      capture["classes"].each do |entry|
        college = @colleges.find(entry["school"])
        next result.unmatched << entry["school"] unless college

        saved = college_seasons[college.id]&.recruiting_season
        attrs = attributes(entry)
        status = saved.nil? ? :new : attributes_of(saved) == attrs ? :same : :changed
        result.rows << { college: college, entry: entry, attrs: attrs, status: status, rank_before: saved&.ranking }
      end
      result
    end

    # Saves the new and changed rows; returns how many were written.
    def self.commit(season, rows)
      writes = rows.reject { |row| row[:status] == :same }
      ActiveRecord::Base.transaction do
        writes.each do |row|
          college_season = CollegeSeason.find_or_create_by!(college: row[:college], season: season)
          (college_season.recruiting_season || college_season.build_recruiting_season).update!(row[:attrs])
        end
      end
      writes.size
    end

    private

    def attributes(entry)
      {
        ranking: entry["rank"], points: entry["points"]&.round(1), total_signed: entry["commits"],
        five_stars: entry["five"], four_stars: entry["four"], three_stars: entry["three"],
        two_stars: entry["two"], one_stars: entry["one"]
      }
    end

    def attributes_of(recruiting_season)
      attributes_keys = %i[ranking points total_signed five_stars four_stars three_stars two_stars one_stars]
      recruiting_season.slice(*attributes_keys).symbolize_keys.tap { |attrs| attrs[:points] = attrs[:points]&.round(1) }
    end
  end
end
