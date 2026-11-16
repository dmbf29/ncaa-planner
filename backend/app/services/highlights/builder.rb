require "tmpdir"

module Highlights
  # Local-only: cuts a short highlights video out of a game's stream recording. Every moment is a clip around a logged video
  # time, and clips that overlap are merged, then joined in game order. Two sources of moments:
  #   * scoring plays, from the scouting report next to the recording (see GameScoring::Recordings). The scoreboard changes
  #     just after the play, during the extra-point screen, so the clip starts well before the logged time.
  #   * turnovers, from the "turnovers" stored in the same summary (GameScoring::Turnovers, found by tools/scouting/key_plays.py).
  #     They are logged while the play happens, so these clips start closer and run longer.
  class Builder
    Error = Class.new(StandardError)

    Moment = Struct.new(:offset, :label)

    OUTPUT_DIR = GameScoring::Recordings::STREAMS_DIR.join("highlights")

    # Seconds of video kept before and after the logged time.
    SCORE_PADDING = { lead: 18, tail: 6 }.freeze
    TURNOVER_PADDING = { "Fumble" => { lead: 8, tail: 12 }, "Turnover" => { lead: 10, tail: 12 } }.freeze

    # YouTube turns "0:00 ..." lines into chapters, so every moment gets its own time in the highlights video.
    def self.description(game, moments)
      week = game.week
      header = "#{game.away_college.name} at #{game.home_college.name}, #{week.season.year} #{week.name || "Week #{week.number}"}: scoring plays and turnovers."
      chapters = moments.map { |moment| format("%d:%02d %s", moment.offset / 60, moment.offset % 60, moment.label) }
      [ header, *chapters ].join("\n")
    end

    # lead/tail override the padding around scoring plays.
    def initialize(game, lead: SCORE_PADDING[:lead], tail: SCORE_PADDING[:tail], turnovers: true)
      @game = game
      @score_padding = { lead: lead, tail: tail }
      @turnovers = turnovers
    end

    # Writes the highlights mp4 to `output`; returns the moments (offset in the new video + a text line) for chapters.
    def call(output)
      raise Error, "Game #{@game.id} has no scoring summary to cut highlights from." if @game.scoring_summary.blank?
      raise Error, "No recording at #{recording}." unless recording.file?
      raise Error, "No scouting report at #{report_path}." unless report_path.file?

      windows = merged_windows
      FileUtils.mkdir_p(File.dirname(output))
      Dir.mktmpdir("highlights") do |dir|
        clips = windows.each_with_index.map { |window, index| cut(window, File.join(dir, format("clip%02d.mp4", index))) }
        join(clips, dir, output)
      end
      moments(windows)
    end

    # The chapter list without cutting anything, for a highlights file that was built earlier.
    def moments_for_description
      moments(merged_windows)
    end

    private

    def source
      @game.scoring_summary["source"]
    end

    def recording
      @recording ||= GameScoring::Recordings::STREAMS_DIR.join("#{source}.ts")
    end

    def report_path
      GameScoring::Recordings::STREAMS_DIR.join("#{source}.scout.json")
    end

    def report
      @report ||= JSON.parse(report_path.read)
    end

    # The summary's plays and the report's scoring entries are the same list in the same order.
    def scores
      @scores ||= begin
        entries = report["scoring"]
        plays = @game.scoring_summary["plays"]
        raise Error, "The saved scoring summary no longer matches the scouting report; re-attach it." unless entries.size == plays.size

        entries.zip(plays).map do |entry, play|
          @score_padding.merge(time: entry["time"].to_f, label: label_for(play))
        end
      end
    end

    # Empty when the summary was attached before turnovers were stored (re-attach it) or none were found.
    def turnover_events
      return [] unless @turnovers

      (@game.scoring_summary["turnovers"] || []).filter_map do |event|
        padding = TURNOVER_PADDING[event["kind"]]
        padding&.merge(time: event["time"].to_f, label: label_for(event))
      end
    end

    def label_for(event)
      quarter = event["quarter"].to_i
      "#{quarter <= 4 ? "Q#{quarter}" : "OT#{quarter - 4}"} #{GameScoring::Formatter.line(@game.scoring_summary, event)}"
    end

    # [{ start:, finish:, events: [...] }, ...] in video order, overlapping windows merged.
    def merged_windows
      duration = report["duration_s"].to_f
      (scores + turnover_events).sort_by { |event| event[:time] }.each_with_object([]) do |event, windows|
        start = [ event[:time] - event[:lead], 0 ].max
        finish = event[:time] + event[:tail]
        finish = [ finish, duration ].min if duration.positive?
        if windows.last && start <= windows.last[:finish]
          windows.last[:finish] = [ windows.last[:finish], finish ].max
          windows.last[:events] << event
        else
          windows << { start: start, finish: finish, events: [ event ] }
        end
      end
    end

    def cut(window, path)
      run("ffmpeg", "-v", "error", "-y", "-ss", window[:start].to_s, "-i", recording.to_s, "-t", (window[:finish] - window[:start]).to_s,
          "-c:v", "libx264", "-preset", "veryfast", "-crf", "22", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", path)
      path
    end

    def join(clips, dir, output)
      list = File.join(dir, "clips.txt")
      File.write(list, clips.map { |clip| "file '#{clip}'\n" }.join)
      run("ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", "-movflags", "+faststart", output.to_s)
    end

    def moments(windows)
      elapsed = 0.0
      windows.flat_map do |window|
        offset = elapsed
        elapsed += window[:finish] - window[:start]
        window[:events].map { |event| Moment.new(offset + [ event[:time] - event[:lead] - window[:start], 0 ].max, event[:label]) }
      end
    end

    def run(*command)
      system(*command) || raise(Error, "#{command.first} failed")
    end
  end
end
