class WeekPolicy < ApplicationPolicy
  def analyze_top_25_rankings?
    owner?
  end

  def commit_top_25_rankings?
    owner?
  end

  def analyze_heisman_candidates?
    owner?
  end

  def commit_heisman_candidates?
    owner?
  end

  def analyze_bowl_projections?
    owner?
  end

  def commit_bowl_projections?
    owner?
  end

  def owner?
    record.season.dynasty.user == user
  end
end
