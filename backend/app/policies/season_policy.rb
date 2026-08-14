class SeasonPolicy < ApplicationPolicy
  def show?
    owner?
  end

  def create?
    owner?
  end

  def analyze_schedule?
    owner?
  end

  def commit_schedule?
    owner?
  end

  def analyze_all_americans?
    owner?
  end

  def commit_all_americans?
    owner?
  end

  def analyze_nil_spend?
    owner?
  end

  def commit_nil_spend?
    owner?
  end

  def analyze_conference_standings?
    owner?
  end

  def commit_conference_standings?
    owner?
  end

  def analyze_players_of_the_week?
    owner?
  end

  def commit_players_of_the_week?
    owner?
  end

  def analyze_team_schedule?
    owner?
  end

  def commit_team_schedule?
    owner?
  end

  def owner?
    record.dynasty.user == user
  end
end
