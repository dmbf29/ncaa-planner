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
  #
  # Callers that already know each player-stat screenshot's category (the
  # local Remote Play capture reads it off the screen) can pass
  # home_categories/away_categories — one entry per file, nil when unknown —
  # to skip ImageClassifier; only the nil ones are still classified. The
  # special category "defense_extra" marks a name-grafted screenshot of the
  # scrolled-right Defense columns (see PlayerCategoryExtractor::EXTRA_FIELD_GROUPS).
  #
  # On the dev machine, every screenshot is first read locally with Apple Vision (LocalReader; no AI
  # call). The extractors use that when the numbers add up and fall back to the AI for whatever doesn't.
  class ExtractionService
    EXTRA_CATEGORY = "defense_extra".freeze

    def initialize(game)
      @game = game
      @warnings = []
    end

    def call(box_score_files:, home_files:, away_files:, home_categories: nil, away_categories: nil)
      box_score_blobs = BlobUploader.attach_blobs(box_score_files)
      home_blobs = BlobUploader.attach_blobs(home_files)
      away_blobs = BlobUploader.attach_blobs(away_files)

      home_roster = Roster.for(@game.home_college, season)
      away_roster = Roster.for(@game.away_college, season)

      @local = LocalReader.new(box_score_blobs: box_score_blobs, table_blobs: home_blobs + away_blobs)

      box_score_extractor = BoxScoreExtractor.new(home_college: @game.home_college, away_college: @game.away_college, local: @local)
      college_stats = box_score_extractor.call(box_score_blobs)
      @warnings.concat(box_score_extractor.warnings)

      player_stats = player_stats_for(@game.home_college, home_roster, home_blobs, home_categories) +
                     player_stats_for(@game.away_college, away_roster, away_blobs, away_categories)

      {
        box_score_screenshot_signed_ids: box_score_blobs.map(&:signed_id),
        home_screenshot_signed_ids: home_blobs.map(&:signed_id),
        away_screenshot_signed_ids: away_blobs.map(&:signed_id),
        college_stats: college_stats,
        player_stats: player_stats,
        home_roster: home_roster,
        away_roster: away_roster,
        warnings: @warnings
      }
    end

    private

    def season
      @game.week.season
    end

    def player_stats_for(college, roster, blobs, known_categories = nil)
      return [] if blobs.blank?

      grouped = group_by_known_category(blobs, known_categories)
      unknown = blobs - grouped.values.flatten
      unknown -= categorize_locally(unknown, grouped)
      group_by_category(unknown, ImageClassifier.new(team_name: college.name).call(unknown)).each do |category, group|
        grouped[category].concat(group)
      end

      StatFields::CATEGORIES.flat_map do |category|
        extractor = PlayerCategoryExtractor.new(category: category, college: college, roster: roster, local: @local)
        rows = extractor.call(grouped[category], extra_blobs: category == "defense" ? grouped[EXTRA_CATEGORY] : [])
        @warnings.concat(extractor.warnings.map { |warning| "#{college.name} #{warning}" })
        rows
      end
    end

    # Screenshots the capture couldn't label: the local reader knows a table's category from its headers, so
    # only the ones it couldn't read at all go to the AI classifier. One it read but found no recognisable table
    # on is a screen caught mid-navigation (the team menu open over the table, say) and is dropped, as the AI
    # would have been handed a table with its first columns hidden. Returns the blobs it dealt with.
    def categorize_locally(blobs, grouped)
      blobs.select do |blob|
        next false unless @local.read?(blob)

        category = LocalPlayerTable.category_of(@local.table(blob))
        if category
          grouped[category] << blob
        else
          @warnings << "A captured screen that didn't show a full stats table was skipped (#{blob.filename})."
        end
        true
      end
    end

    # known_categories[i] is the category of blobs[i], or nil/absent if unknown.
    def group_by_known_category(blobs, known_categories)
      groups = Hash.new { |hash, key| hash[key] = [] }
      Array(known_categories).each_with_index do |category, index|
        groups[category] << blobs[index] if blobs[index] && (StatFields::CATEGORIES + [ EXTRA_CATEGORY ]).include?(category)
      end
      groups
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
