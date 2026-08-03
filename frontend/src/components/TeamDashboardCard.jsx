import { clsx } from "clsx";
import Card from "./Card";
import StatPill from "./StatPill";

function KeyPlayerRow({ player }) {
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="text-xs text-textSecondary">{player.position}</span>
        <span className="truncate   text-textPrimary dark:text-white">{player.name}</span>
      </div>
      <span className="shrink-0 rounded-full bg-charcoal/5 px-1.5 py-0.5 text-xs font-semibold dark:bg-white/10">
        {player.overall}
      </span>
    </div>
  );
}

function KeyPlayersGroup({ label, players }) {
  return (
    <div className="space-y-1">
      <p className="text-xs uppercase tracking-wide text-textSecondary">{label}</p>
      {players && players.length > 0 ? (
        <div className="space-y-1">
          {players.map((player) => (
            <KeyPlayerRow key={player.id} player={player} />
          ))}
        </div>
      ) : (
        <p className="text-sm text-textSecondary/60">—</p>
      )}
    </div>
  );
}

const positionAverageTone = (value) => {
  if (value == null) return "muted";
  if (value >= 80) return "positive";
  if (value < 70) return "danger";
  return "warning";
};

const positionAverageToneClasses = {
  muted: "bg-textSecondary/10 text-textSecondary",
  positive: "bg-success/20 text-success",
  warning: "bg-warning/20 text-warning",
  danger: "bg-danger/20 text-danger",
};

const positionGroupShortLabels = {
  Quarterbacks: "QB",
  "Running Backs": "RB",
  "Wide Receivers": "WR",
  "Tight Ends": "TE",
  "Offensive Line": "OL",
  "Defensive Line": "DL",
  Linebackers: "LB",
  Secondary: "Sec",
  "Kickers/Punters": "K/P",
};

function PositionGroupAverages({ averages }) {
  const entries = Object.entries(averages || {});
  if (!entries.length) return null;

  return (
    <div className="space-y-1">
      <p className="text-xs uppercase tracking-wide text-textSecondary">Position Averages</p>
      <div className="grid grid-cols-3 gap-1.5">
        {entries.map(([label, value]) => (
          <div
            key={label}
            title={label}
            className="flex items-center justify-between gap-1 rounded-md border border-border px-2 py-1.5 text-xs dark:border-darkborder"
          >
            <span className="text-textSecondary">{positionGroupShortLabels[label] || label}</span>
            <span
              className={clsx(
                "shrink-0 rounded-full px-2 py-0.5 font-bold",
                positionAverageToneClasses[positionAverageTone(value)],
              )}
            >
              {value ?? "—"}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function PrestigeStars({ value }) {
  if (value == null) return null;

  const rounded = Math.round(value * 2) / 2;
  const stars = [];
  for (let i = 1; i <= 5; i += 1) {
    const icon = rounded >= i ? "fa-solid fa-star" : rounded >= i - 0.5 ? "fa-solid fa-star-half-stroke" : "fa-regular fa-star";
    stars.push(<i key={i} className={clsx(icon, "text-[11px] text-burnt")} />);
  }

  return (
    <span className="inline-flex items-center gap-0.5" title={`Prestige: ${value}`}>
      {stars}
    </span>
  );
}

function ScheduleRow({ week }) {
  const isSpecialWeek = week.conferenceChampionship || week.postSeason;
  const label = week.conferenceChampionship
    ? "Conf. Champ"
    : week.postSeason
      ? week.name || "Bowl"
      : `Wk ${week.number}`;

  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1 text-xs last:border-0 dark:border-darkborder/60">
      <span className="w-20 shrink-0 text-textSecondary">{label}</span>
      {week.opponent ? (
        <span className="flex min-w-0 flex-1 items-center gap-1 truncate">
          <span className="text-textSecondary">{week.opponent.home ? "vs" : "@"}</span>{" "}
          <span className="truncate text-textPrimary dark:text-white">{week.opponent.name}</span>
          {week.opponent.userCoached ? (
            <i className="fa-solid fa-gamepad shrink-0 text-[11px] text-burnt/80" title="User-coached opponent" />
          ) : null}
        </span>
      ) : (
        <span className="flex-1 italic text-textSecondary/60">{isSpecialWeek ? "TBD" : "Bye"}</span>
      )}
      {week.result ? (
        <span
          className={clsx(
            "shrink-0 rounded-full px-2 py-0.5 font-semibold",
            week.result.won ? "bg-success/15 text-success" : "bg-danger/15 text-danger",
          )}
        >
          {week.result.won ? "W" : "L"} {week.result.teamScore}-{week.result.opponentScore}
        </span>
      ) : week.opponent ? (
        <span className="shrink-0 text-textSecondary/50">—</span>
      ) : null}
    </div>
  );
}

function TeamDashboardCard({ team }) {
  const record = team.wins != null || team.losses != null ? `${team.wins ?? 0}-${team.losses ?? 0}` : "—";
  const weeks = (team.weeks || []).filter((w) => w.number !== 0);

  return (
    <Card className="flex flex-col overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="flex items-center gap-2 font-varsity text-lg uppercase tracking-[0.06em]">
          {team.college.name}
          <PrestigeStars value={team.prestige} />
        </h3>
        <p className="text-xs text-white/70">
          {team.coach.name}
        </p>
      </div>

      <div className="grid grid-cols-3 gap-2 border-b border-border px-4 py-3 dark:border-darkborder">
        <StatPill label="OVR" value={team.overall ?? "—"} />
        <StatPill label="OFF" value={team.offense ?? "—"} />
        <StatPill label="DEF" value={team.defense ?? "—"} />
      </div>

      <div className="space-y-3 border-b border-border px-4 py-3 dark:border-darkborder">
        <KeyPlayersGroup label="Offense" players={team.bestOffensivePlayers} />
        <KeyPlayersGroup label="Defense" players={team.bestDefensivePlayers} />
      </div>

      <div className="border-b border-border px-4 py-3 dark:border-darkborder">
        <PositionGroupAverages averages={team.positionGroupAverages} />
      </div>

      <div className="max-h-72 overflow-y-auto px-4 py-3">
        <p className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-textSecondary flex justify-between">
          <span>Schedule</span>
          <span className="text-textPrimary dark:text-white">{record}</span>
        </p>
        {weeks.map((week) => (
          <ScheduleRow key={week.id} week={week} />
        ))}
      </div>
    </Card>
  );
}

export default TeamDashboardCard;
