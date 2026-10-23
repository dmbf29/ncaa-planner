require "open3"

# Script -> finished mp3: voices the script in chunks with Podcast::GeminiSpeech, joins them, and mixes the result
# with the intro/outro music bed in ffmpeg.
#
# Mix, matched to the published episodes (measured against pod/raw_audio/podcast_intro_outro.mp3, a ~60s music piece):
# the music opens at full volume and fades out as the voices come in at SPEECH_START seconds. The outro is the SAME
# music again from its beginning, fading in under the last seconds of the voices and fading out after the last word.
module Podcast
  class EpisodeProducer
    CHUNK_WORDS = 500
    CHUNK_GAP = 0.25 # seconds of silence between voiced chunks
    SPEECH_START = 9.0
    INTRO_FADE = 4.0
    OUTRO_LENGTH = 15.5  # seconds of the music's start used for the outro
    OUTRO_FADE_IN = 9.0
    OUTRO_FADE_OUT = 5.0
    OUTRO_TAIL = 5.0     # music left ringing after the last word
    MUSIC_PATH = File.expand_path("../../../../pod/raw_audio/podcast_intro_outro.mp3", __dir__)

    def initialize(script_path:, out_dir:, name:)
      @turns = File.readlines(script_path, chomp: true).filter_map do |line|
        match = /\A(ARLIS|TY):\s*(.+)\z/.match(line)
        { speaker: match[1], text: match[2] } if match
      end
      @out_dir = out_dir
      @name = name
      FileUtils.mkdir_p(out_dir)
    end

    # remix: true skips voicing and re-mixes the speech file left by an earlier run (to tweak the music mix only).
    def call(remix: false)
      speech_file = File.join(out_dir, "#{name}_speech.wav")
      return mix(speech_file) if remix && File.exist?(speech_file)

      chunks = chunk_turns
      $stderr.puts "[episode] #{@turns.size} turns in #{chunks.size} chunks"
      wavs = chunks.each_with_index.map do |chunk, index|
        path = File.join(out_dir, "#{name}_chunk#{index}.wav")
        unless File.exist?(path) # lets a rerun resume after a failed chunk
          $stderr.puts "[episode] voicing chunk #{index + 1}/#{chunks.size} (#{chunk.sum { |t| t[:text].split.size }} words)"
          File.binwrite(path, GeminiSpeech.call(chunk))
        end
        path
      end
      speech = join(wavs)
      mix(speech)
    end

    private

    attr_reader :out_dir, :name

    def chunk_turns
      @turns.each_with_object([ [] ]) do |turn, groups|
        words = groups.last.sum { |t| t[:text].split.size }
        groups << [] if words >= CHUNK_WORDS
        groups.last << turn
      end
    end

    def join(wavs)
      output = File.join(out_dir, "#{name}_speech.wav")
      inputs = wavs.flat_map { |wav| [ "-i", wav ] }
      pads = wavs.each_index.map { |i| "[#{i}:a]apad=pad_dur=#{CHUNK_GAP}[p#{i}]" }.join(";")
      labels = wavs.each_index.map { |i| "[p#{i}]" }.join
      ffmpeg(*inputs, "-filter_complex", "#{pads};#{labels}concat=n=#{wavs.size}:v=0:a=1[out]", "-map", "[out]", "-y", output)
      output
    end

    def mix(speech)
      duration = ffprobe_duration(speech)
      outro_start = SPEECH_START + duration + OUTRO_TAIL - OUTRO_LENGTH
      output = File.join(out_dir, "#{name}.mp3")
      graph = [
        "[0:a]loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,aformat=channel_layouts=stereo,adelay=#{(SPEECH_START * 1000).to_i}:all=1[voice]",
        "[1:a]atrim=0:#{SPEECH_START + INTRO_FADE},asetpts=PTS-STARTPTS,afade=t=out:st=#{SPEECH_START}:d=#{INTRO_FADE}[intro]",
        "[1:a]atrim=0:#{OUTRO_LENGTH},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=#{OUTRO_FADE_IN}," \
        "afade=t=out:st=#{OUTRO_LENGTH - OUTRO_FADE_OUT}:d=#{OUTRO_FADE_OUT},adelay=#{(outro_start * 1000).to_i}:all=1[outro]",
        "[voice][intro][outro]amix=inputs=3:normalize=0:duration=longest[out]"
      ].join(";")
      ffmpeg("-i", speech, "-i", MUSIC_PATH, "-filter_complex", graph, "-map", "[out]",
             "-codec:a", "libmp3lame", "-b:a", "128k", "-y", output)
      output
    end

    def ffprobe_duration(path)
      out, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path)
      out.to_f
    end

    def ffmpeg(*args)
      _out, err, status = Open3.capture3("ffmpeg", "-loglevel", "error", *args)
      raise "ffmpeg failed: #{err}" unless status.success?
    end
  end
end
