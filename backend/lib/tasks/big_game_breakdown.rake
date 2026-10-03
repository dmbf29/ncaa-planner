namespace :big_game_breakdown do
  desc "Delete the locked lines and picks for a week so they're rebuilt on the next request " \
       "(e.g. after fixing rosters): rake big_game_breakdown:reset[SEASON_ID,WEEK_NUMBER]"
  task :reset, %i[season_id week_number] => :environment do |_task, args|
    season = Season.find(args.fetch(:season_id))
    week = season.weeks.find_by!(number: args.fetch(:week_number))

    deleted = GamePick.where(game_id: Game.where(week_id: week.id).select(:id)).delete_all
    puts "Deleted #{deleted} pick(s) for #{season.year} Week #{week.number}."
  end
end
