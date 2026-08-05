namespace :colleges do
  desc "Create the generic FCS placeholder opponents (not real scoutable programs, so not part of colleges.csv)"
  task seed_fcs_placeholders: :environment do
    %w[FCS\ East FCS\ Midwest FCS\ Northwest FCS\ Southeast FCS\ West].each do |name|
      College.find_or_create_by!(name: name) { |college| college.conference = "FCS" }
    end
  end
end
