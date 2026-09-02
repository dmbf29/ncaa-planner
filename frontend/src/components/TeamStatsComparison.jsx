import { clsx } from "clsx";
import Card from "./Card";

// The same team stats the weekly-review broadcast reports, lined up so the
// coached teams can be compared at a glance. Most are per-game averages
// (TeamSeasonStats#team_stats); third-down % and turnovers are season
// totals (TeamSeasonStats#team_totals) — `source` picks the bucket. Stats
// that read better low are flagged per row so a long bar isn't misread.
const STATS = [
  { key: "passingOffense", label: "Pass Off", unit: "yds", lowerIsBetter: false, source: "stats" },
  { key: "rushingOffense", label: "Rush Off", unit: "yds", lowerIsBetter: false, source: "stats" },
  { key: "pointsPerGame", label: "Points", unit: "pts", lowerIsBetter: false, source: "stats" },
  { key: "thirdDownPercentage", label: "3rd Down", unit: "%", lowerIsBetter: false, source: "totals" },
  { key: "turnovers", label: "Turnovers", unit: "", lowerIsBetter: true, source: "totals" },
  { key: "passingDefense", label: "Pass Def", unit: "yds", lowerIsBetter: true, source: "stats" },
  { key: "rushingDefense", label: "Rush Def", unit: "yds", lowerIsBetter: true, source: "stats" },
  { key: "pointsAgainstPerGame", label: "Points Allowed", unit: "pts", lowerIsBetter: true, source: "stats" },
];

const statValue = (team, stat) =>
  (stat.source === "totals" ? team.teamTotals : team.teamStats)?.[stat.key];

function StatRow({ stat, teams }) {
  const values = teams.map((team) => statValue(team, stat)).filter((v) => v != null);
  if (values.length === 0) return null;

  const max = Math.max(...values);
  const best = stat.lowerIsBetter ? Math.min(...values) : Math.max(...values);
  const showBest = values.length > 1;

  return (
    <div className="space-y-1 px-4 py-2.5">
      <div className="flex items-center justify-between text-xs">
        <span className="font-semibold uppercase tracking-wide text-textSecondary">{stat.label}</span>
        <span className="text-[10px] text-textSecondary/70">
          {[stat.source === "totals" && "season total", stat.lowerIsBetter && "↓ lower is better"]
            .filter(Boolean)
            .join(" · ")}
        </span>
      </div>
      <div className="space-y-1">
        {teams.map((team) => {
          const value = statValue(team, stat);
          const width = value != null && max > 0 ? Math.max(2, Math.round((value / max) * 100)) : 0;
          const isBest = showBest && value != null && value === best;

          return (
            <div key={team.id} className="flex items-center gap-2 text-xs">
              <span className="w-20 shrink-0 truncate text-textSecondary" title={team.college.name}>
                {team.college.alternateName || team.college.name}
              </span>
              <div className="h-2 flex-1 overflow-hidden rounded-full bg-charcoal/10 dark:bg-white/10">
                <div
                  className={clsx("h-full rounded-full", isBest ? "bg-burnt" : "bg-charcoal/40 dark:bg-white/30")}
                  style={{ width: `${width}%` }}
                />
              </div>
              <span
                className={clsx(
                  "w-14 shrink-0 text-right font-semibold text-nowrap",
                  isBest ? "text-burnt" : "text-textPrimary dark:text-white",
                )}
              >
                {value != null ? value : "—"}
                {stat.unit && <span className="font-light text-textSecondary"> {stat.unit}</span>}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function TeamStatsComparison({ teams }) {
  const played = (teams || []).filter((team) => team.teamStats);

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Team Stats</h3>
      </div>
      {played.length > 0 ? (
        <div className="divide-y divide-border dark:divide-darkborder">
          {STATS.map((stat) => (
            <StatRow key={stat.key} stat={stat} teams={played} />
          ))}
        </div>
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No games played yet this season.</p>
      )}
    </Card>
  );
}

export default TeamStatsComparison;
