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
    CollegeSeason.where.not(coach: nil).each do |cs|
      cs.opponent_college_seasons.each do |college_season|
        ScrapeStudentsJob.perform_now(college_season_id: college_season.id) unless college_season.student_seasons.count == 85
        sleep(2)
      end
    end
  end
end
