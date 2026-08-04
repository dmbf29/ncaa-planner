module GameStats
  # Orchestrates a single "analyze these screenshots" request: uploads the
  # images as ActiveStorage blobs (so they can be reused at commit time
  # without re-uploading), runs vision extraction, then narrative synthesis.
  # Persists nothing on the Game/CollegeGameStat/StudentGameStat tables —
  # that only happens if/when the user confirms via CommitService.
  class ExtractionService
    def initialize(game)
      @game = game
    end

    def call(uploaded_files)
      blobs = attach_transient_blobs(uploaded_files)

      home_roster = Roster.for(@game.home_college, season)
      away_roster = Roster.for(@game.away_college, season)

      extraction = VisionExtractor.new(
        home_college: @game.home_college,
        away_college: @game.away_college,
        home_roster: home_roster,
        away_roster: away_roster
      ).call(blobs)

      narrative = NarrativeSynthesizer.new(
        home_college: @game.home_college,
        away_college: @game.away_college
      ).call(college_stats: extraction[:college_stats], player_stats: extraction[:player_stats])

      {
        screenshot_signed_ids: blobs.map(&:signed_id),
        college_stats: extraction[:college_stats],
        player_stats: extraction[:player_stats],
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
  end
end
