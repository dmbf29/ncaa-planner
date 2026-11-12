module Api
  module V1
    # Commissioner side of non-conference scheduling: set the season's byes, then upload each coached team's schedule
    # screenshots (read locally) to lock in its fixed games and the weeks its coach will choose.
    class SchedulingsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_season

      def show
        render json: Scheduling::Overview.new(@season).as_json
      end

      def update
        byes = Array(params[:bye_week_numbers]).map(&:to_i).uniq.sort
        unless byes.all? { |n| Scheduling::Rules::WEEK_NUMBERS.cover?(n) } && byes.size <= Scheduling::Rules::MAX_BYES
          return render json: { error: "Pick at most #{Scheduling::Rules::MAX_BYES} bye weeks between 0 and 13.", code: "unprocessable_entity" }, status: :unprocessable_entity
        end

        @season.update!(schedule_bye_week_numbers: byes)
        render json: Scheduling::Overview.new(@season).as_json
      end

      # Synchronous: two screenshots read with Apple Vision take a few seconds.
      def analyze_team
        paths = Array(params[:images]).filter_map { |file| file.respond_to?(:tempfile) ? stash(file) : nil }
        return render json: { error: "Upload the team's schedule screenshots.", code: "missing_images" }, status: :unprocessable_entity if paths.empty?

        render json: Scheduling::TeamReader.new.call(paths, season: @season)
      rescue Scheduling::TeamReader::Error => e
        render json: { error: e.message, code: "extraction_failed" }, status: :unprocessable_entity
      ensure
        paths&.each { |path| FileUtils.rm_f(path) }
      end

      # Local-only, like the roster video: a recording of the opponent picker is read in the background
      # (OpponentVideoJob); poll #week_video_status with the returned token.
      def start_week_video
        return render json: { error: "Reading recordings only works on the local dev server.", code: "dev_only" }, status: :unprocessable_entity unless Rails.env.development?

        video = params[:video]
        return render json: { error: "No video uploaded", code: "missing_video" }, status: :unprocessable_entity unless video.respond_to?(:tempfile)

        token = SecureRandom.uuid
        path = OpponentVideoJob.stash_upload(token, video)
        AnalysisStatus.pending!(token)
        OpponentVideoJob.perform_later(token: token, path: path.to_s)
        render json: { token: token, status: "pending" }, status: :accepted
      end

      def week_video_status
        status = AnalysisStatus.read(params[:token])
        case status[:status]
        when "completed"
          render json: { status: "completed", analysis: Scheduling::OpponentCards.new(@season).call(status[:result]["cards"]) }
        when "failed"
          render json: { status: "failed", error: status[:error], code: "extraction_failed" }, status: :unprocessable_entity
        when "not_found"
          render json: { status: "failed", error: "Video job expired or not found — try again.", code: "extraction_failed" }, status: :unprocessable_entity
        else
          render json: { status: "pending", progress: status[:progress] }
        end
      end

      def commit_week
        college_season = @season.college_seasons.find(params[:college_season_id])
        week = @season.weeks.find(params[:week_id])
        render json: Scheduling::OpponentCommit.new(college_season, week).call(params.require(:cards).map { |card| card.to_unsafe_h })
      end

      def commit_team
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        warnings = Scheduling::TeamCommit.new(college_season).call(params.require(:rows).map { |row| row.to_unsafe_h })
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_season
        dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
        @season = dynasty.seasons.find(params[:season_id])
        authorize @season, :show?
      end

      def stash(file)
        path = Rails.root.join("tmp", "#{SecureRandom.hex(8)}#{File.extname(file.original_filename)}")
        FileUtils.cp(file.tempfile.path, path)
        path.to_s
      end
    end
  end
end
