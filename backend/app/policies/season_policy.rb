class SeasonPolicy < ApplicationPolicy
  def show?
    record.dynasty.user == user
  end

  def create?
    record.dynasty.user == user
  end
end
