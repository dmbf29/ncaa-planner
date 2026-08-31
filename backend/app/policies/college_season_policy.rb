class CollegeSeasonPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.joins(season: :dynasty).where(dynasties: { user_id: @user.id })
    end
  end

  def owner?
    record.season.dynasty.user == user
  end
end
