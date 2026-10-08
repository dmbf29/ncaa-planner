namespace :big_game_breakdown do
  desc "Delete the locked lines and picks for a week so they're rebuilt on the next request " \
       "(e.g. after fixing rosters): rake big_game_breakdown:reset[SEASON_ID,WEEK_NUMBER]. Refuses if any of " \
       "the week's picked games has been played (picks can't be rebuilt for a played game, and they're needed " \
       "for grading); FORCE=1 deletes them anyway."
  task :reset, %i[season_id week_number] => :environment do |_task, args|
    season = Season.find(args.fetch(:season_id))
    week = season.weeks.find_by!(number: args.fetch(:week_number))

    picks = GamePick.where(game_id: Game.where(week_id: week.id).select(:id))
    played = Game.where(id: picks.select(:game_id)).includes(:home_college, :away_college, :college_game_stats).select(&:played?)

    if played.any? && ENV["FORCE"] != "1"
      names = played.map { |game| "#{game.away_college.name} @ #{game.home_college.name}" }.join(", ")
      abort "Not resetting #{season.year} Week #{week.number}: #{played.size} picked game(s) already played (#{names}). " \
            "Their picks can't be recreated and are needed for grading. Re-run with FORCE=1 to delete them anyway."
    end

    deleted = picks.delete_all
    puts "Deleted #{deleted} pick(s) for #{season.year} Week #{week.number}."
  end
end
