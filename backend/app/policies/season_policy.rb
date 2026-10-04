class SeasonPolicy < ApplicationPolicy
  def show?
    owner?
  end

  def create?
    owner?
  end

  def destroy?
    owner?
  end

  def analyze_schedule?
    owner?
  end

  def analyze_schedule_status?
    owner?
  end

  def commit_schedule?
    owner?
  end

  def analyze_all_americans?
    owner?
  end

  def commit_all_americans?
    owner?
  end

  def analyze_nil_spend?
    owner?
  end

  def commit_nil_spend?
    owner?
  end

  def analyze_conference_standings?
    owner?
  end

  def commit_conference_standings?
    owner?
  end

  def team_attributes?
    owner?
  end

  def analyze_team_stats?
    owner?
  end

  def commit_team_stats?
    owner?
  end

  def analyze_recruiting?
    owner?
  end

  def commit_recruiting?
    owner?
  end

  def analyze_recruitment_trail?
    owner?
  end

  def commit_recruitment_trail?
    owner?
  end

  def signed_recruit_overalls?
    owner?
  end

  def commit_signed_recruit_overalls?
    owner?
  end

  def analyze_players_of_the_week?
    owner?
  end

  def commit_players_of_the_week?
    owner?
  end

  def analyze_team_schedule?
    owner?
  end

  def commit_team_schedule?
    owner?
  end

  def start_roster_video?
    owner?
  end

  def roster_video_status?
    owner?
  end

  def start_team_builder_export?
    owner?
  end

  def team_builder_export_status?
    owner?
  end

  def analyze_roster_import?
    owner?
  end

  def commit_roster_import?
    owner?
  end

  def search_previous_students?
    owner?
  end

  def analyze_portal_preview?
    owner?
  end

  def commit_portal_preview?
    owner?
  end

  def portal_statuses?
    owner?
  end

  def coach_assignments?
    owner?
  end

  def commit_coach_assignments?
    owner?
  end

  def coach_info?
    owner?
  end

  def award_winners?
    owner?
  end

  def commit_award_winners?
    owner?
  end

  def owner?
    record.dynasty.user == user
  end
end
