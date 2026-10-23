module Api
  module V1
    # The weekly podcast episode, driven from the Export page. Owner-only: unlike the public broadcast endpoints,
    # these spend API credits and publish to the podcast feed. Each step runs as a background job (PodcastEpisodeJob);
    # the page polls #show. The week in the URL is the week being recapped, and the next week is previewed.
    class PodcastEpisodesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season
      before_action :set_status

      def show
        authorize @season, :show_podcast_episode?
        render json: @status.to_h
      end

      def prepare
        authorize @season, :manage_podcast_episode?
        start("prepare", "Starting")
      end

      def produce
        authorize @season, :manage_podcast_episode?
        return render_error("Prepare the episode (script and fact-check) first.") unless @status.to_h[:steps][:fact_check]

        redo_audio = params[:redo].to_s == "true"
        if @status.to_h[:steps][:audio] && !redo_audio && !@status.audio_stale?
          return render_error("The audio is already produced.")
        end

        start("produce", "Starting", redo_audio: redo_audio || @status.audio_stale?)
      end

      def publish
        authorize @season, :manage_podcast_episode?
        return render_error("Produce the audio first.") unless @status.to_h[:steps][:audio]
        return render_error("The script was edited after the audio was made: produce it again first.") if @status.audio_stale?

        start("publish", "Starting", episode: Integer(params[:episode], exception: false))
      end

      def regenerate_art
        authorize @season, :manage_podcast_episode?
        start("regenerate_art", "Starting")
      end

      def art
        authorize @season, :show_podcast_episode?
        send_episode_file(@status.art_file, "image/png")
      end

      def audio
        authorize @season, :show_podcast_episode?
        send_episode_file(@status.audio_path, "audio/mpeg")
      end

      def script
        authorize @season, :show_podcast_episode?
        render json: { script: @status.script_text }
      end

      # Hand edits to the reviewed script. The old voices no longer match it, so #show reports audio_stale.
      def update_script
        authorize @season, :manage_podcast_episode?
        return render_error("A step is running; wait for it to finish.", :conflict) if @status.running?

        text = params[:script].to_s
        lines = text.lines.map(&:strip).reject(&:empty?)
        return render_error("The script is empty.") if lines.empty?

        bad = lines.index { |line| !line.match?(/\A(ARLIS|TY): \S/) }
        return render_error("Line #{bad + 1} must start with \"ARLIS: \" or \"TY: \".") if bad

        File.write(@status.path("script.checked.txt"), "#{lines.join("\n")}\n")
        FileUtils.rm_f(@status.path("script.checked.description.txt"))
        render json: @status.to_h
      end

      private

      def set_season
        dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
        @week_number = Integer(params[:week_number], exception: false)
        # Every step spends API credits, so a week that isn't on this season's calendar is refused up front.
        render_error("Week #{params[:week_number]} isn't in the #{@season.year} season.", :not_found) unless @week_number&.positive? && @season.weeks.exists?(number: @week_number)
      end

      def set_status
        @status = Podcast::EpisodeStatus.new(year: @season.year, week_number: @week_number)
      end

      def start(step, message, **options)
        @status.start_job!(step, message)
        PodcastEpisodeJob.perform_later(season_id: @season.id, year: @season.year, week_number: @week_number,
                                        step: step, **options)
        render json: @status.to_h, status: :accepted
      rescue Podcast::EpisodeStatus::AlreadyRunning => e
        render_error(e.message, :conflict)
      end

      def send_episode_file(path, type)
        return render_error("Not generated yet.", :not_found) unless File.exist?(path)

        send_file path, type: type, disposition: "inline"
      end

      def render_error(message, status = :unprocessable_entity)
        render json: { error: message, code: status.to_s }, status: status
      end
    end
  end
end
