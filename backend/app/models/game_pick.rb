# One host's single bet on a game, locked in the first time the Big Game
# Breakdown data is built for that game's week and graded later against the
# final score (see BigGameBreakdown::PickLocker). Each host makes exactly one
# bet per game, either on the spread or on the total.
#
# `spread_line` is from the home team's side: -6.5 means the home team is a
# 6.5-point favorite, +3.5 means it's a 3.5-point underdog. Lines always end
# in .5, so a bet is never a push in practice, but #result still handles it.
class GamePick < ApplicationRecord
  MARKETS = %w[spread total].freeze
  SIDES = %w[home away over under].freeze

  belongs_to :game

  validates :host, presence: true
  validates :market, inclusion: { in: MARKETS }
  validates :side, inclusion: { in: SIDES }
  validates :host, uniqueness: { scope: :game_id }

  # :win, :loss, :push, or nil while the game hasn't been played.
  def result
    home_score, away_score = final_scores
    return nil unless home_score && away_score

    margin = market == "spread" ? spread_margin(home_score, away_score) : total_margin(home_score, away_score)
    return :push if margin.zero?

    margin.positive? == backed_positive_side? ? :win : :loss
  end

  # "Ohio State -6.5", "Michigan +6.5", "Over 54.5".
  def description
    case market
    when "total" then "#{side.capitalize} #{format_line(total_line)}"
    when "spread" then side == "home" ? "#{game.home_college.name} #{signed(spread_line)}" : "#{game.away_college.name} #{signed(-spread_line)}"
    end
  end

  private

  def final_scores
    stats = game.college_game_stats
    home = stats.find { |stat| stat.college_id == game.home_college_id }
    away = stats.find { |stat| stat.college_id == game.away_college_id }
    [ home&.final_score, away&.final_score ]
  end

  # Positive when the home side covers (home score plus its line beats away).
  def spread_margin(home_score, away_score)
    (home_score - away_score) + spread_line
  end

  # Positive when the game goes over.
  def total_margin(home_score, away_score)
    (home_score + away_score) - total_line
  end

  # The pick wins when the margin has the sign of the side it backed.
  def backed_positive_side?
    %w[home over].include?(side)
  end

  def signed(value)
    value.positive? ? "+#{format_line(value)}" : format_line(value)
  end

  def format_line(value)
    value.to_f.to_s
  end
end
