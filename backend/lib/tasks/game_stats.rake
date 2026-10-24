namespace :game_stats do
  desc "Delete StudentGameStat rows where every stat is 0 or blank (players listed on a stat screen who did " \
       "nothing). Dry run by default; APPLY=1 deletes. Players/StudentSeasons are left alone."
  task prune_empty: :environment do
    stat_columns = GameStats::StatFields::PLAYER_FIELDS.map(&:to_s)
    empty = StudentGameStat.find_each.select { |stat| GameStats::StatFields.empty_line?(stat.attributes.slice(*stat_columns)) }

    puts "#{empty.size} of #{StudentGameStat.count} StudentGameStat rows have no non-zero stat."
    next puts("Nothing to do.") if empty.empty?

    by_season = empty.group_by { |stat| stat.game.week.season }.sort_by { |season, _| season.year }
    by_season.each { |season, stats| puts "  #{season.year}: #{stats.size}" }

    if ENV["APPLY"] == "1"
      deleted = StudentGameStat.where(id: empty.map(&:id)).delete_all
      puts "Deleted #{deleted} row(s)."
    else
      puts "Dry run. Re-run with APPLY=1 to delete them."
    end
  end
end
