module DynastyRewired
  # Dynasty Rewired stat code => our column. Each pairing was checked against the box scores already
  # saved by hand (31 games, ~3,000 values): all match except the three noted below. Defense blocks,
  # safeties and touchdowns are almost always 0, so their codes are tied with others in that data
  # and are only a best guess until one of them is non-zero in a game we've saved.
  module StatMap
    COLLEGE = {
      first_downs: "OFFD", total_offense: "OFYD", total_plays: "PLAY", yards_per_play: "OYPP",
      rushes: "ORUS", rushing_yards: "OFRY", rushing_tds: "OFTD", yards_per_rush: "YPRU",
      passing_completions: "COMP", passing_attempts: "PSAT", passing_tds: "PSTD", yards_per_pass: "YPPA", passing_yards: "OFPY",
      third_down_conversions: "THRD", third_down_attempts: "THDD",
      fourth_down_conversions: "FRTH", fourth_down_attempts: "FTHD",
      two_point_conversions: "TWOP", two_point_attempts: "TWPA",
      red_zone_tds: "RDTD", red_zone_field_goals: "FDFG", red_zone_success_percentage: "REDP",
      turnovers: "TURN", fumbles_lost: "FUMB", interceptions_thrown: "INTC",
      punt_return_yards: "PRYD", kick_return_yards: "KRYD",
      total_yards: "YARD", # 2 of 62 saved games differ
      punts: "TPUN", penalties: "PNLT", penalty_yards: "PNTY", time_of_possession: "PSSC",
      points_in_quarter_1: "SCR1", points_in_quarter_2: "SCR2", points_in_quarter_3: "SCR3", points_in_quarter_4: "SCR4",
      points_in_overtime: "SCRO", final_score: "SCOR"
    }.freeze

    PLAYER = {
      passing_rating: "PSPR", passing_yards: "PSPY", passing_tds: "PSPT", passing_interceptions: "PSPI",
      passing_longest: "PSPL", passing_sacks_taken: "PSPS", passing_completions: "PSPC",
      passing_attempts: "PSPA", passing_avg: "PPCP",
      rushing_carries: "PSRA", rushing_yards: "PSRY", rushing_avg: "PSRV", rushing_tds: "PSRT",
      rushing_fumbles: "PSRF", rushing_yac: "PSAF", rushing_longest: "PSRL", # 1 of 223 saved lines differs
      receiving_receptions: "PRRT", receiving_yards: "PRYD", receiving_avg: "PRAV", receiving_tds: "PRTD",
      receiving_rac: "PRAC", receiving_longest: "PRLR", receiving_drop: "PRDP",
      defense_solo_tackles: "PDTS", defense_assist_tackles: "PDTA", defense_tackles: "PSTT",
      defense_tfl: "PTFL", defense_sacks: "PSDS",
      defense_interceptions: "PDIT", defense_interceptions_longest: "PDRL",
      defense_interceptions_yards: "PDRY", defense_interceptions_avg: "PDRA",
      defense_deflections: "PDPD", defense_forced_fumbles: "PDFF", defense_fumble_recoveries: "PDFR",
      defense_fumble_return_yards: "PDFY",
      defense_blocks: "PSBK", defense_safeties: "PDSY", defense_touchdowns: "PDDT"
    }.freeze
  end
end
