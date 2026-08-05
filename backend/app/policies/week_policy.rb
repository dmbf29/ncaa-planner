class WeekPolicy < ApplicationPolicy
  def analyze_top_25_rankings?
    owner?
  end

  def commit_top_25_rankings?
    owner?
  end

  def owner?
    record.season.dynasty.user == user
  end
end
