require "csv"

namespace :colleges do
  desc "Create the generic FCS placeholder opponents (not real scoutable programs, so not part of colleges.csv)"
  task seed_fcs_placeholders: :environment do
    {
      "FCS East" => "FCSE",
      "FCS Midwest" => "FCSMW",
      "FCS Northwest" => "FCSNW",
      "FCS Southeast" => "FCSSE",
      "FCS West" => "FCSW"
    }.each do |name, abbrev|
      college = College.find_or_initialize_by(name: name)
      college.conference = "FCS"
      college.abbrev = abbrev
      college.save!
    end
  end

  desc "Rename any college still stored under its old/abbreviated name to the corrected name in " \
       "db/data/colleges.csv, preserving the old name as alternate_name so screenshot readers can still " \
       "match on it. Reusable: whenever a name is fixed in the CSV (name = correct full name, " \
       "alternate_name = the old value), just re-run this task."
  task apply_renames: :environment do
    CSV.foreach(Rails.root.join("db/data/colleges.csv"), headers: :first_row, header_converters: :symbol) do |row|
      new_name = row[:name]
      alternate_name = row[:alternate_name].presence
      next unless alternate_name

      college = College.find_by(name: new_name) || College.find_by(name: alternate_name)
      unless college
        puts "SKIP #{alternate_name.inspect} -> #{new_name.inspect}: no matching college found"
        next
      end

      if college.name == new_name && college.alternate_name == alternate_name
        puts "OK #{new_name}: already up to date"
        next
      end

      college.update!(name: new_name, alternate_name: alternate_name)
      puts "RENAMED #{alternate_name.inspect} -> #{new_name.inspect}"
    end
  end
end
