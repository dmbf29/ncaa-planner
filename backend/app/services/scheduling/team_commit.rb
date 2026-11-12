module Scheduling
  # Saves a (possibly hand-corrected) team-schedule reading: locked games become real Games (and locked OPENs real
  # byes) through TeamSchedule::CommitService, the weeks a coach may still choose are remembered, and any opponent the
  # screenshot showed on an unlocked week is registered as that week's first possible opponent.
  class TeamCommit
    def initialize(college_season)
      @college_season = college_season
      @season = college_season.season
    end

    def call(rows)
      rows = Array(rows).map { |row| row.to_h.deep_symbolize_keys }
      locked = rows.select { |row| %w[locked bye].include?(row[:state]) }

      warnings = TeamSchedule::CommitService.new(@college_season).call({}, locked.map { |row| commit_row(row) })
      save_setup(rows, failed_weeks: warnings.map { |warning| warning[:week_label] })
      warnings
    end

    private

    def commit_row(row)
      { week_id: row[:week_id], is_bye: row[:state] == "bye", opponent_college_id: row[:opponent_college_id], is_away: row[:is_away], week_label: row[:week_number].to_s }
    end

    def save_setup(rows, failed_weeks:)
      saved = rows.select { |row| row[:state] == "locked" && row[:opponent_college_id] && failed_weeks.exclude?(row[:week_number].to_s) }
      locked_week_ids = saved.map { |row| row[:week_id] }

      ActiveRecord::Base.transaction do
        @college_season.schedule_options.where(suggested: true).destroy_all
        rows.select { |row| row[:state] == "option" && row[:opponent_college_id] }.each do |row|
          option = @college_season.schedule_options.find_or_initialize_by(week_id: row[:week_id], opponent_college_id: row[:opponent_college_id])
          option.update!(suggested: true)
        end
        @college_season.update!(
          schedule_locked_week_ids: locked_week_ids, schedule_uploaded_at: Time.current,
          schedule_token: @college_season.schedule_token || SecureRandom.urlsafe_base64(16)
        )
      end
    end
  end
end
