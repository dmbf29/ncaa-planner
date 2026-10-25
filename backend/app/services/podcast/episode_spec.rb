# Which episode the Export page is working on: the weekly recap + preview of a given week, or one of the season-long
# shows (win totals, roster breakdown, report cards, portal preview, signing day). Everything that differs between them
# lives here: the slug used in URLs and folder names, the feed key, the title, how long the show runs, the source
# markdown, and what the cover art should say. EpisodeRun, EpisodeStatus and the controller all take a spec.
module Podcast
  class EpisodeSpec
    # kind => title, art headline, target minutes, the serializer/presenter that builds its source markdown, and any
    # per-show rules carried over from the old NotebookLM prompts (the markdown's own producer notes cover the rest).
    SHOWS = {
      "win_totals" => {
        title: ->(year) { "#{year} Preseason Win Totals - Vegas Over/Under" },
        headline: ->(year) { "#{year} WIN TOTALS: OVER/UNDER" },
        minutes: 22, serializer: "WinTotalsSerializer", presenter: "WinTotalsMarkdownPresenter",
        art_facts: "each team's name and its Vegas win total (for example \"OVER/UNDER 7.5\")",
        art_reference: "*win_totals*",
        rules: <<~TEXT
          For each team: read the full schedule game by game in the document's order. LIKELY WIN and LIKELY LOSS games get a
          quick line and move on. Every COIN FLIP stops for a real debate where one host argues win and the other argues
          loss, citing something concrete, alternating who takes which side. Then both hosts give their over/under call on
          the Vegas line, then the Hot Seat Check on the head coach using the thermometer reading (never the percentage).
        TEXT
      },
      "roster_breakdown" => {
        title: ->(year) { "#{year} Spring Practice: Who's Built to Win in the Sun Belt?" },
        headline: ->(year) { "#{year} ROSTER BREAKDOWN" },
        minutes: 22, serializer: "TeamBreakdownSerializer", presenter: "TeamBreakdownMarkdownPresenter",
        art_facts: "each team's name",
        art_reference: "*Spring Practice*", rules: ""
      },
      "midseason_report_cards" => {
        title: ->(year) { "#{year} Midseason Report Cards" },
        headline: ->(year) { "#{year} MIDSEASON REPORT CARDS" },
        minutes: 16, serializer: "MidseasonReportCardSerializer", presenter: "MidseasonReportCardMarkdownPresenter",
        art_facts: "each team's name and its record so far (the record only: no over/under or other numbers)",
        art_reference: "*Midseason*",
        rules: <<~TEXT
          In every team's segment Arlis and Ty must each state their OWN letter grade (A+ through F) out loud, with real
          reasoning. They don't have to agree; a split grade is good radio. Arlis grades on the eye test and the
          storyline, Ty on the scoreboard and the pace. Treat a team coming off a bye as having fewer games on the board.
          Talk about the preseason number in plain studio language ("on pace", "ahead of schedule"), never "probability",
          "model" or "algorithm".
        TEXT
      },
      "end_of_season_report_cards" => {
        title: ->(year) { "#{year} End of Season Report Cards" },
        headline: ->(year) { "#{year} END OF SEASON REPORT CARDS" },
        minutes: 20, serializer: "EndOfSeasonReportCardSerializer", presenter: "EndOfSeasonReportCardMarkdownPresenter",
        art_facts: "each team's name and its final record (the record only: no over/under or other numbers)",
        art_reference: "*Midseason*",
        rules: <<~TEXT
          In every team's segment Arlis and Ty must each state their OWN letter grade (A+ through F) out loud, with real
          reasoning; a split grade is good radio. Talk about the preseason number in plain studio language, never
          "probability", "model" or "algorithm".
        TEXT
      },
      "portal_preview" => {
        title: ->(year) { "#{year} Portal Preview: Who's Leaving & Staying?" },
        headline: ->(year) { "#{year} PORTAL PREVIEW" },
        minutes: 22, serializer: "PortalPreviewSerializer", presenter: "PortalPreviewMarkdownPresenter",
        art_facts: "each team's name", art_reference: nil, rules: ""
      },
      "nsd_breakdown" => {
        title: ->(year) { "#{year} National Signing Day Special" },
        headline: ->(year) { "#{year} NATIONAL SIGNING DAY" },
        minutes: 20, serializer: "NsdBreakdownSerializer", presenter: "NsdBreakdownMarkdownPresenter",
        art_facts: "each team's name and its signing class rank if the document gives one",
        art_reference: "*Signing Day*", rules: ""
      }
    }.freeze

    KINDS = ([ "weekly" ] + SHOWS.keys).freeze

    # Returns nil for a slug that isn't an episode ("week-11" or one of SHOWS' keys). Pass the season so a weekly
    # episode previews the next week our teams actually play (see PreviewWeek) instead of blindly week + 1.
    def self.for(year:, slug:, season: nil)
      slug = slug.to_s
      if (match = slug.match(/\Aweek-(\d+)\z/))
        week = match[1].to_i
        key = "rising-in-the-sun-belt-#{year}-week-#{week}"
        previewed = season ? PreviewWeek.previewed_game_ids(season, exclude_key: key) : []
        preview = if season
          PreviewWeek.for(season, week, skip_game_ids: previewed)
        else
          PreviewWeek::Result.new(number: week + 1, numbers: [ week + 1 ], label: "Week #{week + 1}")
        end
        record = season&.weeks&.find_by(number: week)
        new(year: year, kind: "weekly", week: week, recap_label: (PreviewWeek.label(record) if record),
            recap_postseason: record&.post_season, preview_week: preview&.number, preview_weeks: preview&.numbers,
            preview_label: preview&.label, preview_postseason: preview&.postseason, scoreboard_week: preview&.scoreboard_week,
            previewed_game_ids: previewed, champion: champion_of(record))
      elsif SHOWS.key?(slug)
        new(year: year, kind: slug)
      end
    end

    attr_reader :year, :kind, :week, :preview_week, :preview_weeks, :preview_label, :scoreboard_week, :recap_postseason,
                :preview_postseason, :previewed_game_ids, :champion

    def initialize(year:, kind:, week: nil, recap_label: nil, recap_postseason: nil, preview_week: nil, preview_weeks: nil, preview_label: nil,
                   preview_postseason: nil, scoreboard_week: nil, previewed_game_ids: [], champion: nil)
      @year = year.to_i
      @kind = kind
      @week = week
      @recap_label = recap_label
      @preview_week = preview_week
      @preview_weeks = preview_weeks || (Array(preview_week) if preview_week)
      @preview_label = preview_label
      @scoreboard_week = scoreboard_week
      @recap_postseason = recap_postseason
      @preview_postseason = preview_postseason
      @previewed_game_ids = previewed_game_ids
      @champion = champion
    end

    # Nothing new to preview (it was all previewed already), but the hosts' bets still get graded.
    def scoreboard_only? = weekly? && preview_week.nil? && scoreboard_week.present?

    # What the recapped week is called: "Week 13", "Conference Championship", "Bowl Week 1".
    def recap_label = @recap_label.presence || "Week #{week}"

    # Who won the national championship, when the recapped week is the one it was played in and it has been played.
    def self.champion_of(record)
      return nil unless record&.post_season

      final = Game.where(week_id: record.id, cfp_round: "championship").includes(:college_game_stats, :home_college, :away_college).first
      return nil unless final

      scores = final.college_game_stats.index_by(&:college_id)
      home = scores[final.home_college_id]&.final_score
      away = scores[final.away_college_id]&.final_score
      return nil unless home && away && home != away

      (home > away ? final.home_college : final.away_college).name
    end

    # The national championship episode: the title game and the champion's road to it, with a champion cover.
    def championship? = weekly? && champion.present?

    def weekly? = kind == "weekly"

    def slug = weekly? ? "week-#{week}" : kind

    def show = SHOWS.fetch(kind)

    def dir = File.join(Show::ROOT, "episodes", "#{year}_#{slug}")

    # The feed guid. Weekly keeps the keys already published ("...-2027-week-11").
    def key = "rising-in-the-sun-belt-#{year}-#{slug.tr('_', '-')}"

    def art_path
      name = weekly? ? format("%<y>d_%<w>02d_episode.png", y: year, w: week) : "#{year}_#{kind}_episode.png"
      File.join(Show::ART_DIR, name)
    end

    def final_audio_path
      name = weekly? ? format("%<y>d_%<w>02d_episode.mp3", y: year, w: week) : "#{year}_#{kind}_episode.mp3"
      File.join(Show::ROOT, "podcast_audio", name)
    end

    # Title without needing a script (weekly adds the preview unless there is none to preview).
    def title(recap_only: false)
      return show[:title].call(year) unless weekly?
      return "#{year} National Championship Reactions | National Champions: #{champion}" if championship?

      parts = [ "#{year} #{recap_label} Reactions" ]
      parts << "#{preview_label} Preview" unless recap_only || preview_week.nil?
      parts.join(" | ")
    end

    def minutes = show[:minutes]

    # The show-specific rules ported from the old NotebookLM prompts ("" when the markdown's own notes cover it).
    def rules = show[:rules]
  end
end
