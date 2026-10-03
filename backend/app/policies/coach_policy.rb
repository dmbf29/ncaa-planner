class CoachPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.joins(:dynasty).where(dynasties: { user_id: @user.id })
    end
  end

  def update?
    record.dynasty.user == user
  end
end
