namespace :dynasty do
  desc "Setup the first dynasty"
  task create: :environment do
    user = User.find_by(email: "douglasmberkley@gmail.com")
    dynasty = Dynasty.find_or_create_by!(name: "Rising in the Sun Belt", user:)
    eric = Coach.find_or_create_by!(name: "Poindexter Pecan-Praline", dynasty:)
    alex = Coach.find_or_create_by!(name: "Randy Moss", dynasty:)
    doug = Coach.find_or_create_by!(name: "Bubba Boudreaux", dynasty:)
    brady = Coach.find_or_create_by!(name: "Dobby The Elf", dynasty:)
    season = Season.find_or_create_by!(year: 2026, dynasty:)
    College.find_each do |college|
      college_season = CollegeSeason.find_or_initialize_by(
        college:,
        season:,
        overall: college.overall,
        offense: college.offense,
        defense: college.defense,
        prestige: college.prestige,
      )
      college_season.save!

      case college.name
      when "UL Monroe"
        college_season.coach = doug
      when "App St."
        college_season.coach = brady
      when "Marshall"
        college_season.coach = alex
      when "GA Southern"
        college_season.coach = eric
      end

      next unless college_season.coach
      college_season.save!
      ScrapeStudentsJob.perform_now(college_season_id: college_season.id) unless college_season.student_seasons.count == 85
    end
  end

  desc "Create the 2026 schedule for the tracked teams"
  task games: :environment do
    user = User.find_by(email: "douglasmberkley@gmail.com")
    dynasty = Dynasty.find_by!(name: "Sun Belt Challenge", user:)
    season = Season.find_by!(year: 2026, dynasty:)

    # week number => [[home_college_name, away_college_name], ...]
    schedule = {
      1 => [
        [ "App St.", "Bowling Green" ],
        [ "GA Southern", "Rice" ],
        [ "Marshall", "Navy" ],
        [ "UL Monroe", "W. Kentucky" ]
      ],
      2 => [
        [ "UMass", "App St." ],
        [ "New Mexico", "GA Southern" ],
        [ "Ohio", "Marshall" ],
        [ "Hawai'i", "UL Monroe" ]
      ],
      3 => [
        [ "App St.", "Charlotte" ],
        [ "GA Southern", "Air Force" ],
        [ "Marshall", "East Carolina" ],
        [ "UL Monroe", "Colorado State" ]
      ],
      4 => [
        [ "App St.", "Arkansas State" ],
        [ "UL Monroe", "GA Southern" ],
        [ "Troy", "Marshall" ]
      ],
      5 => [
        [ "C. Carolina", "GA Southern" ],
        [ "James Madison", "Marshall" ]
      ],
      6 => [
        [ "App St.", "Middle Tenn" ],
        [ "James Madison", "GA Southern" ],
        [ "Marshall", "C. Carolina" ],
        [ "GA State", "UL Monroe" ]
      ],
      7 => [
        [ "App St.", "C. Carolina" ],
        [ "Old Dominion", "GA Southern" ],
        [ "Marshall", "Jax State" ],
        [ "UL Monroe", "Missouri State" ]
      ],
      8 => [
        [ "James Madison", "App St." ],
        [ "UL Monroe", "Troy" ]
      ],
      9 => [
        [ "GA Southern", "App St." ],
        [ "Marshall", "Southern Miss" ],
        [ "UL Monroe", "James Madison" ]
      ],
      10 => [
        [ "App St.", "GA State" ],
        [ "GA Southern", "Marshall" ],
        [ "Arkansas State", "UL Monroe" ]
      ],
      11 => [
        [ "App St.", "Marshall" ],
        [ "GA Southern", "GA State" ],
        [ "C. Carolina", "UL Monroe" ]
      ],
      12 => [
        [ "UL Monroe", "App St." ],
        [ "GA Southern", "Delaware" ],
        [ "Marshall", "GA State" ]
      ],
      13 => [
        [ "Louisiana", "App St." ],
        [ "GA Southern", "Louisiana Tech" ],
        [ "Marshall", "UL Monroe" ]
      ]
    }

    schedule.each do |number, matchups|
      week = Week.find_by!(season:, number:)

      matchups.each do |home_name, away_name|
        home_college = College.find_by!(name: home_name)
        away_college = College.find_by!(name: away_name)

        Game.find_or_create_by!(week:, home_college:, away_college:)
      end
    end
    CollegeSeason.each do |college_season|
      # 50 is just a random number
      ScrapeStudentsJob.perform_now(college_season_id: college_season.id) unless college_season.student_seasons.count > 50
      sleep(5)
    end
  end

  # One-off: the first season's student_seasons were scraped before the
  # combine-attribute columns existed, so ScrapeStudentsJob only kept SPD.
  # This re-fetches each roster from the same source and fills ONLY the new
  # columns (strength/agility/acceleration/change_of_direction/awareness) on
  # student_seasons that already exist — it never creates rows and never
  # touches overall/class_year/position/nil_amount/dev_trait, so anything
  # hand-corrected since the initial scrape is left alone.
  #
  #   rake dynasty:backfill_combine_attributes                 # every college in 2026
  #   rake "dynasty:backfill_combine_attributes[2026,Georgia]" # one college, to spot-check
  #   DRY_RUN=1 rake "dynasty:backfill_combine_attributes[2026,Georgia]"
  desc "Backfill combine-attribute columns on the first season's rosters from the scrape source"
  task :backfill_combine_attributes, [ :year, :college ] => :environment do |_task, args|
    require "open-uri"
    require "nokogiri"

    year = (args[:year] || 2026).to_i
    dry_run = ENV["DRY_RUN"].present?

    # Scrape header text => student_seasons column. SPD is included only as a
    # match check — it should already equal the stored speed, so a mismatch
    # means we lined up the wrong player and should skip that row.
    header_to_column = {
      "SPD" => :speed,
      "STR" => :strength,
      "AGI" => :agility,
      "ACC" => :acceleration,
      "COD" => :change_of_direction,
      "AWR" => :awareness
    }
    new_columns = %i[strength agility acceleration change_of_direction awareness]

    scrape_rows = lambda do |url|
      doc = Nokogiri::HTML.parse(URI.parse(url).open)
      table = doc.at_css("table")
      return [] unless table

      headers = table.css("thead th").map { |th| th.text.strip }
      attribute_headers = headers[4..] || []

      table.css("tbody tr").filter_map do |row|
        cells = row.css("> td")
        name = cells[0].at_css("a")&.text&.strip&.sub(/\*+\z/, "")&.strip
        next if name.blank?

        values = attribute_headers.each_with_index.each_with_object({}) do |(header, i), acc|
          column = header_to_column[header]
          acc[column] = cells[4 + i].text.strip.to_i if column
        end
        [ name, values ]
      end.to_h
    end

    college_seasons = CollegeSeason.joins(:season).where(seasons: { year: year }).includes(:college, student_seasons: :student)
    college_seasons = college_seasons.where(colleges: { name: args[:college] }) if args[:college].present?
    college_seasons = college_seasons.to_a

    puts "#{dry_run ? '[DRY RUN] ' : ''}Backfilling #{new_columns.join(', ')} for #{college_seasons.size} college season(s) in #{year}"

    totals = Hash.new(0)

    college_seasons.each do |college_season|
      college = college_season.college
      unless college.api_id
        puts "  #{college.name}: no api_id, skipping"
        next
      end

      begin
        scraped = scrape_rows.call(college.scraping_url)
      rescue OpenURI::HTTPError, SocketError, Errno::ECONNRESET => e
        puts "  #{college.name}: fetch failed (#{e.class}: #{e.message}), skipping"
        totals[:fetch_failed] += 1
        next
      end

      if scraped.empty?
        puts "  #{college.name}: no rows parsed from #{college.scraping_url}, skipping"
        totals[:empty] += 1
        next
      end

      updated = 0
      unmatched = []
      speed_mismatch = []
      by_name = college_season.student_seasons.group_by { |ss| ss.student.name.downcase }

      scraped.each do |name, values|
        matches = by_name[name.downcase]
        if matches.blank?
          next
        elsif matches.size > 1
          # Same display name twice on one roster — can't safely pick, leave for manual review.
          unmatched << "#{name} (#{matches.size} student_seasons share this name)"
          next
        end

        student_season = matches.first
        if values[:speed] && student_season.speed && values[:speed] != student_season.speed
          speed_mismatch << "#{name} (scrape SPD #{values[:speed]} vs stored #{student_season.speed})"
          next
        end

        attrs = values.slice(*new_columns)
        next if attrs.empty?

        student_season.assign_attributes(attrs)
        if student_season.changed?
          student_season.save!(validate: false) unless dry_run
          updated += 1
        end
      end

      scraped_names = scraped.keys.map(&:downcase).to_set
      missing_from_scrape = college_season.student_seasons.count { |ss| scraped_names.exclude?(ss.student.name.downcase) }

      puts "  #{college.name}: #{updated} updated, #{missing_from_scrape} roster player(s) not on scrape page" \
           "#{unmatched.any? ? ", #{unmatched.size} ambiguous" : ''}" \
           "#{speed_mismatch.any? ? ", #{speed_mismatch.size} SPD mismatch" : ''}"
      unmatched.each { |line| puts "      ambiguous: #{line}" }
      speed_mismatch.each { |line| puts "      SPD mismatch (skipped): #{line}" }

      totals[:updated] += updated
      totals[:ambiguous] += unmatched.size
      totals[:speed_mismatch] += speed_mismatch.size
      totals[:colleges] += 1

      sleep(3) if college_seasons.size > 1
    end

    puts "#{dry_run ? '[DRY RUN] ' : ''}Done. #{totals[:colleges]} college season(s), #{totals[:updated]} student_seasons updated, " \
         "#{totals[:ambiguous]} ambiguous, #{totals[:speed_mismatch]} SPD mismatch, #{totals[:fetch_failed]} fetch failures, #{totals[:empty]} empty."
  end
end
