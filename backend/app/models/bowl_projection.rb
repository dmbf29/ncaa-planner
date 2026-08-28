class BowlProjection < ApplicationRecord
  # A speculative matchup for a not-yet-played bowl/CFP game. `week` is the
  # week this projection was observed/captured (in practice always one of
  # the last two regular-season weeks or the conference championship week
  # — bowl projections all get revealed together in one screenshot on
  # those weeks, not spread across the post-season bowl weeks the games
  # themselves will eventually be played in), not the week the bowl game
  # itself will happen. Snapshotting per observation week keeps "what did
  # the projection look like in Week 13 vs Week 14" visible instead of one
  # row being overwritten as picks shift. Deliberately separate from Game:
  # a Game is a real scheduled/played matchup, this is a guess about what
  # a future Game might be.
  enum :cfp_round, { first_round: 0, quarterfinal: 1, semifinal: 2, championship: 3 }

  belongs_to :week
  belongs_to :projected_home_college, class_name: "College", optional: true
  belongs_to :projected_away_college, class_name: "College", optional: true

  validates :bowl_name, presence: true
end
