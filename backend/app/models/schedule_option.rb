# A team the commissioner registered as a possible non-conference opponent for one of a coached team's open weeks.
# `suggested` options came off the schedule screenshot (an opponent shown on an unlocked row); the rest come from
# recording the in-game opponent picker. `ranked` says the opponent was
# in the poll at capture time; `rank` is its number when that could be read.
class ScheduleOption < ApplicationRecord
  belongs_to :college_season
  belongs_to :week
  belongs_to :opponent_college, class_name: "College"

  validates :opponent_college_id, uniqueness: { scope: %i[college_season_id week_id] }
end
