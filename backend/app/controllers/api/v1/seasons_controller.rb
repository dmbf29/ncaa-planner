module Api
  module V1
    class SeasonsController < BaseController
      skip_after_action :verify_policy_scoped
      skip_after_action :verify_authorized
      before_action :set_dynasty
      before_action :set_season, except: :create

      def show
        authorize @season
        render json: ::SeasonDashboardSerializer.cached(@season)
      end

      def create
        @season = @dynasty.seasons.new(season_params)
        authorize @season
        @season.save!
        render json: { id: @season.id, year: @season.year }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      # Backgrounded — see ScheduleAnalysisJob for why. Uploads the
      # screenshots as blobs right away (fast, no LLM call) and hands their
      # signed_ids to the job; the frontend polls #analyze_schedule_status
      # with the returned token for the result.
      def analyze_schedule
        authorize @season
        token = SecureRandom.uuid
        blobs = BlobUploader.attach_blobs(Array(params[:images]))

        AnalysisStatus.pending!(token)
        ScheduleAnalysisJob.perform_later(token: token, season_id: @season.id, image_signed_ids: blobs.map(&:signed_id))
        render json: { token: token, status: "pending" }, status: :accepted
      end

      def analyze_schedule_status
        authorize @season
        status = AnalysisStatus.read(params[:token])

        case status[:status]
        when "completed"
          render json: { status: "completed", analysis: status[:result] }
        when "failed"
          render json: { status: "failed", error: status[:error], code: "extraction_failed" }, status: :unprocessable_entity
        when "not_found"
          render json: { status: "failed", error: "Analysis expired or not found — try again.", code: "extraction_failed" },
                 status: :unprocessable_entity
        else
          render json: { status: "pending" }
        end
      end

      def commit_schedule
        authorize @season
        week = @season.weeks.find(params[:week_id])
        warnings = ScheduleStats::CommitService.new(week).call(commit_rows)
        render json: { week_id: week.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_all_americans
        authorize @season
        result = AllAmericans::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_all_americans
        authorize @season
        warnings = AllAmericans::CommitService.new(@season).call(commit_groups)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_nil_spend
        authorize @season
        result = NilSpend::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_nil_spend
        authorize @season
        warnings = NilSpend::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def team_attributes
        authorize @season
        render json: ::TeamAttributesSerializer.new(@season).as_json
      end

      def coach_info
        authorize @season
        render json: ::SeasonCoachInfoSerializer.new(@season).as_json
      end

      def analyze_conference_standings
        authorize @season
        result = ConferenceStandings::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_conference_standings
        authorize @season
        warnings = ConferenceStandings::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_team_stats
        authorize @season
        extractor = params[:stat_type] == "defense" ? TeamStats::DefenseExtractor.new : TeamStats::OffenseExtractor.new
        result = extractor.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_team_stats
        authorize @season
        warnings = TeamStats::CommitService.new(@season, params[:stat_type]).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_players_of_the_week
        authorize @season
        result = PlayersOfTheWeek::Extractor.new.call(Array(params[:images]), season: @season)
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_players_of_the_week
        authorize @season
        warnings = PlayersOfTheWeek::CommitService.new(@season).call(commit_groups)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_recruiting
        authorize @season
        result = Recruiting::Extractor.new.call(Array(params[:images]))
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_recruiting
        authorize @season
        warnings = Recruiting::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def analyze_recruitment_trail
        authorize @season
        result = RecruitmentTrail::Extractor.new.call(Array(params[:images]), season: @season)
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_recruitment_trail
        authorize @season
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        week = @season.weeks.find_by!(number: params[:week_number])
        warnings = RecruitmentTrail::CommitService.new(college_season, week).call(commit_rows)
        # The dashboard payload is cached on season.updated_at; without this the recruits list stays stale.
        @season.touch
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      # Coached teams' signees for the hand-entry overall page. Transfers are
      # listed too (read-only) with the overall found via their linked
      # StudentSeason this season, so a missing/wrong match is visible.
      def signed_recruit_overalls
        authorize @season
        render json: { teams: SignedRecruitOverallsSerializer.new(@season).as_json }
      end

      def commit_signed_recruit_overalls
        authorize @season
        warnings = SignedRecruitOveralls::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      end

      def analyze_team_schedule
        authorize @season
        result = TeamSchedule::ScheduleExtractor.new.call(Array(params[:images]), season: @season)
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_team_schedule
        authorize @season
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        warnings = TeamSchedule::CommitService.new(college_season).call(team_stats_params, commit_rows)
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def destroy
        authorize @season
        @season.destroy
        head :no_content
      end

      # Local-only: shells out to tools/roster_video (OCR on a screen recording)
      # instead of paying for AI vision. Backgrounded like analyze_schedule; the
      # frontend polls #roster_video_status with the returned token.
      def start_roster_video
        authorize @season
        return render_roster_video_dev_only unless Rails.env.development?

        video = params[:video]
        return render json: { error: "No video uploaded", code: "missing_video" }, status: :unprocessable_entity unless video.respond_to?(:tempfile)

        token = SecureRandom.uuid
        path = RosterVideoJob.stash_upload(token, video)
        AnalysisStatus.pending!(token)
        RosterVideoJob.perform_later(token: token, path: path.to_s)
        render json: { token: token, status: "pending" }, status: :accepted
      end

      def roster_video_status
        authorize @season
        return render_roster_video_dev_only unless Rails.env.development?

        status = AnalysisStatus.read(params[:token])
        case status[:status]
        when "completed"
          render json: { status: "completed", analysis: status[:result] }
        when "failed"
          render json: { status: "failed", error: status[:error], code: "extraction_failed" }, status: :unprocessable_entity
        when "not_found"
          render json: { status: "failed", error: "Video job expired or not found — try again.", code: "extraction_failed" },
                 status: :unprocessable_entity
        else
          render json: { status: "pending", progress: status[:progress] }
        end
      end

      def analyze_roster_import
        authorize @season
        college_season = @season.college_seasons.find_by!(id: params[:college_season_id])
        result = RosterImport::Analyzer.new(college_season).call(commit_players)
        render json: { players: result }
      end

      def commit_roster_import
        authorize @season
        college_season = @season.college_seasons.find_by!(id: params[:college_season_id])
        warnings = RosterImport::CommitService.new(college_season).call(commit_players)
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def search_previous_students
        authorize @season
        college_season = @season.college_seasons.find_by!(id: params[:college_season_id])
        results = RosterImport::PreviousSeasonSearch.new(college_season).call(params[:q])
        render json: { students: results }
      end

      def analyze_portal_preview
        authorize @season
        result = PortalPreview::Extractor.new.call(Array(params[:images]))
        college_season = @season.college_seasons.find_by(college_id: result[:college_id])
        result[:players] = PortalPreview::Matcher.new(college_season).resolve_each(result[:players]) if college_season
        render json: result
      rescue RubyLLM::Error => e
        render json: { error: "AI extraction failed: #{e.message}", code: "extraction_failed" }, status: :unprocessable_entity
      end

      def commit_portal_preview
        authorize @season
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        # Not commit_rows: that helper hard-requires a non-empty :rows, but
        # deleting every remaining row for a team (removed_ids only, rows
        # legitimately []) is a normal thing to save here.
        rows = Array(params[:rows]).map { |row| row.to_unsafe_h.deep_symbolize_keys }
        warnings = PortalPreview::CommitService.new(college_season).call(rows, removed_ids: Array(params[:removed_ids]))
        render json: { college_season_id: college_season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def portal_statuses
        authorize @season
        college_season = @season.college_seasons.find_by!(college_id: params[:college_id])
        current_statuses = PortalPreview::CurrentStatuses.new
        render json: { players: current_statuses.call(college_season), roster: current_statuses.roster(college_season) }
      end

      def coach_assignments
        authorize @season
        render json: SeasonCoachAssignmentsSerializer.new(@season).as_json
      end

      def commit_coach_assignments
        authorize @season
        warnings = CoachContinuity::CommitService.new(@season).call(commit_assignments)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      def award_winners
        authorize @season
        render json: SeasonAwardWinnersSerializer.new(@season).as_json
      end

      def commit_award_winners
        authorize @season
        warnings = AwardWinners::CommitService.new(@season).call(commit_rows)
        render json: { season_id: @season.id, warnings: warnings }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "unprocessable_entity" }, status: :unprocessable_entity
      end

      private

      def set_dynasty
        @dynasty = policy_scope(Dynasty).find(params[:dynasty_id])
      end

      def set_season
        @season = @dynasty.seasons.find(params[:id])
      end

      def season_params
        params.require(:season).permit(:year)
      end

      def commit_rows
        params.require(:rows)
        params[:rows].map { |row| row.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_groups
        params.require(:groups)
        params[:groups].map { |group| group.to_unsafe_h.deep_symbolize_keys }
      end

      def commit_assignments
        params.require(:assignments)
        params[:assignments].map { |assignment| assignment.to_unsafe_h.deep_symbolize_keys }
      end

      def render_roster_video_dev_only
        render json: { error: "Roster video import only runs on a local development server", code: "dev_only" }, status: :forbidden
      end

      def commit_players
        params.require(:players)
        params[:players].map { |player| player.to_unsafe_h.deep_symbolize_keys }
      end

      def team_stats_params
        return {} unless params[:team_stats]

        params[:team_stats].to_unsafe_h.deep_symbolize_keys
      end
    end
  end
end
