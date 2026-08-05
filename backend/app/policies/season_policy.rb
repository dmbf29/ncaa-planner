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

  def owner?
    record.dynasty.user == user
  end
end
