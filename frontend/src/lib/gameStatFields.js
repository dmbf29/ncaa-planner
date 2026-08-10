export const TEAM_STAT_GROUPS = [
  { label: "Scoring", fields: ["finalScore", "pointsInQuarter1", "pointsInQuarter2", "pointsInQuarter3", "pointsInQuarter4"] },
  { label: "Offense", fields: ["firstDowns", "totalOffense", "totalPlays", "yardsPerPlay", "totalYards"] },
  { label: "Rushing", fields: ["rushes", "rushingYards", "rushingTds", "yardsPerRush"] },
  { label: "Passing", fields: ["passingCompletions", "passingAttempts", "passingTds", "passingYards", "yardsPerPass"] },
  {
    label: "Downs & 2-PT",
    fields: [
      "thirdDownConversions", "thirdDownAttempts", "fourthDownConversions", "fourthDownAttempts",
      "twoPointConversions", "twoPointAttempts",
    ],
  },
  { label: "Red Zone", fields: ["redZoneTds", "redZoneFieldGoals", "redZoneSuccessPercentage"] },
  { label: "Ball Security", fields: ["turnovers", "fumblesLost", "interceptionsThrown"] },
  { label: "Special Teams", fields: ["puntReturnYards", "kickReturnYards", "punts"] },
  { label: "Penalties & Time", fields: ["penalties", "penaltyYards", "timeOfPossession"] },
];

export const FIELD_LABELS = {
  finalScore: "Final Score", pointsInQuarter1: "Q1", pointsInQuarter2: "Q2", pointsInQuarter3: "Q3", pointsInQuarter4: "Q4",
  firstDowns: "First Downs", totalOffense: "Total Offense", totalPlays: "Total Plays", yardsPerPlay: "Yards/Play",
  totalYards: "Total Yards", rushes: "Rushes", rushingYards: "Rush Yards", rushingTds: "Rush TDs",
  yardsPerRush: "Yards/Rush", passingCompletions: "Comp", passingAttempts: "Att", passingTds: "Pass TDs",
  passingYards: "Pass Yards", yardsPerPass: "Yards/Pass", thirdDownConversions: "3rd Down Made",
  thirdDownAttempts: "3rd Down Att", fourthDownConversions: "4th Down Made", fourthDownAttempts: "4th Down Att",
  twoPointConversions: "2-PT Made", twoPointAttempts: "2-PT Att", redZoneTds: "RZ TDs", redZoneFieldGoals: "RZ FGs",
  redZoneSuccessPercentage: "RZ %", turnovers: "Turnovers", fumblesLost: "Fumbles Lost",
  interceptionsThrown: "INTs Thrown", puntReturnYards: "PR Yards", kickReturnYards: "KR Yards", punts: "Punts",
  penalties: "Penalties", penaltyYards: "Penalty Yards", timeOfPossession: "TOP (sec)",
};

export const CATEGORY_FIELDS = {
  passing: ["passingCompletions", "passingAttempts", "passingYards", "passingTds", "passingInterceptions", "passingRating", "passingLongest", "passingSacksTaken", "passingAvg"],
  rushing: ["rushingCarries", "rushingYards", "rushingAvg", "rushingTds", "rushingFumbles", "rushingYac", "rushingLongest"],
  receiving: ["receivingReceptions", "receivingYards", "receivingAvg", "receivingTds", "receivingRac", "receivingLongest", "receivingDrop"],
  defense: ["defenseSoloTackles", "defenseAssistTackles", "defenseTackles", "defenseTfl", "defenseSacks", "defenseInterceptions", "defenseInterceptionsLongest"],
};

export const PLAYER_FIELD_LABELS = {
  passingRating: "Rating", passingCompletions: "Comp", passingAttempts: "Att", passingYards: "Yards",
  passingTds: "TD", passingInterceptions: "INT", passingLongest: "Long", passingSacksTaken: "Sacks Taken",
  passingAvg: "Comp %", rushingCarries: "Car", rushingYards: "Yards", rushingAvg: "Avg", rushingTds: "TD",
  rushingFumbles: "Fumb", rushingYac: "YAC", rushingLongest: "Long", receivingReceptions: "Rec",
  receivingYards: "Yards", receivingAvg: "Avg", receivingTds: "TD", receivingRac: "RAC", receivingLongest: "Long",
  receivingDrop: "Drops", defenseSoloTackles: "Solo", defenseAssistTackles: "Assist", defenseTackles: "Tak",
  defenseTfl: "TFL", defenseSacks: "Sack", defenseInterceptions: "INT", defenseInterceptionsLongest: "INT Long",
};

export const normalizeCollegeStats = (rows, awayCollege, homeCollege) => {
  const byTeam = Object.fromEntries((rows || []).map((row) => [row.team, row]));
  return [awayCollege, homeCollege].map((college) => byTeam[college.name] || { team: college.name, fields: {} });
};

// Every valid position across CollegeSeason::POSITION_GROUPS on the backend
// — offered as a dropdown when creating a new player from an unmatched
// stat row, since position is otherwise free text with no source of truth
// to fetch from.
export const POSITIONS = ["QB", "HB", "FB", "WR", "TE", "LT", "LG", "C", "RG", "RT", "LE", "RE", "DT", "MLB", "LOLB", "ROLB", "CB", "FS", "SS", "K", "P"];

export const CLASS_YEARS = ["FR", "FR(RS)", "SO", "SO(RS)", "JR", "JR(RS)", "SR", "SR(RS)"];

// Mirrors GameStats::CommitService::DEFAULT_POSITION_BY_CATEGORY — just a
// starting guess for a newly-created player; the user can correct it.
export const DEFAULT_POSITION_BY_CATEGORY = { passing: "QB", rushing: "HB", receiving: "WR", defense: "MLB" };
