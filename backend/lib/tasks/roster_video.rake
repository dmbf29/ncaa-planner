require "open3"

namespace :roster_import do
  desc "Import every roster recording in DIR (default video_test/) via tools/roster_video " \
       "(SEASON_ID, default latest; APPLY=1 to write, otherwise a dry run; with APPLY=1 REPAIR_LINKS=1 also fixes probable wrong links)"
  task from_videos: :environment do
    abort "Roster video import only runs in development" unless Rails.env.development?

    season = ENV["SEASON_ID"] ? Season.find(ENV["SEASON_ID"]) : Season.order(:year).last
    dir = Pathname(ENV.fetch("DIR") { Rails.root.join("video_test").to_s })
    apply = ENV["APPLY"] == "1"
    repair_links = ENV["REPAIR_LINKS"] == "1"
    clips = Dir[dir.join("*.{mov,mp4,m4v}")].sort
    abort "No videos found in #{dir}" if clips.empty?

    puts "#{apply ? 'APPLYING' : 'DRY RUN'} for the #{season.year} season (season #{season.id}, dynasty #{season.dynasty_id}); #{clips.size} videos in #{dir}"
    puts

    # Extractions are cached by file + extractor version, so the APPLY run after a dry run doesn't redo the OCR.
    cache_dir = Rails.root.join("tmp/roster_video/cache")
    FileUtils.mkdir_p(cache_dir)
    extractor = RosterVideoJob::TOOL_DIR.join("extract.py")
    # Keyed on the extractor's OUTPUT_VERSION (not its edit time), so only changes that alter what it outputs re-read clips.
    output_version = File.read(extractor)[/^OUTPUT_VERSION = (\d+)/, 1]
    abort "Roster video tool isn't set up (no Python at #{RosterVideoJob::PYTHON}); see tools/roster_video/README.md" unless File.executable?(RosterVideoJob::PYTHON)

    extract = lambda do |path|
      cache = cache_dir.join("#{File.basename(path)}-#{File.mtime(path).to_i}-v#{output_version}.json")
      next JSON.parse(File.read(cache)) if cache.exist?

      out, err, status = Open3.capture3(RosterVideoJob::PYTHON, extractor.to_s, path)
      raise "extractor failed: #{err.lines.grep_v(/\Aprogress/).last(3).join.strip}" unless status.success?

      File.write(cache, out)
      JSON.parse(out)
    end

    # Each clip's OCR already uses several cores, so two at a time keeps the machine busy without thrashing it.
    $stdout.sync = true
    at_once = Integer(ENV.fetch("CLIPS_AT_ONCE", 2))
    pending = Queue.new
    clips.each { |path| pending << path }
    outcomes = {}
    lock = Mutex.new
    Array.new(at_once) do
      Thread.new do
        loop do
          path = begin
            pending.pop(true)
          rescue ThreadError
            break
          end
          outcome = begin
            extract.call(path)
          rescue StandardError => e
            e
          end
          lock.synchronize do
            outcomes[path] = outcome
            puts "  read #{outcomes.size}/#{clips.size}" if (outcomes.size % 10).zero?
          end
        end
      end
    end.each(&:join)

    resolver = RosterVideo::TeamResolver.new
    extracted = clips.each_with_index.filter_map do |path, index|
      name = File.basename(path)
      begin
        result = outcomes.fetch(path)
        raise result if result.is_a?(StandardError)

        college = resolver.call(result["team"])
        puts format("[%2d/%d] %-34s team %-22s -> %s", index + 1, clips.size, name, result["team"].inspect, college&.name || "UNRECOGNIZED")
        { path: path, name: name, result: result, college: college }
      rescue StandardError => e
        puts format("[%2d/%d] %-34s FAILED: %s", index + 1, clips.size, name, e.message)
        { path: path, name: name, error: e.message }
      end
    end
    puts

    short_clip_floor = lambda do |college|
      existing = season.college_seasons.find_by(college_id: college.id)&.student_seasons&.count.to_i
      existing.positive? ? (existing * 0.8).floor : 20
    end

    report = { season_id: season.id, applied: apply, teams: [], skipped_clips: [] }
    usable = []
    extracted.each do |clip|
      if clip[:error]
        report[:skipped_clips] << { file: clip[:name], reason: clip[:error] }
      elsif clip[:college].nil?
        report[:skipped_clips] << { file: clip[:name], reason: "team name #{clip[:result]['team'].inspect} not recognized" }
      elsif (read = clip[:result]["players"].size) < (floor = short_clip_floor.call(clip[:college]))
        # A recording that stopped early. Rosters vary (user-controlled teams are not filled to 85), so "short" is
        # judged against the roster already in the DB, not a fixed number.
        report[:skipped_clips] << { file: clip[:name], reason: "only #{read} players read (expected at least #{floor})" }
      else
        usable << clip
      end
    end

    usable.group_by { |clip| clip[:college].id }.each_value do |group|
      newest = group.max_by { |clip| File.mtime(clip[:path]) }
      (group - [ newest ]).each { |clip| report[:skipped_clips] << { file: clip[:name], reason: "duplicate of #{newest[:name]} (older, ignored)" } }
    end
    chosen = usable.group_by { |clip| clip[:college].id }.values.map { |group| group.max_by { |clip| File.mtime(clip[:path]) } }

    fields = %w[class_year position overall speed acceleration agility change_of_direction strength awareness]
    totals = Hash.new(0)

    chosen.sort_by { |clip| clip[:college].name }.each do |clip|
      college = clip[:college]
      college_season = season.college_seasons.find_by(college_id: college.id)
      unless college_season
        report[:skipped_clips] << { file: clip[:name], reason: "#{college.name} has no #{season.year} college season" }
        next
      end

      players = clip[:result]["players"]
      analyzed = RosterImport::Analyzer.new(college_season).call(players)
      analyzed.each { |row| row[:needs_review] = Array(row[:needs_review]) + [ "unknown position #{row[:position].inspect}" ] unless PositionBoardMapping.known?(row[:position]) }
      # Same-named players across schools: when exactly one candidate plays the row's position, it is that player
      # (e.g. a WR matches last year's WR, not a same-named LE at another school). Anything less clear stays ambiguous.
      auto_resolved = []
      analyzed.each do |row|
        next unless row[:status] == "ambiguous" && row[:needs_review].blank?

        same_position = row[:candidates].select { |c| PositionBoardMapping.canonical(c[:position]) == PositionBoardMapping.canonical(row[:position]) }
        next unless same_position.size == 1

        pick = same_position.first
        row.merge!(status: "match", student_id: pick[:student_id], matched_name: pick[:name], matched_college: pick[:college])
        auto_resolved << "#{row[:first_name]} #{row[:last_name]} (#{row[:position]} #{row[:class_year]}) -> #{pick[:college]} #{pick[:position]} #{pick[:class_year]} #{pick[:overall]}, " \
                         "ruled out #{(row[:candidates].size - 1)} same-named player(s) at other positions"
      end
      flagged = analyzed.select { |row| row[:needs_review].present? }
      ambiguous = analyzed.select { |row| row[:needs_review].blank? && row[:status] == "ambiguous" }
      # A "new" row that is really an existing player stored under the wrong Student must not be written as new (it
      # would duplicate them); it is reported, and repaired only on request.
      link_audit = RosterVideo::LinkAudit.new(college_season)
      wrong_links = link_audit.call(analyzed.select { |row| row[:needs_review].blank? })
      # The reverse problem: the player is matched fine, but the roster ALSO holds them under another name/Student.
      duplicate_cleanup = RosterVideo::DuplicateCleanup.new(college_season)
      duplicates = duplicate_cleanup.call(analyzed.select { |row| row[:needs_review].blank? })
      writable = analyzed.select { |row| row[:needs_review].blank? && row[:status] != "ambiguous" && wrong_links.none? { |finding| finding.row.equal?(row) } }

      existing = college_season.student_seasons.index_by(&:student_id)
      changes = []
      added = 0
      writable.each do |row|
        student_season = row[:status] == "match" && existing[row[:student_id]]
        if student_season
          fields.each do |field|
            new_value = row[field.to_sym].presence
            new_value = new_value.to_i if new_value && !%w[class_year position].include?(field)
            old_value = student_season.public_send(field)
            changes << "#{row[:first_name]} #{row[:last_name]} #{field} #{old_value.inspect}->#{new_value.inspect}" if old_value != new_value
          end
        else
          added += 1
        end
      end

      # Players the highlight skipped while scrolling: visible in the table, so we know their initial, last name, class,
      # position and ratings, but never saw their pane (full first name). Fine if the roster already has them.
      skipped_report = Array(clip[:result]["skipped"]).map do |s|
        known = existing.values.find do |ss|
          ss.student.first_name.to_s[0]&.casecmp?(s["first_initial"].to_s[0].to_s) && StringDistance.similar_name?(ss.student.last_name, s["last_name"]) &&
            PositionBoardMapping.canonical(ss.position) == PositionBoardMapping.canonical(s["position"]) &&
            ss.class_year == RosterImport::Matcher.normalize_class_year(s["class_year"]) && ss.overall == s["overall"].to_i
        end
        { entry: s, on_roster_as: known&.student&.name }
      end

      commit_rows = writable.map do |row|
        next row unless row[:status] == "new"

        row.merge(first_name: row[:suggested_first_name].presence || row[:first_name], last_name: row[:suggested_last_name].presence || row[:last_name])
      end
      warnings = apply ? RosterImport::CommitService.new(college_season).call(commit_rows) : []
      repaired = 0
      cleaned = 0
      if apply && repair_links
        wrong_links.select(&:repairable).each do |finding|
          link_audit.repair!(finding)
          repaired += 1
        end
        duplicates.reject(&:manual_reason).each do |finding|
          duplicate_cleanup.repair!(finding)
          cleaned += 1
        end
      end

      counts = analyzed.group_by { |row| row[:status] }.transform_values(&:size)
      puts format("%-20s %2d players: %2d match, %2d new | %3d cell changes, %2d added to roster | skipped: %d ambiguous, %d reader-flagged, %d wrong links, %d duplicates%s",
                  college.name, players.size, counts["match"].to_i, counts["new"].to_i, changes.size, added, ambiguous.size, flagged.size,
                  wrong_links.size, duplicates.size, warnings.any? ? " | #{warnings.size} WARNINGS" : "")
      skipped_report.each do |item|
        s = item[:entry]
        label = "#{s['row_name']} #{s['position']} #{s['class_year']} #{s['overall']}"
        puts item[:on_roster_as] ? "    -- skipped by the highlight, already on the roster: #{label} (as #{item[:on_roster_as]})" :
                                    "    -- SKIPPED BY THE HIGHLIGHT AND NOT ON THE ROSTER: #{label} (no full first name in the video)"
      end
      duplicates.each do |finding|
        status = cleaned.positive? && !finding.manual_reason ? "REMOVED" : (finding.manual_reason ? "NEEDS MANUAL FIX (#{finding.manual_reason})" : "removable")
        puts "    ## duplicate [#{status}]: #{finding.describe}"
      end
      wrong_links.each do |finding|
        status = repaired.positive? && finding.repairable ? "REPAIRED" : (finding.repairable ? "repairable" : "NEEDS MANUAL FIX (signed-recruit records)")
        puts "    ~~ probable wrong link [#{status}]: #{finding.describe}"
      end
      changes.first(6).each { |change| puts "    ~ #{change}" }
      puts "    ... and #{changes.size - 6} more" if changes.size > 6
      auto_resolved.each { |line| puts "    = resolved by position: #{line}" }
      ambiguous.each { |row| puts "    ? ambiguous, not written: #{row[:first_name]} #{row[:last_name]} (#{row[:position]} #{row[:class_year]})" }
      flagged.each { |row| puts "    ! reader unsure, not written: #{row[:first_name]} #{row[:last_name]} #{row[:needs_review]}" }
      warnings.each { |warning| puts "    WARNING #{warning[:player]}: #{warning[:error]}" }

      totals[:teams] += 1
      totals[:players] += players.size
      totals[:match] += counts["match"].to_i
      totals[:new] += counts["new"].to_i
      totals[:changes] += changes.size
      totals[:wrong_links] += wrong_links.size
      totals[:duplicates] += duplicates.size
      totals[:skipped_missing] += skipped_report.count { |item| item[:on_roster_as].nil? }
      totals[:ambiguous] += ambiguous.size
      totals[:flagged] += flagged.size
      totals[:warnings] += warnings.size
      report[:teams] << { college: college.name, file: clip[:name], players: players.size, counts: counts, cell_changes: changes,
                          added_to_roster: added, ambiguous: ambiguous.map { |r| r.slice(:first_name, :last_name, :position, :class_year, :candidates) },
                          reader_flagged: flagged.map { |r| r.slice(:first_name, :last_name, :needs_review) }, warnings: warnings, auto_resolved: auto_resolved,
                          wrong_links: wrong_links.map { |f| { description: f.describe, repairable: f.repairable, student_season_id: f.student_season.id } },
                          duplicates: duplicates.map { |f| { description: f.describe, manual_reason: f.manual_reason, student_season_id: f.drop.id } },
                          skipped_by_highlight: skipped_report.map { |item| item[:entry].merge("on_roster_as" => item[:on_roster_as]) } }
    end

    puts
    report[:skipped_clips].each { |skipped| puts "SKIPPED #{skipped[:file]}: #{skipped[:reason]}" }
    puts format("%s %d teams, %d players: %d matched, %d new, %d cell changes; not written: %d ambiguous, %d reader-flagged; %d probable wrong links%s, %d duplicates%s; %d players the highlight skipped and the roster lacks; %d warnings",
                apply ? "Wrote" : "Would write", totals[:teams], totals[:players], totals[:match], totals[:new], totals[:changes],
                totals[:ambiguous], totals[:flagged], totals[:wrong_links], (apply && repair_links ? " (repaired)" : ""),
                totals[:duplicates], (apply && repair_links ? " (cleaned)" : ""), totals[:skipped_missing], totals[:warnings])
    puts "Re-run with APPLY=1 REPAIR_LINKS=1 to repair the wrong links and remove the duplicates." if (totals[:wrong_links] + totals[:duplicates]).positive? && !(apply && repair_links)
    path = Rails.root.join("tmp/roster_video/batch-#{apply ? 'applied' : 'dryrun'}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.json")
    File.write(path, JSON.pretty_generate(report))
    puts "Full report: #{path}"
    puts "Re-run with APPLY=1 to write." unless apply
  end

  desc "List players whose link to last season's Student looks implausible (read-only; SEASON_ID, default latest)"
  task audit_links: :environment do
    season = ENV["SEASON_ID"] ? Season.find(ENV["SEASON_ID"]) : Season.order(:year).last
    previous = season.previous_season
    abort "No season before #{season.year}" unless previous

    squad = ->(position) { PositionBoardMapping.resolve(PositionBoardMapping.canonical(position))&.dig(:squad) }
    predecessors = RosterImport::Matcher::CLASS_YEAR_PREDECESSORS
    current = StudentSeason.where(college_season_id: season.college_seasons.select(:id)).includes(:student, college_season: :college)
    last_year = StudentSeason.where(college_season_id: previous.college_seasons.select(:id)).includes(college_season: :college).index_by(&:student_id)

    linked = current.select { |ss| last_year.key?(ss.student_id) }
    suspects = linked.filter_map do |ss|
      before = last_year[ss.student_id]
      reasons = []
      reasons << "class #{before.class_year}->#{ss.class_year}" unless predecessors.fetch(ss.class_year, []).include?(before.class_year)
      if squad.call(before.position) && squad.call(ss.position) && squad.call(before.position) != squad.call(ss.position)
        reasons << "side #{squad.call(before.position)}->#{squad.call(ss.position)}"
      end
      reasons << "overall #{before.overall}->#{ss.overall}" if before.overall && ss.overall && (ss.overall - before.overall).abs > 15
      [ ss, before, reasons ] if reasons.any?
    end

    puts "#{season.year}: #{current.size} rows, #{linked.size} linked to a #{previous.year} season, #{suspects.size} implausible"
    suspects.sort_by { |ss, _, _| [ ss.college_season.college.name, ss.student.last_name ] }.each do |ss, before, reasons|
      puts format("  %-18s %-24s %s %s %s  <-  %s %s %s %s   [%s]", ss.college_season.college.name, ss.student.name, ss.position, ss.class_year, ss.overall,
                  before.college_season.college.name, before.position, before.class_year, before.overall, reasons.join("; "))
    end
    puts "Check these against a roster recording; a wrong link is repaired with roster_import:from_videos REPAIR_LINKS=1."
  end
end
