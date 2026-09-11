namespace :db do
  desc 'Drops the development DB and replaces it with the Aiven production DB'
  task pull: :environment do
    source = ENV.fetch('AIVEN_DATABASE_URL') # full Aiven service URI, keep ?sslmode=require
    target = 'ncaa_planner_dev'

    puts '-----> Setting the environment...'
    run 'RAILS_ENV=development rails db:environment:set'

    puts '-----> dropping & recreating the local DB...'
    run 'rails db:drop db:create'

    puts '-----> pulling the DB from Aiven...'
    # pg_dump 17+ emits `SET transaction_timeout` (unknown to the local PG 15 server); strip it.
    run %(bash -c 'set -o pipefail; pg_dump --no-owner --no-privileges --no-comments "#{source}" | sed -e "/^SET transaction_timeout/d" | psql --quiet --set ON_ERROR_STOP=1 "#{target}"')
  end

  def run(cmd)
    system(cmd)
    raise "Command #{cmd.inspect} failed!" unless $?.success?
  end
end
