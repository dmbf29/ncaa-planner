class GamePolicy < ApplicationPolicy
  def show?
    owner?
  end

  def analyze?
    owner?
  end

  def commit?
    owner?
  end

  def owner?
    record.week.season.dynasty.user == user
  end
end
