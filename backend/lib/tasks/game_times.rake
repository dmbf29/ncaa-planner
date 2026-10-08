namespace :game_times do
  MIN_PLAUSIBLE_KICKOFF_HOUR = 10

  desc "ONE-TIME fix for times saved before the app ran in Eastern: they were saved as wall-clock in the " \
       "server's own zone. Re-reads each stored time as wall-clock in FROM_ZONE and re-saves it as the same " \
       "wall-clock in Eastern. Dry run unless APPLY=1; writes a backup of the old values first. " \
       "Run exactly once: rake game_times:to_eastern[Asia/Tokyo]"
  task :to_eastern, %i[from_zone] => :environment do |_task, args|
    from = ActiveSupport::TimeZone[args.fetch(:from_zone)] || abort("Unknown zone #{args[:from_zone].inspect}")
    apply = ENV["APPLY"] == "1"
    backup = []

    utc = ActiveSupport::TimeZone["UTC"]
    manual = []

    [ Game, BowlProjection ].each do |model|
      records = model.where.not(time: nil).order(:id).to_a
      hours = Hash.new(0)
      records.each do |record|
        in_from_zone = record.time.in_time_zone(from)
        hours[in_from_zone.hour] += 1
        # A kickoff before 10 AM can't be real, so that value was typed into the bowl form (which saved
        # it as UTC wall-clock) rather than imported from a screenshot: read it as UTC instead.
        typed_in_form = in_from_zone.hour < MIN_PLAUSIBLE_KICKOFF_HOUR
        wall = typed_in_form ? record.time.in_time_zone(utc) : in_from_zone
        manual << "#{model.name} #{record.id} (#{wall.strftime('%a %b %-d, %-I:%M %p')})" if typed_in_form
        fixed = Time.zone.local(wall.year, wall.month, wall.day, wall.hour, wall.min)
        backup << { model: model.name, id: record.id, was: record.time.utc.iso8601 }
        record.update_columns(time: fixed) if apply
      end
      sample = records.first
      puts "#{model.name}: #{records.size} rows; wall-clock hours in #{from.name}: #{hours.sort.to_h.inspect}"
      next unless sample

      wall = sample.time.in_time_zone(from)
      puts "  e.g. id #{sample.id}: stored #{sample.time.utc.iso8601} -> reads #{wall.strftime('%a %b %-d, %-I:%M %p')} in #{from.name} -> " \
           "#{Time.zone.local(wall.year, wall.month, wall.day, wall.hour, wall.min).strftime('%a %b %-d, %-I:%M %p %Z')}"
    end
    puts "Read as UTC wall-clock instead (typed into the form; worth a glance): #{manual.join(', ')}" if manual.any?

    if apply
      path = Rails.root.join("tmp/game_times_backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.pretty_generate(backup))
      puts "APPLIED. Old values saved to #{path}. Do not run this again."
    else
      puts "DRY RUN (nothing changed). Re-run with APPLY=1 to apply."
    end
  end
end
