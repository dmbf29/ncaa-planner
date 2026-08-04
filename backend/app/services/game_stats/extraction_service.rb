module GameStats
  # Orchestrates a single "analyze these screenshots" request: uploads the
  # images as ActiveStorage blobs (so they can be reused at commit time
  # without re-uploading), classifies them by type/team, runs the box score
  # and per-category player extractors against the relevant subsets, then
  # narrative synthesis. Persists nothing on the Game/CollegeGameStat/
  # StudentGameStat tables — that only happens if/when the user confirms via
  # CommitService.
  class ExtractionService
    def initialize(game)
      @game = game
    end

    def call(uploaded_files)
      blobs = attach_transient_blobs(uploaded_files)

      home_roster = Roster.for(@game.home_college, season)
      away_roster = Roster.for(@game.away_college, season)

      grouped = group_images(blobs, classify(blobs))

      college_stats = BoxScoreExtractor.new(home_college: @game.home_college, away_college: @game.away_college)
                                        .call(grouped["box_score"])

      player_stats = StatFields::CATEGORIES.flat_map do |category|
        PlayerCategoryExtractor.new(
          category: category,
          home_college: @game.home_college,
          away_college: @game.away_college,
          home_roster: home_roster,
          away_roster: away_roster
        ).call(grouped[category])
      end

      narrative = NarrativeSynthesizer.new(home_college: @game.home_college, away_college: @game.away_college)
                                       .call(college_stats: college_stats, player_stats: player_stats)

      {
        screenshot_signed_ids: blobs.map(&:signed_id),
        college_stats: college_stats,
        player_stats: player_stats,
        narrative: narrative,
        home_roster: home_roster,
        away_roster: away_roster
      }
    end

    private

    def season
      @game.week.season
    end

    def attach_transient_blobs(uploaded_files)
      Array(uploaded_files).map do |file|
        ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename, content_type: file.content_type)
      end
    end

    def classify(blobs)
      ImageClassifier.new(home_college: @game.home_college, away_college: @game.away_college).call(blobs)
    end

    def group_images(blobs, classification)
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
