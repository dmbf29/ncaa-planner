# Writes a season's chronicle: a short account of how the season went, kept on Season#chronicle so the podcast hosts
# have storylines (not just tallies) about earlier seasons. Written once after the national title game and then
# frozen, so it can be edited by hand; pass force: true to rewrite it.
#
# The model is given only facts from the database (DynastyHistoryMarkdownPresenter through this season, plus the
# recap summaries of the biggest games) and told to add nothing else.
module SeasonChronicle
  class Writer
    KEY_GAME_LIMIT = 8

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You write the season chronicle for a college football league: the lasting record of one season, read later by the
      hosts of a sports podcast as background on what already happened. Use only the facts in the document you are
      given. Never invent a play, a quote, a stat or a storyline, and never mention a game, a simulation or a "dynasty":
      this is real college football.

      Write plain prose, no headings, no bullets, no markdown, in two parts separated by a blank line:
      1. ONE or TWO sentences: the season in a nutshell, the way an almanac would put it (who won the national title,
         the headline award winners, what stood out for our conference).
      2. THREE to FIVE sentences of storylines: how the champion got there, how our programs fared and any shift in the
         conference's standing (a first title, a breakout, a fall), and anything the document marks as historic.
      Say "first" only where the document's all-time tallies support it. Under 170 words total.
    PROMPT

    def initialize(season, model: nil)
      @season = season
      @model = model
    end

    def call(force: false)
      return @season.chronicle if @season.chronicle.present? && !force

      text = chat.ask(prompt).content.strip
      raise "The chronicle for #{@season.year} came back empty" if text.blank?

      @season.update!(chronicle: text)
      text
    end

    private

    def chat
      chat = @model ? RubyLLM.chat(model: @model) : RubyLLM.chat
      chat.with_instructions(SYSTEM_PROMPT)
    end

    def prompt
      history = DynastyHistoryMarkdownPresenter.new(DynastyHistorySerializer.new(@season, include_current: true, with_chronicles: false).as_json).to_markdown
      <<~PROMPT
        Here is the league record through the #{@season.year} season (the newest season is listed first).

        <record>
        #{history}
        </record>

        #{key_games_block}
        Write the chronicle of the #{@season.year} season.
      PROMPT
    end

    # The title game, the later playoff games and the conference title games of our conference, with their recap text.
    def key_games_block
      games = key_games.map { |game| key_game_line(game) }.compact
      return "" if games.empty?

      "Recaps of the season's biggest games:\n#{games.map { |line| "- #{line}" }.join("\n")}\n"
    end

    def key_games
      weeks = @season.weeks.where("post_season OR conference_championship").pluck(:id)
      Game.where(week_id: weeks).includes(:home_college, :away_college, :college_game_stats)
          .select { |game| game.cfp_round.in?(%w[championship semifinal quarterfinal]) || our_conference_title_game?(game) }
          .sort_by { |game| [ -(Game.cfp_rounds[game.cfp_round] || -1), game.id ] }.first(KEY_GAME_LIMIT)
    end

    def our_conference_title_game?(game)
      conferences = @season.college_seasons.where(college_id: [ game.home_college_id, game.away_college_id ]).pluck(:conference).uniq
      game.week.conference_championship && conferences.size == 1 && conferences.first == our_conference
    end

    def our_conference
      @our_conference ||= @season.college_seasons.where.not(coach_id: nil).group(:conference).order(Arel.sql("COUNT(*) DESC")).count.keys.first
    end

    def key_game_line(game)
      scores = game.college_game_stats.index_by(&:college_id)
      home, away = scores[game.home_college_id]&.final_score, scores[game.away_college_id]&.final_score
      return nil unless home && away

      label = game.cfp_round ? game.cfp_round.humanize : "Conference title game"
      "#{label}: #{game.home_college.name} #{home}, #{game.away_college.name} #{away}. #{game.narrative_summary}".strip
    end
  end
end
