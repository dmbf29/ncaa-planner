module GameScoring
  # Local-only: stream recordings that have been scouted (tools/scouting) but aren't attached to a game yet, each with the
  # game it most likely is, so a game can be attached (and its videos uploaded) the day it is played instead of after the
  # week's box scores are in.
  #
  # The final score can't match a recording to a game yet, so the match is the streamer: each channel is one coach's
  # team, learned from the games already attached (the one college every game of that channel has in common). The
  # suggestion is that college's earliest game with no box score and no recording. A channel with fewer than two attached
  # games can't be learned and gets no suggestion, only the list of open games. Recordings are attached in the order they
  # were made, so one older than the channel's newest attached recording is a game that was skipped on purpose and stays out. A recording
  # shows up once its key-plays and edges scans exist (scout_watch.py runs them right after scouting).
  class Inbox
    RECENT_DAYS = 21
    OPEN_GAMES_LIMIT = 16

    def initialize(dynasty)
      @dynasty = dynasty
    end

    def call
      attached = attached_games
      colleges = streamer_colleges(attached)
      open_games = open_games(attached, colleges.values.compact.uniq)
      recordings(attached.filter_map { |game| game.scoring_summary["source"] }).map do |recording|
        college_id = colleges[recording[:channel]]
        suggested = college_id && open_games.find { |game| [ game.home_college_id, game.away_college_id ].include?(college_id) }
        recording.merge(suggestion: suggested && game_json(suggested), open_games: open_games.first(OPEN_GAMES_LIMIT).map { |game| game_json(game) })
      end
    end

    # Hides a recording from the inbox for good (a practice game, a replay of an old game, ...).
    def self.dismiss(recording_id)
      raise Recordings::Error, "Unknown recording." unless recording_id.to_s.match?(Recordings::ID_FORMAT)

      raise Recordings::Error, "No scouting report for that recording." unless Recordings::STREAMS_DIR.join("#{recording_id}.scout.json").exist?

      FileUtils.touch(Recordings::STREAMS_DIR.join("#{recording_id}.scout.dismissed"))
    end

    private

    def games
      Game.joins(week: :season).where(seasons: { dynasty_id: @dynasty.id })
          .includes(:home_college, :away_college, :college_game_stats, week: :season)
    end

    def attached_games
      games.where.not(scoring_summary: nil).to_a
    end

    # { "douglascribs" => college_id }: the college all of a channel's attached games share.
    def streamer_colleges(attached)
      attached.group_by { |game| game.scoring_summary["source"].split("/").first }.transform_values do |channel_games|
        next if channel_games.size < 2

        shared = channel_games.map { |game| [ game.home_college_id, game.away_college_id ] }.reduce(:&)
        shared.first if shared.size == 1
      end
    end

    def open_games(attached, streamer_college_ids)
      attached_ids = attached.to_set(&:id)
      games.reject { |game| game.played? || attached_ids.include?(game.id) || game.scoring_summary.present? }
           .select { |game| (streamer_college_ids & [ game.home_college_id, game.away_college_id ]).any? }
           .sort_by { |game| [ game.week.season.year, game.week.number, game.id ] }
    end

    def recordings(attached_sources)
      cutoff = RECENT_DAYS.days.ago
      newest_attached = attached_sources.group_by { |source| source.split("/").first }.transform_values { |sources| sources.filter_map { |source| started_at(source) }.max }
      Dir[Recordings::STREAMS_DIR.join("*/*.scout.json")].sort.reverse.filter_map do |path|
        id = "#{File.basename(File.dirname(path))}/#{File.basename(path, '.scout.json')}"
        started_at = started_at(id)
        next if started_at.nil? || started_at < cutoff || attached_sources.include?(id)
        next if newest_attached[id.split("/").first] && started_at < newest_attached[id.split("/").first]
        next if File.exist?(path.sub(/\.scout\.json\z/, ".scout.dismissed"))
        # the watcher reads turnovers and the game's end right after scouting; attaching before that would lose them
        next unless %w[keyplays edges].all? { |scan| File.exist?(path.sub(/\.scout\.json\z/, ".#{scan}.json")) }

        report = JSON.parse(File.read(path))
        next if report["scoring"].blank?

        { id: id, channel: id.split("/").first, started_at: started_at.iso8601, teams: report["teams"], plays: report["scoring"].size,
          final_score: report["scoring"].last["score"] }
      end
    end

    # The recording's name is its start time, in the recorder's local time.
    def started_at(id)
      Time.zone.parse(id.split("/").last.sub(/\A(\d{4}-\d\d-\d\d)_(\d\d)-(\d\d)-(\d\d)\z/, '\1 \2:\3:\4'))
    rescue ArgumentError
      nil
    end

    def game_json(game)
      { game_id: game.id, home: game.home_college.name, away: game.away_college.name, season_year: game.week.season.year,
        week_number: game.week.number, label: "#{game.week.season.year} week #{game.week.number}: #{game.away_college.name} at #{game.home_college.name}" }
    end
  end
end
