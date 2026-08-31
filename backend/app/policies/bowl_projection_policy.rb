class BowlProjectionPolicy < ApplicationPolicy
  def owner?
    record.week.season.dynasty.user == user
  end

  class Scope < Scope
    def resolve
      @scope.joins(week: { season: :dynasty }).where(dynasties: { user_id: @user.id })
    end
  end
end
