module Api
  module V1
    # A podcast episode, driven from the Export page: the weekly recap + preview ("week-11" recaps Week 11 and
    # previews Week 12) or one of the season-long shows ("win_totals", ...; see Podcast::EpisodeSpec). Owner-only:
    # unlike the public broadcast endpoints, these spend API credits and publish to the podcast feed. Each step runs
    # as a background job (PodcastEpisodeJob); the page polls #show.
    class PodcastEpisodesController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season
      before_action :set_status

      def show
        authorize @season, :show_podcast_episode?
        render json: @status.to_h
      end

      # Prepare and produce in one background job: the Export page's main button. Publishing is separate.
      def make
        authorize @season, :manage_podcast_episode?
        start("make", "Starting")
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

      # Throws away an unpublished episode's working files and cover so it can be made again from scratch (for example
      # after the source data was fixed). Published episodes are left alone.
      def reset
        authorize @season, :manage_podcast_episode?
        return render_error("A step is running; wait for it to finish.", :conflict) if @status.running?
        return render_error("This episode is already published, so it can't be reset here.") if @status.to_h[:steps][:published]

        FileUtils.rm_rf(@status.dir)
        FileUtils.rm_f(@status.art_file)
        render json: @status.to_h
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
        @spec = Podcast::EpisodeSpec.for(year: @season.year, slug: params[:slug], season: @season)
        return render_error("Unknown episode \"#{params[:slug]}\".", :not_found) unless @spec

        # Every step spends API credits, so a week that isn't on this season's calendar is refused up front.
        return unless @spec.weekly? && !@season.weeks.exists?(number: @spec.week)

        render_error("Week #{@spec.week} isn't in the #{@season.year} season.", :not_found)
      end

      def set_status
        @status = Podcast::EpisodeStatus.new(spec: @spec)
      end

      def start(step, message, **options)
        @status.start_job!(step, message)
        PodcastEpisodeJob.perform_later(season_id: @season.id, year: @season.year, slug: @spec.slug, step: step, **options)
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
