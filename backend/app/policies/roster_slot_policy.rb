class RosterSlotPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.joins(position_board: :team).where(teams: { user_id: @user.id })
    end
  end
end
