namespace :roster_import do
  desc "Link players with no history to last season's Student (SEASON_ID, default latest; APPLY=1 to write, otherwise a dry run)"
  task link_history: :environment do
    season = ENV["SEASON_ID"] ? Season.find(ENV["SEASON_ID"]) : Season.order(:year).last
    apply = ENV["APPLY"] == "1"
    puts "#{apply ? 'APPLYING' : 'DRY RUN'} for the #{season.year} season"

    total = 0
    skipped_total = 0
    RosterImport::HistoryLinker.for_season(season).each do |linker|
      result = linker.plan
      next if result[:links].empty? && result[:skipped].empty?

      puts "== #{linker.instance_variable_get(:@college_season).college.name}"
      result[:links].each do |link|
        ss = link.student_season
        prev = link.previous
        puts "  link #{ss.student.name} (#{ss.position} #{ss.class_year} #{ss.overall}) <- #{prev.college_season.college.name} #{prev.position} #{prev.class_year} #{prev.overall} " \
             "[student #{link.from_student.id} -> #{link.to_student.id}; #{link.reason}]"
      end
      result[:skipped].each do |skip|
        puts "  SKIP #{skip.student_season.student.name}: #{skip.reason} (#{skip.candidates.size} candidates)"
      end
      total += result[:links].size
      skipped_total += result[:skipped].size
      linker.call if apply
    end
    puts "#{apply ? 'Linked' : 'Would link'} #{total}; skipped #{skipped_total}"
  end
end
