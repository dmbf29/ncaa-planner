# What an episode previews: the next week after the recapped one in which one of our coached teams plays, skipping a
# week where none does (the Army/Navy week has no Big Game Breakdown) and any week an earlier PUBLISHED episode already
# previewed (see previewed_weeks): the hosts shouldn't preview the same game twice. When that next week is part of the
# postseason, the preview covers EVERY postseason week that has one of our games still to preview (CFP first round, the
# other bowls, ...), because a bowl season is one story, not a week-by-week show.
#
# When games remain but were all previewed already, there is nothing to preview, but the episode still wants the
# scoreboard of the hosts' bets on the week just recapped: scoreboard_week is the week whose preview document carries
# that ledger. nil when our teams have no games left at all and there is no next week to grade from.
module Podcast
  class PreviewWeek
    # number is the first week previewed (nil if none), numbers every week previewed, label what it's called on air.
    Result = Struct.new(:number, :numbers, :label, :scoreboard_week, keyword_init: true)

    def self.for(season, week_number, skip_weeks: [])
      upcoming = season.weeks.where("number > ?", week_number).order(:number).to_a.select { |week| ours?(season, week) }
      open_weeks = upcoming.reject { |week| skip_weeks.include?(week.number) }
      first = open_weeks.first
      return scoreboard_only(season, week_number, upcoming) unless first

      covered = first.post_season ? open_weeks.select { |week| week.number >= first.number && week.post_season } : [ first ]
      label = covered.size > 1 ? "Bowl Season" : label(first)
      Result.new(number: first.number, numbers: covered.map(&:number), label: label, scoreboard_week: nil)
    end

    # Nothing left to preview. The scoreboard of last week's bets comes from the next week's preview document: the
    # first upcoming game week if there is one (its games are simply not previewed again), else the very next week.
    def self.scoreboard_only(season, week_number, upcoming)
      week = upcoming.first || season.weeks.find_by(number: week_number + 1)
      week && Result.new(number: nil, numbers: [], label: nil, scoreboard_week: week.number)
    end

    # The week numbers that published episodes of this season already previewed. A manifest entry records them
    # (preview_weeks); entries published before that was recorded get them worked out the same way they were chosen.
    def self.previewed_weeks(season, exclude_key: nil)
      manifest = File.exist?(Publisher::MANIFEST) ? JSON.parse(File.read(Publisher::MANIFEST)) : []
      manifest.flat_map do |entry|
        next [] if entry["key"] == exclude_key
        next Array(entry["preview_weeks"]) if entry.key?("preview_weeks")

        match = entry["key"].to_s.match(/-#{season.year}-week-(\d+)\z/)
        match ? Array(self.for(season, match[1].to_i)&.numbers) : []
      end.uniq
    end

    # Does a coached team play in this week?
    def self.ours?(season, week)
      coached = coached_ids(season)
      return false if coached.empty?

      Game.where(week_id: week.id).where("home_college_id IN (:ids) OR away_college_id IN (:ids)", ids: coached).exists?
    end

    def self.coached_ids(season)
      season.college_seasons.where.not(coach_id: nil).pluck(:college_id)
    end

    def self.label(week)
      return "Conference Championship" if week.conference_championship
      return week.name.presence || "Postseason" if week.post_season

      "Week #{week.number}"
    end
  end
end
