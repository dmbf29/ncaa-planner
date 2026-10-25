# What an episode previews: the games after the recapped week that one of our coached teams plays in or (in the
# postseason) that are College Football Playoff games, since the hosts bet on every CFP game. The week it starts
# from is the next week with any such game still to preview, skipping a week where there is none (the Army/Navy
# week has no Big Game Breakdown). Games an earlier PUBLISHED episode already previewed are left out (see
# previewed_game_ids): the hosts shouldn't preview the same game twice, but a game added to the schedule later (a
# quarterfinal in a bowl week whose other game was already covered) is still new. When the first week is part of
# the postseason, the preview covers EVERY postseason week with a game still to preview (CFP rounds, the other
# bowls of ours), because a bowl season is one story, not a week-by-week show.
#
# When games remain but were all previewed already, there is nothing to preview, but the episode still wants the
# scoreboard of the hosts' bets on the week just recapped: scoreboard_week is the week whose preview document carries
# that ledger. nil when there are no games left at all and no next week to grade from.
module Podcast
  class PreviewWeek
    # number is the first week previewed (nil if none), numbers every week previewed, label what it's called on air,
    # postseason whether those are bowl / CFP weeks (no standings or poll talk).
    Result = Struct.new(:number, :numbers, :label, :scoreboard_week, :postseason, keyword_init: true)

    def self.for(season, week_number, skip_game_ids: [])
      upcoming = season.weeks.where("number > ?", week_number).order(:number).to_a
                       .select { |week| relevant_game_ids(season, week).any? }
      open_weeks = upcoming.select { |week| (relevant_game_ids(season, week) - skip_game_ids).any? }
      first = open_weeks.first
      return scoreboard_only(season, week_number, upcoming) unless first

      covered = first.post_season ? open_weeks.select { |week| week.number >= first.number && week.post_season } : [ first ]
      label = covered.size > 1 ? "Bowl Season" : label(first)
      Result.new(number: first.number, numbers: covered.map(&:number), label: label, scoreboard_week: nil, postseason: first.post_season)
    end

    # Nothing left to preview. The scoreboard of last week's bets comes from the next week's preview document: the
    # first upcoming game week if there is one (its games are simply not previewed again), else the very next week.
    def self.scoreboard_only(season, week_number, upcoming)
      week = upcoming.first || season.weeks.find_by(number: week_number + 1)
      week && Result.new(number: nil, numbers: [], label: nil, scoreboard_week: week.number, postseason: nil)
    end

    # The ids of the games that published episodes of this season already previewed. A manifest entry records them
    # (previewed_game_ids). Entries published before that was recorded get them worked out: the games in the weeks it
    # previewed that had bets locked by the time it was published (the bets are created when an episode previews a game).
    def self.previewed_game_ids(season, exclude_key: nil)
      manifest = File.exist?(Publisher::MANIFEST) ? JSON.parse(File.read(Publisher::MANIFEST)) : []
      manifest.flat_map do |entry|
        next [] if entry["key"] == exclude_key
        next Array(entry["previewed_game_ids"]) if entry.key?("previewed_game_ids")

        match = entry["key"].to_s.match(/-#{season.year}-week-(\d+)\z/)
        match ? legacy_previewed_game_ids(season, entry, match[1].to_i) : []
      end.uniq
    end

    def self.legacy_previewed_game_ids(season, entry, week_number)
      weeks = Array(self.for(season, week_number)&.numbers)
      ids = season.weeks.where(number: weeks).flat_map { |week| relevant_game_ids(season, week) }
      published = Time.iso8601(entry["published_at"])
      GamePick.where(game_id: ids).where("created_at <= ?", published).distinct.pluck(:game_id)
    end

    # The games in a week worth a preview: ones our coached teams play in, plus (postseason weeks) every CFP game.
    def self.relevant_game_ids(season, week)
      coached = coached_ids(season)
      games = Game.where(week_id: week.id)
      ours = coached.empty? ? Game.none : games.where("home_college_id IN (:ids) OR away_college_id IN (:ids)", ids: coached)
      cfp = week.post_season ? games.where.not(cfp_round: nil) : Game.none
      (ours.pluck(:id) + cfp.pluck(:id)).uniq
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
