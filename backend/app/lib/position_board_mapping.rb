# Maps a scraped/screenshot position abbreviation to the {squad:, board:} it belongs
# on. Shared by ScrapePlayersJob (initial roster import) and RosterUpdates::Extractor
# (seasonal batch update from screenshots) so both features resolve position codes
# identically instead of drifting apart.
module PositionBoardMapping
  MAP = {
    "QB" => { squad: "Offense", board: "QB" },
    "HB" => { squad: "Offense", board: "HB" },
    "FB" => { squad: "Offense", board: "HB" },
    "WR" => { squad: "Offense", board: "WR" },
    "TE" => { squad: "Offense", board: "TE" },
    "LT" => { squad: "Offense", board: "LT" },
    "LG" => { squad: "Offense", board: "LG" },
    "C" => { squad: "Offense", board: "C" },
    "RG" => { squad: "Offense", board: "RG" },
    "RT" => { squad: "Offense", board: "RT" },
    "LE" => { squad: "Defense", board: "LE" },
    "RE" => { squad: "Defense", board: "RE" },
    "DT" => { squad: "Defense", board: "DT" },
    "MLB" => { squad: "Defense", board: "MIKE" },
    "LOLB" => { squad: "Defense", board: "SAM" },
    "ROLB" => { squad: "Defense", board: "WILL" },
    "CB" => { squad: "Defense", board: "CB" },
    "FS" => { squad: "Defense", board: "FS" },
    "SS" => { squad: "Defense", board: "SS" },
    "K" => { squad: "Offense", board: "K" },
    "P" => { squad: "Offense", board: "P" }
  }.freeze

  # Broader than MAP's keys — used only to guess which squad an unrecognized
  # position code belongs to, so callers can fall back to a squad's "OTHER" board
  # instead of leaving the position unresolved entirely.
  OFFENSE_CODES = %w[QB HB RB FB WR TE OL OT OG LT RT LG RG C].freeze
  DEFENSE_CODES = %w[DE DT NT DL OLB ILB LB MLB LOLB ROLB MIKE SAM WILL LE RE CB DB S FS SS NB NICKEL].freeze

  module_function

  # Returns {squad:, board:} for a known code, a guessed {squad:, board: "OTHER"}
  # for an unrecognized-but-classifiable code, or nil if the squad can't be guessed.
  def resolve(position_code)
    MAP[position_code] || fallback(position_code)
  end

  def guess_squad(position_code)
    return "Offense" if OFFENSE_CODES.include?(position_code)
    return "Defense" if DEFENSE_CODES.include?(position_code)

    nil
  end

  def fallback(position_code)
    squad_name = guess_squad(position_code)
    return nil if squad_name.blank?

    { squad: squad_name, board: "OTHER" }
  end
end
