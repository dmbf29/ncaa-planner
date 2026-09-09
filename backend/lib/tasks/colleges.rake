require "csv"

namespace :colleges do
  # Scrape each college's logo from the same teamcrafters roster page the player
  # scrapers use and attach it (ActiveStorage -> Cloudinary) as `college.logo`.
  # The page server-renders an <img> pointing at the CDN webp, e.g.
  #   <img alt="Air Force logo" src="https://tc-cdn.trosclair.dev/team-images/air-force-100.webp">
  # We match on the "/team-images/" path so the TeamCrafters site logo is ignored.
  #
  #   rake colleges:scrape_logos                  # every college with an api_id, skips ones already attached
  #   rake "colleges:scrape_logos[Air Force]"     # just one college, by name
  #   FORCE=1 rake colleges:scrape_logos          # re-download and replace existing logos too
  desc "Scrape college logos from the roster pages and attach them via ActiveStorage/Cloudinary"
  task :scrape_logos, [ :college ] => :environment do |_task, args|
    require "open-uri"
    require "nokogiri"

    force = ENV["FORCE"].present?

    colleges = College.where.not(api_id: nil)
    colleges = colleges.where(name: args[:college]) if args[:college].present?
    colleges = colleges.order(:name).to_a

    puts "Scraping logos for #{colleges.size} college(s)#{force ? ' (FORCE: replacing existing)' : ''}"

    totals = Hash.new(0)

    colleges.each do |college|
      if college.logo.attached? && !force
        puts "  #{college.name}: already has a logo, skipping (use FORCE=1 to replace)"
        totals[:skipped] += 1
        next
      end

      begin
        doc = Nokogiri::HTML.parse(URI.parse(college.scraping_url).open)
      rescue URI::InvalidURIError, OpenURI::HTTPError, SocketError, Errno::ECONNRESET => e
        puts "  #{college.name}: page fetch failed (#{e.class}: #{e.message})"
        totals[:fetch_failed] += 1
        next
      end

      img = doc.css("img").find { |node| node["src"].to_s.include?("/team-images/") }
      if img.nil?
        puts "  #{college.name}: no logo <img> found on #{college.scraping_url}"
        totals[:not_found] += 1
        next
      end

      src = img["src"]
      # File.basename is plain string work, so it keeps a clean UTF-8 name
      # ("louisiana–monroe-100.webp"), but URI.parse chokes on the non-ASCII
      # en-dash some slugs use, so percent-escape before opening.
      filename = File.basename(src)

      begin
        io = URI.parse(URI::DEFAULT_PARSER.escape(src)).open
      rescue URI::InvalidURIError, OpenURI::HTTPError, SocketError, Errno::ECONNRESET => e
        puts "  #{college.name}: logo download failed (#{e.class}: #{e.message}) for #{src}"
        totals[:download_failed] += 1
        next
      end

      content_type = io.content_type.presence || Marcel::MimeType.for(name: filename)

      college.logo.purge if college.logo.attached?
      college.logo.attach(io: io, filename: filename, content_type: content_type)

      puts "  #{college.name}: attached #{filename} (#{content_type})"
      totals[:attached] += 1

      sleep(3) if colleges.size > 1
    end

    puts "Done. #{totals[:attached]} attached, #{totals[:skipped]} skipped, " \
         "#{totals[:not_found]} no image, #{totals[:fetch_failed]} page fetch failed, " \
         "#{totals[:download_failed]} logo download failed."
  end

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
