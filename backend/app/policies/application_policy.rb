class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    owner?
  end

  def create?
    owner?
  end

  def new?
    create?
  end

  def update?
    owner?
  end

  def edit?
    update?
  end

  def destroy?
    owner?
  end

  def owner?
    if record.respond_to?(:user)
      record.user == user
    elsif record.respond_to?(:team)
      record.team&.user == user
    elsif record.respond_to?(:position_board)
      record.position_board&.team&.user == user
    else
      false
    end
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      @scope.none
    end
  end
end
