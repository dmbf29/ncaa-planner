namespace :signed_recruits do
  desc "Link already-saved transfer signees to their previous-roster Student (SEASON_ID optional)"
  task link_transfers: :environment do
    seasons = ENV["SEASON_ID"] ? Season.where(id: ENV["SEASON_ID"]) : Season.all
    seasons.find_each do |season|
      matcher = RecruitmentTrail::TransferMatcher.new(season)
      scope = SignedRecruit.where(transfer: true, student_id: nil, college_season_id: season.college_seasons.select(:id))
      unlinked = scope.to_a
      linked = unlinked.count { |recruit| (student = matcher.student_for(recruit)) && recruit.update!(student: student) }
      puts "Season #{season.year}: linked #{linked} of #{unlinked.size} unlinked transfer signees"
    end
  end
end
