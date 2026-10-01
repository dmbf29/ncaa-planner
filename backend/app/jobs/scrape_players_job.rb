require "open-uri"
require "nokogiri"

class ScrapePlayersJob < ApplicationJob
  queue_as :default

  # Header text (from the "All Players" table) -> attribute_values key.
  # These are the keys the front-end already knows how to render.
  ATTRIBUTE_KEY_MAP = {
    "SPD" => "speed",
    "STR" => "strength",
    "AGI" => "agility",
    "ACC" => "acceleration",
    "COD" => "change_of_direction",
    "INJ" => "injury",
    "STA" => "stamina",
    "AWR" => "awareness"
  }.freeze

  def perform(college_id: nil, team_name: nil, team_id: nil, user_id: nil)
    team = find_or_create_team(team_id: team_id, team_name: team_name, user_id: user_id)
    url = College.find_by(id: college_id)&.scraping_url
    return unless url

    doc = Nokogiri::HTML.parse(URI.parse(url).open)

    # Production DB round-trips are slow, so cache lookups instead of querying per player.
    @existing_players = team.players.index_by(&:name)
    @squads = team.squads.index_by(&:name)
    @boards = team.position_boards.index_by { |b| [ b.name, b.squad_id ] }

    ActiveRecord::Base.transaction do
      parse_players(doc).each { |attrs| upsert_player(team, attrs) }
    end
  end

  private

  def find_or_create_team(team_id:, team_name:, user_id:)
    return Team.find(team_id) if team_id.present?

    user = user_id.present? ? User.find(user_id) : User.first
    user.teams.find_or_create_by!(name: team_name)
  end

  def parse_players(doc)
    table = doc.at_css("table")
    headers = table.css("thead th").map { |th| th.text.strip }
    attribute_headers = headers[4..] || []

    table.css("tbody tr").map do |row|
      cells = row.css("> td")
      name_cell = cells[0]
      meta = name_cell.at_css("div.flex.items-center.gap-2.text-xs.text-content-muted")

      {
        name: name_cell.at_css("a")&.text&.strip&.sub(/\*+\z/, "")&.strip,
        position_code: meta&.at_css("span.bg-surface-hover")&.text&.strip,
        class_year: parse_class_year(meta),
        archetype: meta&.css("> span")&.last&.text&.strip,
        overall: cells[1].text.strip.to_i,
        dev_trait: cells[2].text.strip.downcase,
        nil_amount: cells[3].text.strip.to_i,
        attribute_values: parse_attribute_values(cells[4..], attribute_headers)
      }
    end
  end

  def parse_class_year(meta)
    return if meta.blank?

    class_year_span = meta.at_css("span.flex.items-center.gap-1")
    return if class_year_span.blank?

    base = class_year_span.xpath("./text()").text.strip
    redshirt = class_year_span.at_css("span").present?
    redshirt ? "#{base}(RS)" : base
  end

  def parse_attribute_values(attribute_cells, attribute_headers)
    attribute_headers.each_with_index.each_with_object({}) do |(header, index), values|
      key = ATTRIBUTE_KEY_MAP[header] || header.downcase
      values[key] = attribute_cells[index].text.strip.to_i
    end
  end

  def upsert_player(team, attrs)
    return if attrs[:name].blank?

    player = @existing_players[attrs[:name]] || team.players.build(name: attrs[:name])
    player.status = :rostered if player.new_record?
    player.class_year = attrs[:class_year]
    player.dev_trait = attrs[:dev_trait]
    player.archetype = attrs[:archetype]
    player.overall = attrs[:overall]
    player.nil_amount = attrs[:nil_amount]
    player.attribute_values = attrs[:attribute_values]
    board = find_or_create_position_board(team, attrs[:position_code])
    player.position_board = board
    # Assign the cached squad object so validations don't re-query it.
    player.squad = @squads.values.find { |sq| sq.id == board.squad_id } if board
    player.save!
    @existing_players[player.name] = player
  end

  def find_or_create_position_board(team, position_code)
    board_meta = PositionBoardMapping.resolve(position_code)
    return nil if board_meta.blank?

    squad = @squads[board_meta[:squad]] ||= team.squads.create!(name: board_meta[:squad])
    @boards[[ board_meta[:board], squad.id ]] ||= team.position_boards.create!(name: board_meta[:board], squad_id: squad.id)
  end
end
