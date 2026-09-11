module GameStats
  # Orchestrates a single "analyze these screenshots" request: uploads the
  # images as ActiveStorage blobs (so they can be reused at commit time
  # without re-uploading), then runs box score extraction on the box-score
  # bucket and per-category player extraction on each team's bucket (each
  # bucket's images are classified by category first, since a team's
  # screenshots may cover multiple categories). Persists nothing on the
  # Game/CollegeGameStat/StudentGameStat tables — that only happens if/when
  # the user confirms via CommitService.
  #
  # Deliberately does NOT run NarrativeSynthesizer — the narrative/player-
  # of-the-game pass is a separate opt-in step (see GamesController#analyze_narrative)
  # so games the user doesn't care to write up skip that extra AI call.
  class ExtractionService
    # Turns freshly uploaded files into ActiveStorage blobs (Blobs already
    # in the array — e.g. a reanalyze request — pass through untouched).
    # Public and callable without an instance so GamesController can upload
    # eagerly (fast, no LLM call) before handing signed_ids off to
    # GameAnalysisJob, which can't serialize raw uploaded-file objects onto
    # the job queue the way it can a plain string id.
    def self.attach_blobs(files_or_blobs)
      Array(files_or_blobs).map do |file|
        next file if file.is_a?(ActiveStorage::Blob)

        ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: file.content_type)
      end
    end

    def initialize(game)
      @game = game
    end

    def call(box_score_files:, home_files:, away_files:)
      box_score_blobs = self.class.attach_blobs(box_score_files)
      home_blobs = self.class.attach_blobs(home_files)
      away_blobs = self.class.attach_blobs(away_files)

      home_roster = Roster.for(@game.home_college, season)
      away_roster = Roster.for(@game.away_college, season)

      college_stats = BoxScoreExtractor.new(home_college: @game.home_college, away_college: @game.away_college)
                                        .call(box_score_blobs)

      player_stats = player_stats_for(@game.home_college, home_roster, home_blobs) +
                     player_stats_for(@game.away_college, away_roster, away_blobs)

      {
        box_score_screenshot_signed_ids: box_score_blobs.map(&:signed_id),
        home_screenshot_signed_ids: home_blobs.map(&:signed_id),
        away_screenshot_signed_ids: away_blobs.map(&:signed_id),
        college_stats: college_stats,
        player_stats: player_stats,
        home_roster: home_roster,
        away_roster: away_roster
      }
    end

    private

    def season
      @game.week.season
    end

    def player_stats_for(college, roster, blobs)
      return [] if blobs.blank?

      grouped = group_by_category(blobs, ImageClassifier.new(team_name: college.name).call(blobs))

      StatFields::CATEGORIES.flat_map do |category|
        PlayerCategoryExtractor.new(category: category, college: college, roster: roster).call(grouped[category])
      end
    end

    def group_by_category(blobs, classification)
      by_index = classification.index_by { |entry| entry[:index] }
      groups = Hash.new { |hash, key| hash[key] = [] }

      blobs.each_with_index do |blob, index|
        type = by_index[index]&.fetch(:type, nil)
        groups[type] << blob if type && type != "unknown"
      end

      groups
    end
  end
end
