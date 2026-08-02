require "open-uri"
require "nokogiri"

class ScrapeStudentsJob < ApplicationJob
  queue_as :default

  # Header text (from the "All Players" table) -> attribute_values key.
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

  def perform(college_season_id:)
    college_season = CollegeSeason.find(college_season_id)
    p url = college_season.college&.scraping_url
    return unless url

    doc = Nokogiri::HTML.parse(URI.parse(url).open)

    ActiveRecord::Base.transaction do
      parse_students(doc).each { |attrs| upsert_student(college_season, attrs) }
    end
  end

  private

  def parse_students(doc)
    table = doc.at_css("table")
    headers = table.css("thead th").map { |th| th.text.strip }
    attribute_headers = headers[4..] || []

    table.css("tbody tr").map do |row|
      cells = row.css("> td")
      name_cell = cells[0]
      meta = name_cell.at_css("div.flex.items-center.gap-2.text-xs.text-content-muted")

      {
        name: name_cell.at_css("a")&.text&.strip,
        position: meta&.at_css("span.bg-surface-hover")&.text&.strip,
        class_year: parse_class_year(meta),
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

  def upsert_student(college_season, attrs)
    return if attrs[:name].blank?

    first_name, last_name = split_name(attrs[:name])
    student = Student.find_or_create_by!(first_name: first_name, last_name: last_name)

    student_season = student.student_seasons.find_or_initialize_by(college_season: college_season)
    student_season.class_year = attrs[:class_year]
    student_season.position = attrs[:position]
    student_season.overall = attrs[:overall]
    student_season.nil_amount = attrs[:nil_amount]
    student_season.dev_trait = attrs[:dev_trait]
    student_season.speed = attrs[:attribute_values]["speed"]
    student_season.save
  end

  def split_name(name)
    parts = name.strip.split(/\s+/)
    return [ parts.first, "" ] if parts.size == 1

    [ parts[0..-2].join(" "), parts[-1] ]
  end
end
