namespace :dynasty do
  desc "Setup the first dynasty"
  task create: :environment do
    user = User.find_by(email: "douglasmberkley@gmail.com")
    dynasty = Dynasty.find_or_create_by!(name: "Sun Belt Challenge", user:)
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
      ScrapeStudentsJob.perform_now(college_season_id: college_season.id)
    end
  end
end
