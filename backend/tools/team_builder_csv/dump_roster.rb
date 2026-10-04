# Read-only: prints a college's roster from the DB as JSON, for video_to_csv.py to pick up full first names.
#   bin/rails runner tools/team_builder_csv/dump_roster.rb "UL Monroe" > tmp/team_builder_csv/ul_monroe/db_roster.json
name = ARGV.first
college = College.where("lower(name) = :n OR lower(alternate_name) = :n OR lower(abbrev) = :n", n: name.downcase).first or abort("no college #{name.inspect}")
cs = college.college_seasons.joins(:season).order("seasons.id DESC").first or abort("no college seasons")
rows = cs.student_seasons.includes(:student).map do |ss|
  { first_name: ss.student.first_name, last_name: ss.student.last_name, position: ss.position, class_year: ss.class_year, overall: ss.overall }
end
puts({ college: college.name, season_id: cs.season_id, players: rows }.to_json)
