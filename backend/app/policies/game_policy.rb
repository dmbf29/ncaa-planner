class GamePolicy < ApplicationPolicy
  def show?
    owner?
  end

  def update?
    owner?
  end

  def analyze?
    owner?
  end

  def reanalyze?
    owner?
  end

  def analyze_status?
    owner?
  end

  def analyze_narrative?
    owner?
  end

  def commit?
    owner?
  end

  def capture_start?
    owner?
  end

  def capture_status?
    owner?
  end

  def capture_finish?
    owner?
  end

  def capture_cancel?
    owner?
  end

  def capture_mute?
    owner?
  end

  def scoring_recordings?
    owner?
  end

  def attach_scoring_summary?
    owner?
  end

  def detach_scoring_summary?
    owner?
  end

  def owner?
    record.week.season.dynasty.user == user
  end
end
