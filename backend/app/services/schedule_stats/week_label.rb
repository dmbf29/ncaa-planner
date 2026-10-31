module ScheduleStats
  # Maps the header text on a Scores/Schedules screen ("WEEK 5" / "BOWL WEEK 1" / "CONFERENCE CHAMPIONSHIP") to the
  # season's real Week record. Regular weeks are number 0-14, bowl weeks are number 16-19 with a "Bowl Week N" name
  # (see Season#create_weeks), so a plain "WEEK N" is only matched against a regular-season week and can never
  # resolve to the same row a "BOWL WEEK N" header would.
  module WeekLabel
    def self.resolve(season, raw_label)
      return nil if season.nil? || raw_label.blank?

      normalized = raw_label.strip
      return season.weeks.find_by(conference_championship: true) if normalized.match?(/conf(erence)?\s*champ/i)

      bowl_match = normalized.match(/bowl\s*week\s*(\d+)/i)
      return season.weeks.find_by(name: "Bowl Week #{bowl_match[1]}") if bowl_match

      number_match = normalized.match(/\d+/)
      return nil unless number_match

      season.weeks.find_by(number: number_match[0].to_i, post_season: false, conference_championship: false)
    end
  end
end
