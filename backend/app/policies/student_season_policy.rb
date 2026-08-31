class StudentSeasonPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.joins(college_season: { season: :dynasty }).where(dynasties: { user_id: @user.id })
    end
  end

  def owner?
    record.college_season.season.dynasty.user == user
  end
end
