class InjuryPolicy < ApplicationPolicy
  def owner?
    record.student_season.college_season.season.dynasty.user == user
  end
end
