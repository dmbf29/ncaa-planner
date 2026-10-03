module BigGameBreakdown
  # Decides each host's one bet per game and saves it, so the same picks come
  # back on every later request and can be graded after the game is played.
  # We can't read back what the hosts say on air, so the picks are assigned
  # here and written into the script for them to argue.
  #
  # The first request for a game locks its lines and picks (picks are
  # idempotent after that, so re-generating the script never changes a bet).
  # A game that has already been played is never given picks. Everything is
  # seeded off the game's id, so the assignment is stable and reproducible.
  class PickLocker
    # How far (in points) the projected total has to sit from the league
    # average before a game is bet as a total instead of against the spread:
    # a shootout or a slugfest is a total game, the rest are spread games.
    TOTAL_MARKET_EDGE = 7.0

    # Chance the second host takes the other side from the first (they
    # disagree on most games, because that's the fun part).
    DISAGREEMENT_RATE = 0.7

    def initialize(hosts: PodcastShow.host_first_names)
      @hosts = hosts
    end

    # `lines` is the LineMaker result for the game. Returns the game's picks
    # (existing ones if already locked), or [] for a game already played.
    def call(game, lines)
      existing = GamePick.where(game_id: game.id).order(:id).to_a
      return existing if existing.any? || game.played?

      create_picks(game, lines)
    rescue ActiveRecord::RecordNotUnique
      GamePick.where(game_id: game.id).order(:id).to_a
    end

    private

    def create_picks(game, lines)
      rng = Random.new(game.id)
      market = lines[:total_edge].abs >= TOTAL_MARKET_EDGE ? "total" : "spread"
      first_side = (market == "total" ? %w[over under] : %w[home away]).sample(random: rng)
      second_side = rng.rand < DISAGREEMENT_RATE ? opposite(first_side) : first_side
      sides = [ first_side, second_side ]

      GamePick.transaction do
        @hosts.each_with_index.map do |host, index|
          GamePick.create!(game: game, host: host, market: market, side: sides.fetch(index),
                           spread_line: lines[:spread], total_line: lines[:total])
        end
      end
    end

    def opposite(side)
      { "home" => "away", "away" => "home", "over" => "under", "under" => "over" }.fetch(side)
    end
  end
end
