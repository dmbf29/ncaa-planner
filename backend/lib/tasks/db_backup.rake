namespace :db do
  namespace :backup do
    BACKUP_DIR = Rails.root.join("db", "backups").freeze

    desc "Dump the development database to db/backups/ (KEEP=N to prune to the newest N, default 10)"
    task create: :environment do
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      FileUtils.mkdir_p(BACKUP_DIR)

      timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
      path = BACKUP_DIR.join("#{config[:database]}-#{timestamp}.dump")

      env = {}
      env["PGPASSWORD"] = config[:password].to_s if config[:password].present?

      args = [ "pg_dump", "--format=custom", "--no-owner", "--no-privileges", "--file=#{path}" ]
      args << "--host=#{config[:host]}"         if config[:host].present?
      args << "--port=#{config[:port]}"         if config[:port].present?
      args << "--username=#{config[:username]}" if config[:username].present?
      args << config[:database]

      unless system(env, *args)
        abort "pg_dump failed (exit #{$?.exitstatus}). Is PostgreSQL running and pg_dump on your PATH?"
      end

      size = ActiveSupport::NumberHelper.number_to_human_size(File.size(path))
      puts "Wrote #{path} (#{size})"

      keep = Integer(ENV.fetch("KEEP", 10))
      backups = Dir[BACKUP_DIR.join("*.dump")].sort
      (backups[0...-keep] || []).each do |old|
        File.delete(old)
        puts "Pruned #{old}"
      end
    end

    desc "Restore the development database from a .dump file (FILE=path, defaults to newest)"
    task :restore, [ :file ] => :environment do |_t, task_args|
      abort "Refusing to restore outside development (RAILS_ENV=#{Rails.env})" unless Rails.env.development?

      file = task_args[:file] || ENV["FILE"] || Dir[BACKUP_DIR.join("*.dump")].max
      abort "No backup file found. Pass FILE=path or run db:backup:create first." if file.nil?
      abort "No such file: #{file}" unless File.exist?(file)

      config = ActiveRecord::Base.connection_db_config.configuration_hash
      env = {}
      env["PGPASSWORD"] = config[:password].to_s if config[:password].present?

      args = [ "pg_restore", "--clean", "--if-exists", "--no-owner", "--no-privileges", "--dbname=#{config[:database]}" ]
      args << "--host=#{config[:host]}"         if config[:host].present?
      args << "--port=#{config[:port]}"         if config[:port].present?
      args << "--username=#{config[:username]}" if config[:username].present?
      args << file

      puts "Restoring #{config[:database]} from #{file} ..."
      # pg_restore exits non-zero on ignorable "does not exist" notices from --clean; surface but don't abort.
      system(env, *args)
      puts "Done."
    end
  end

  desc "Alias for db:backup:create"
  task backup: "db:backup:create"
end
