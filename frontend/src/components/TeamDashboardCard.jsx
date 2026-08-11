import { useState } from "react";
import { Link } from "react-router-dom";
import { clsx } from "clsx";
import Card from "./Card";
import NumberPill from "./NumberPill";

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

const STAT_LEADER_LABELS = {
  passing: { label: "Passing", unit: "Yds" },
  rushing: { label: "Rushing", unit: "Yds" },
  receiving: { label: "Receiving", unit: "Yds" },
  sacks: { label: "Sacks", unit: "Sck" },
  tackles: { label: "Tackles", unit: "Tkl" },
  interceptions: { label: "INT", unit: "Int" },
};

function StatLeaderRow({ label, unit, leader }) {
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="w-16 shrink-0 text-xs text-textSecondary">{label}</span>
        <span className="truncate text-textPrimary dark:text-white text-xs">{leader ? leader.name : "—"}</span>
      </div>
      {leader ? (
        <span className="shrink-0 rounded-full bg-charcoal/5 px-1.5 py-0.5 text-xs font-semibold dark:bg-white/10">
          {leader.value} {unit}
        </span>
      ) : null}
    </div>
  );
}

function StatLeadersGroup({ statLeaders }) {
  return (
    <div className="space-y-1">
      <p className="text-xs uppercase tracking-wide text-textSecondary">Stat Leaders</p>
      <div className="space-y-1">
        {Object.entries(STAT_LEADER_LABELS).map(([key, meta]) => (
          <StatLeaderRow key={key} label={meta.label} unit={meta.unit} leader={statLeaders[key]} />
        ))}
      </div>
    </div>
  );
}

const TEAM_STAT_LABELS = {
  passingOffense: { label: "Pass Off", unit: "Yds" },
  passingDefense: { label: "Pass Def", unit: "Yds" },
  rushingOffense: { label: "Rush Off", unit: "Yds" },
  rushingDefense: { label: "Rush Def", unit: "Yds" },
  pointsPerGame: { label: "PPG", unit: "Pts" },
  pointsAgainstPerGame: { label: "PA/G", unit: "Pts" },
};

function TeamStatRow({ label, unit, value }) {
  return (
    <div className="flex items-center justify-between gap-2 text-sm">
      <span className="text-xs text-textSecondary text-nowrap overflow-hidden">{label}</span>
      <span className="shrink-0 rounded-full bg-charcoal/5 px-1.5 py-0.5 text-xs font-semibold dark:bg-white/10">
        {value ?? "—"} <span className="font-light">{unit}</span>
      </span>
    </div>
  );
}

function TeamStatsGroup({ teamStats }) {
  if (!teamStats) return null;

  return (
    <div className="space-y-1">
      <p className="text-xs uppercase tracking-wide text-textSecondary">Team Stats</p>
      <div className="grid grid-cols-2 gap-x-3 gap-y-1">
        {Object.entries(TEAM_STAT_LABELS).map(([key, meta]) => (
          <TeamStatRow key={key} label={meta.label} unit={meta.unit} value={teamStats[key]} />
        ))}
      </div>
    </div>
  );
}

function PositionGroupAverages({ averages }) {
  const entries = Object.entries(averages || {});
  if (!entries.length) return null;

  return (
    <div className="space-y-1">
      <div className="grid grid-flow-col grid-cols-3 grid-rows-3 gap-1.5">
        {entries.map(([label, value]) => (
          <NumberPill label={label} key={label} value={value ?? "—"} />
        ))}
      </div>
    </div>
  );
}

function PositionGroupAveragesCollapsible({ averages }) {
  const [open, setOpen] = useState(false);
  const entries = Object.entries(averages || {});
  if (!entries.length) return null;

  return (
    <div className="border-b border-border dark:border-darkborder">
      <button
        type="button"
        onClick={() => setOpen((prev) => !prev)}
        className="flex w-full items-center justify-center px-4 pb-2 text-xs font-semibold uppercase tracking-wide text-textSecondary"
      >
        <i className={clsx("fa-solid fa-chevron-down transition-transform", open && "rotate-180")} />
      </button>
      {open && (
        <div className="px-4 pb-3">
          <PositionGroupAverages averages={averages} />
        </div>
      )}
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

  const content = (
    <>
      <span className="w-20 shrink-0 text-textSecondary">{label}</span>
      {week.opponent ? (
        <span className="flex min-w-0 flex-1 items-center gap-1 truncate">
          <span className="text-textSecondary">{week.opponent.home ? "vs" : "@"}</span>{" "}
          {week.opponent.rank && <span className="shrink-0 text-textSecondary">#{week.opponent.rank}</span>}
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
    </>
  );

  const rowClass = "flex items-center gap-2 border-b border-border/60 py-1 text-xs last:border-0 dark:border-darkborder/60";

  if (week.gameId) {
    return (
      <Link to={`/dynasty/games/${week.gameId}`} className={clsx(rowClass, "hover:bg-charcoal/5 dark:hover:bg-white/5")}>
        {content}
      </Link>
    );
  }

  return <div className={rowClass}>{content}</div>;
}

function NextGameBanner({ nextGame }) {
  if (!nextGame) {
    return (
      <div className="border-b border-border bg-charcoal/5 px-4 py-2.5 text-xs italic text-textSecondary dark:border-darkborder dark:bg-white/5">
        Season complete — no games remaining
      </div>
    );
  }

  const label = nextGame.week.name || `Week ${nextGame.week.number}`;

  return (
    <div className="border-b border-border bg-burnt/10 px-4 py-2.5 dark:border-darkborder">
      <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-burnt">Next Game — {label}</p>
      {nextGame.opponent ? (
        <p className="mt-0.5 flex items-center gap-1.5 text-sm">
          <span className="text-textSecondary">{nextGame.opponent.home ? "vs" : "@"}</span>
          {nextGame.opponent.rank && <span className="text-textSecondary">#{nextGame.opponent.rank}</span>}
          <span className="font-semibold text-textPrimary dark:text-white">{nextGame.opponent.name}</span>
          {nextGame.opponent.userCoached ? (
            <i className="fa-solid fa-gamepad text-[11px] text-burnt/80" title="User-coached opponent" />
          ) : null}
        </p>
      ) : (
        <p className="mt-0.5 text-sm italic text-textSecondary">TBD</p>
      )}
    </div>
  );
}

function TeamDashboardCard({ team, dynastyId, seasonId }) {
  const record = team.wins != null || team.losses != null ? `${team.wins ?? 0}-${team.losses ?? 0}` : "—";
  const weeks = (team.weeks || []).filter((w) => w.number !== 0);

  return (
    <Card className="flex flex-col overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="flex items-center gap-2 font-varsity text-lg uppercase tracking-[0.06em]">
          {team.currentRank ? (
            <span className="rounded-full bg-burnt px-2 py-0.5 text-xs">#{team.currentRank}</span>
          ) : null}
          {team.college.alternateName ? team.college.alternateName : team.college.name}
          <PrestigeStars value={team.prestige} />
        </h3>
        <p className="text-xs text-white/70">
          {team.coach.name}
        </p>
      </div>

      <NextGameBanner nextGame={team.nextGame} />

      <div className="space-y-3 border-b border-border px-4 py-3 dark:border-darkborder">
        {team.statLeaders ? (
          <StatLeadersGroup statLeaders={team.statLeaders} />
        ) : (
          <>
            <KeyPlayersGroup label="Offense" players={team.bestOffensivePlayers} />
            <KeyPlayersGroup label="Defense" players={team.bestDefensivePlayers} />
          </>
        )}
        <TeamStatsGroup teamStats={team.teamStats} />
      </div>

      <div className="space-y-3 px-4 pt-3 pb-2 dark:border-darkborder">
        <div className="grid grid-cols-3 gap-1.5">
          <NumberPill label="OVR" bold="true" value={team.overall ?? "—"} />
          <NumberPill label="OFF" bold="true" value={team.offense ?? "—"} />
          <NumberPill label="DEF" bold="true" value={team.defense ?? "—"} />
        </div>
      </div>

      <PositionGroupAveragesCollapsible averages={team.positionGroupAverages} />

      <div className="max-h-72 overflow-y-auto px-4 py-3">
        <p className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-textSecondary flex justify-between">
          <span>Schedule</span>
          <span className="text-textPrimary dark:text-white">{record}</span>
        </p>
        {weeks.map((week) => (
          <ScheduleRow key={week.id} week={week} />
        ))}
      </div>

      {dynastyId && seasonId && (
        <Link
          to={`/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${team.id}/roster`}
          className="border-t border-border px-4 py-2 text-center text-xs font-semibold uppercase tracking-wide text-burnt hover:bg-burnt/5 dark:border-darkborder"
        >
          Full Roster &rarr;
        </Link>
      )}
    </Card>
  );
}

export default TeamDashboardCard;
