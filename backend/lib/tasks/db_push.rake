namespace :db do
  desc "Pushes the local development DB to the Aiven production DB — your normal publish step, since friends are read-only there"
  task push: :environment do
    target = ENV.fetch("AIVEN_DATABASE_URL") # full Aiven service URI, keep ?sslmode=require
    source = "ncaa_planner_dev"
    backup_dir = "tmp/db_backups"
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")

    FileUtils.mkdir_p(backup_dir)
    local_backup = "#{backup_dir}/local_#{timestamp}.sql"
    prod_backup = "#{backup_dir}/prod_before_push_#{timestamp}.sql"

    print "Push local DB to production? [y/N] "
    abort "Aborted." unless $stdin.gets&.strip&.downcase == "y"

    # The one that actually matters: local is where the real work happens
    # (production's too slow to edit in directly), so this is the backup
    # worth keeping if anything ever goes wrong locally.
    puts "-----> backing up local DB to #{local_backup}..."
    run %(pg_dump --no-owner --no-privileges --no-comments "#{source}" > #{local_backup})

    # Secondary: lets you undo *this specific push* without having to figure
    # out which local backup was the last good one.
    puts "-----> backing up current production DB to #{prod_backup}..."
    run %(pg_dump --no-owner --no-privileges --no-comments "#{target}" > #{prod_backup})

    puts "-----> pushing local DB to production..."
    # pg_dump 17+ emits `SET transaction_timeout`; strip it defensively in case of a version mismatch
    # the other direction (see db:pull) — harmless no-op when it's not present.
    run %(bash -c 'set -o pipefail; pg_dump --no-owner --no-privileges --no-comments --clean --if-exists "#{source}" | sed -e "/^SET transaction_timeout/d" | psql --quiet --set ON_ERROR_STOP=1 "#{target}"')

    puts "-----> tagging the pushed data as production (it was dumped from a development DB)..."
    run %(psql --quiet "#{target}" -c "update ar_internal_metadata set value = 'production' where key = 'environment';")

    prune_old_backups(backup_dir)
    puts "-----> done."
  end

  # Keeps the 5 most recent of each backup type — this runs often now, no
  # reason to let tmp/db_backups grow forever.
  def prune_old_backups(dir, keep: 5)
    %w[local prod_before_push].each do |prefix|
      files = Dir.glob("#{dir}/#{prefix}_*.sql").sort
      files.first(files.size - keep).each { |f| File.delete(f) } if files.size > keep
    end
  end

  def run(cmd)
    system(cmd)
    raise "Command #{cmd.inspect} failed!" unless $?.success?
  end
end
