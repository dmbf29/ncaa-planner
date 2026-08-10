class TeamPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.where(user: @user)
    end
  end

  def index?
    true
  end

  def create?
    true
  end

  def import_roster?
    owner?
  end

  def analyze_roster_update?
    owner?
  end

  def commit_roster_update?
    owner?
  end
end
