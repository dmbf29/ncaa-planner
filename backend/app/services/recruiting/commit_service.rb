module Recruiting
  # Persists a (possibly user-edited) national recruiting class rankings
  # table for one season. Purely team-level data — no Student/StudentSeason
  # involved — so each row just finds-or-creates the CollegeSeason (same
  # reasoning as NilSpend/ConferenceStandings: a freshly-started season
  # won't have one yet for anything but the coached teams) and overwrites
  # its RecruitingSeason with this upload, since a snapshot upload is meant
  # to be the definitive replacement, not a merge.
  #
  # Each row commits independently and a validation failure is caught and
  # reported as a warning rather than aborting the rest of the batch,
  # mirroring the other CommitServices.
  class CommitService
    def initialize(season)
      @season = season
    end

    def call(rows)
      Array(rows).filter_map do |row|
        symbolized = row.deep_symbolize_keys
        commit_row(symbolized)
        nil
      rescue ActiveRecord::RecordInvalid => e
        { team: symbolized[:college_raw_name], error: e.message }
      end
    end

    private

    def commit_row(row)
      college = College.find_by(id: row[:college_id])
      return if college.blank?

      college_season = CollegeSeason.find_or_create_by!(college: college, season: @season)
      recruiting_season = college_season.recruiting_season || college_season.build_recruiting_season
      recruiting_season.update!(
        ranking: row[:ranking],
        points: row[:points],
        total_signed: row[:total_signed],
        nil_spent: row[:nil_spent],
        five_stars: row[:five_stars],
        four_stars: row[:four_stars],
        three_stars: row[:three_stars],
        two_stars: row[:two_stars],
        one_stars: row[:one_stars]
      )
    end
  end
end
