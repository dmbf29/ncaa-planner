# A team the commissioner registered as a possible non-conference opponent for one of a coached team's open weeks.
# `suggested` options came off the schedule screenshot (an opponent shown on an unlocked row); the rest come from
# recording the in-game opponent picker. `rank` is the opponent's poll rank at capture time, nil if unranked.
class ScheduleOption < ApplicationRecord
  belongs_to :college_season
  belongs_to :week
  belongs_to :opponent_college, class_name: "College"

  validates :opponent_college_id, uniqueness: { scope: %i[college_season_id week_id] }
end
