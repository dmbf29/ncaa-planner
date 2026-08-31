module RosterImport
  # Read-only pass over a pasted roster snapshot: classifies each row via
  # Matcher without persisting anything, so the frontend can show a review
  # screen (match / new / needs review) before anything is committed.
  class Analyzer
    def initialize(college_season)
      @matcher = Matcher.new(college_season)
    end

    def call(players)
      Array(players).map { |row| analyze_row(row.deep_symbolize_keys) }
    end

    private

    def analyze_row(row)
      row[:class_year] = Matcher.normalize_class_year(row[:class_year])
      row.merge(@matcher.resolve(row))
    end
  end
end
