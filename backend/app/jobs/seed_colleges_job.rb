require "csv"

class SeedCollegesJob < ApplicationJob
  queue_as :default

  def perform
    # Look into "db/data/colleges.csv" and create_or_find_by
    CSV.foreach("db/data/colleges.csv", headers: :first_row, header_converters: :symbol) do |row|
      college = College.find_by(name: row[:name])
      if college
        college.update(
          api_id: row[:api_id],
          prestige: row[:prestige],
          overall: row[:overall],
          offense: row[:offense],
          defense: row[:defense],
          conference: row[:conference],
          nil_total: row[:nil_total]&.delete(",")&.to_i,
          capacity: row[:capacity]&.delete(",")&.to_i,
          pipeline_ranking: row[:pipeline_ranking],
          alternate_name: row[:alternate_name].presence
        )
      else
        College.create(
          name: row[:name],
          api_id: row[:api_id],
          prestige: row[:prestige],
          overall: row[:overall],
          offense: row[:offense],
          defense: row[:defense],
          conference: row[:conference],
          nil_total: row[:nil_total]&.delete(",")&.to_i,
          capacity: row[:capacity]&.delete(",")&.to_i,
          pipeline_ranking: row[:pipeline_ranking],
          alternate_name: row[:alternate_name].presence
        )
      end
    end
  end
end
