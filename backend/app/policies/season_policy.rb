class SeasonPolicy < ApplicationPolicy
  def show?
    record.dynasty.user == user
  end
end
