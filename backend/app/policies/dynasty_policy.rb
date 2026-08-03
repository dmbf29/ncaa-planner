class DynastyPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      @scope.where(user: @user)
    end
  end

  def index?
    true
  end
end
