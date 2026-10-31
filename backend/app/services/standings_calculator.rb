# Records and points for a season's teams, worked out from the games that have been played (both sides have a
# final score) rather than from a separate standings upload.
#
# Overall record and points count every played game, bowls and the conference title game included; the home
# record skips those (neutral sites).
# Conference record and points count only regular-season games between two teams in the same conference (the
# title game is not a conference game, as in a real standings table). A conference is the one on each team's
# CollegeSeason, so a placeholder FCS opponent never counts as a conference game.
#
# `through_week_number` limits it to games up to and including that week, for a recap of an earlier week.
class StandingsCalculator
  EMPTY = {
    wins: 0, losses: 0, conference_wins: 0, conference_losses: 0,
    points_for: 0, points_against: 0, conference_points_for: 0, conference_points_against: 0,
    home_wins: 0, home_losses: 0
  }.freeze

  # Rewrites the stored standings columns on the two teams of a game whose score just changed. The overall
  # record is never lowered below what an older screenshot (Top 25, team schedule) already recorded, since
  # those can cover games that were never entered here.
  def self.refresh(season, college_ids)
    calculator = new(season, college_ids: college_ids)
    season.college_seasons.where(college_id: college_ids).find_each do |college_season|
      record = calculator.record_for(college_season.college_id)
      next if record == EMPTY

      attrs = record.except(:wins, :losses, :home_wins, :home_losses)
      attrs.merge!(record.slice(:wins, :losses, :home_wins, :home_losses)) if record[:wins] + record[:losses] >= college_season.wins.to_i + college_season.losses.to_i
      college_season.update_columns(attrs)
    end
  end

  def initialize(season, college_ids: nil, through_week_number: nil)
    @season = season
    @college_ids = college_ids
    @through_week_number = through_week_number
  end

  def record_for(college_id)
    records.fetch(college_id, EMPTY)
  end

  private

  def records
    @records ||= begin
      totals = Hash.new { |hash, id| hash[id] = EMPTY.dup }
      played_games.each do |game|
        scores = game.college_game_stats.to_h { |stat| [ stat.college_id, stat.final_score ] }
        next unless scores[game.home_college_id] && scores[game.away_college_id]

        conference_game = conference_game?(game)
        neutral_site = game.week.post_season || game.week.conference_championship
        [ [ game.home_college_id, game.away_college_id, true ], [ game.away_college_id, game.home_college_id, false ] ].each do |id, opponent_id, home|
          next if @college_ids && @college_ids.exclude?(id)

          add(totals[id], scores[id], scores[opponent_id], home: home && !neutral_site, conference_game: conference_game)
        end
      end
      totals
    end
  end

  def add(total, scored, allowed, home:, conference_game:)
    won = scored > allowed
    total[won ? :wins : :losses] += 1
    total[won ? :home_wins : :home_losses] += 1 if home
    total[:points_for] += scored
    total[:points_against] += allowed
    return unless conference_game

    total[won ? :conference_wins : :conference_losses] += 1
    total[:conference_points_for] += scored
    total[:conference_points_against] += allowed
  end

  def conference_game?(game)
    week = game.week
    return false if week.post_season || week.conference_championship

    conference = conferences[game.home_college_id]
    conference.present? && conference == conferences[game.away_college_id]
  end

  def conferences
    @conferences ||= @season.college_seasons.pluck(:college_id, :conference).to_h
  end

  def played_games
    scope = Game.joins(:week).where(weeks: { season_id: @season.id }).includes(:week, :college_game_stats)
    scope = scope.where(weeks: { number: ..@through_week_number }) if @through_week_number
    scope = scope.where(home_college_id: @college_ids).or(scope.where(away_college_id: @college_ids)) if @college_ids
    scope
  end
end
