class SquadPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.joins(:team).where(teams: { user_id: @user.id })
    end
  end
end
