puts "Cleaning the database..."
Team.destroy_all
Squad.destroy_all
PositionBoard.destroy_all
Player.destroy_all
RosterSlot.destroy_all
User.destroy_all

user = User.find_or_create_by!(email: "coach@example.com") do |u|
  u.name = "Coach"
  u.password = "password123"
  u.password_confirmation = "password123"
end

team = user.teams.find_or_create_by!(name: "Purdue")

offense = team.squads.find_or_create_by!(name: "Offense")
defense = team.squads.find_or_create_by!(name: "Defense")
special = team.squads.find_or_create_by!(name: "Graduates/Departures")

qb_board = PositionBoard.find_or_create_by!(
  team: team,
  squad: offense,
  name: "Quarterback",
  sort_order: 1
) do |pb|
  pb.slots_count = 5
  pb.highlighted_attributes = %w[speed throw_power throw_accuracy awareness]
  pb.target_archetypes = %w[dual_threat pro_style]
end

wr_board = PositionBoard.find_or_create_by!(
  team: team,
  squad: offense,
  name: "Wide Receiver",
  sort_order: 2
) do |pb|
  pb.slots_count = 8
  pb.highlighted_attributes = %w[speed route_running catching release]
  pb.target_archetypes = %w[deep_threat possession slot]
end

Player.find_or_create_by!(name: "Kenyon Sample", team: team) do |p|
  p.class_year = "FR"
  p.dev_trait = "star"
  p.archetype = "dual_threat"
  p.status = :rostered
  p.overall = 81
  p.star_rating = 4
  p.squad = offense
  p.position_board = qb_board
  p.attribute_values = { speed: 86, throw_power: 88, throw_accuracy: 82, awareness: 78 }
end

Player.find_or_create_by!(name: "Daley Sample", team: team) do |p|
  p.class_year = "JR"
  p.dev_trait = "normal"
  p.archetype = "power_back"
  p.status = :rostered
  p.overall = 93
  p.star_rating = 4
  p.squad = offense
  p.position_board = wr_board
  p.attribute_values = { speed: 93, catching: 88, route_running: 85, release: 84 }
end
