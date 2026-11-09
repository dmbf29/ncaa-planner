import { useState } from "react";
import { Link } from "react-router-dom";
import { clsx } from "clsx";
import Card from "./Card";
import NumberPill from "./NumberPill";
import { conferenceLogo } from "../lib/conferenceLogos";

function SectionTitle({ children, right }) {
  return (
    <div className="mb-2 flex items-center gap-2">
      <h4 className="font-varsity text-xs uppercase tracking-[0.18em] text-textSecondary">{children}</h4>
      <span className="h-px flex-1 bg-border dark:bg-darkborder" />
      {right}
    </div>
  );
}

function TeamLogo({ src, name, className = "h-8 w-8" }) {
  if (src) return <img src={src} alt="" className={clsx("shrink-0 object-contain", className)} />;
  return (
    <span
      className={clsx(
        "flex shrink-0 items-center justify-center rounded-full bg-charcoal/10 font-varsity text-xs text-textSecondary dark:bg-white/10",
        className,
      )}
    >
      {name?.[0]}
    </span>
  );
}

// OVR/OFF/DEF colour band, so a glance tells you who is stacked.
const ratingColor = (value) =>
  value >= 90 ? "bg-success" : value >= 80 ? "bg-warning" : value >= 70 ? "bg-burnt" : "bg-danger";

function RatingTile({ label, value }) {
  return (
    <div className="rounded-md bg-white/10 px-2.5 pb-2 pt-1.5">
      <div className="flex items-baseline justify-between">
        <span className="font-crayon text-[10px] uppercase tracking-[0.15em] text-white/60">{label}</span>
        <span className="font-varsity text-xl leading-none">{value ?? "—"}</span>
      </div>
      <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/15">
        <div className={clsx("h-full rounded-full", ratingColor(value))} style={{ width: `${Math.min(value ?? 0, 100)}%` }} />
      </div>
    </div>
  );
}

const STAT_LEADERS = [
  { key: "passing", label: "Passing", unit: "YDS", icon: "fa-football", side: "off" },
  { key: "rushing", label: "Rushing", unit: "YDS", icon: "fa-person-running", side: "off" },
  { key: "receiving", label: "Receiving", unit: "YDS", icon: "fa-hand", side: "off" },
  { key: "sacks", label: "Sacks", unit: "SCK", icon: "fa-bolt", side: "def" },
  { key: "tackles", label: "Tackles", unit: "TKL", icon: "fa-shield-halved", side: "def" },
  { key: "interceptions", label: "Interceptions", unit: "INT", icon: "fa-crosshairs", side: "def" },
];

function LeaderTile({ meta, leader }) {
  return (
    <div
      className={clsx(
        "min-w-0 rounded-md border-l-[3px] bg-charcoal/[0.04] px-2.5 py-2 dark:bg-white/5",
        meta.side === "off" ? "border-burnt" : "border-olive",
      )}
    >
      <p className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wide text-textSecondary">
        <i className={clsx("fa-solid", meta.icon, meta.side === "off" ? "text-burnt" : "text-olive")} />
        {meta.label}
      </p>
      {leader ? (
        <>
          <p className="mt-0.5 font-varsity text-xl leading-tight">
            {Number(leader.value).toLocaleString()}
            <span className="ml-1 text-[10px] tracking-wide text-textSecondary">{meta.unit}</span>
          </p>
          <p className="truncate text-xs text-textPrimary dark:text-white" title={`${leader.position} ${leader.name}`}>
            <span className="text-textSecondary">{leader.position}</span> {leader.name}
          </p>
        </>
      ) : (
        <p className="mt-0.5 font-varsity text-xl text-textSecondary/50">—</p>
      )}
    </div>
  );
}

function StatLeadersGroup({ statLeaders }) {
  return (
    <div>
      <SectionTitle>Stat Leaders</SectionTitle>
      <div className="grid grid-cols-2 gap-1.5">
        {STAT_LEADERS.map((meta) => (
          <LeaderTile key={meta.key} meta={meta} leader={statLeaders[meta.key]} />
        ))}
      </div>
    </div>
  );
}

function KeyPlayersGroup({ label, players }) {
  return (
    <div className="space-y-1">
      <p className="text-xs uppercase tracking-wide text-textSecondary">{label}</p>
      {players && players.length > 0 ? (
        players.map((player) => (
          <div key={player.id} className="flex items-center justify-between gap-2 text-sm">
            <span className="truncate">
              <span className="text-xs text-textSecondary">{player.position}</span> {player.name}
            </span>
            <span className="shrink-0 rounded-full bg-charcoal/5 px-1.5 py-0.5 text-xs font-semibold dark:bg-white/10">
              {player.overall}
            </span>
          </div>
        ))
      ) : (
        <p className="text-sm text-textSecondary/60">—</p>
      )}
    </div>
  );
}

function YardCell({ label, value, side }) {
  return (
    <div className="text-center">
      <p className={clsx("text-[10px] font-semibold uppercase tracking-wide", side === "off" ? "text-burnt" : "text-olive")}>
        {label}
      </p>
      <p className="font-varsity text-base leading-tight">{value ?? "—"}</p>
    </div>
  );
}

// A scoreboard-style summary: points for/against with the margin, then yards per game.
function PerGameGroup({ teamStats }) {
  if (!teamStats) return null;

  const ppg = Number(teamStats.pointsPerGame);
  const pag = Number(teamStats.pointsAgainstPerGame);
  const margin = Number.isFinite(ppg) && Number.isFinite(pag) ? ppg - pag : null;

  return (
    <div>
      <SectionTitle>Per Game</SectionTitle>
      <div className="grid grid-cols-3 overflow-hidden rounded-md bg-charcoal text-center text-white dark:bg-black/40">
        <div className="px-2 py-2">
          <p className="font-varsity text-2xl leading-none">{teamStats.pointsPerGame ?? "—"}</p>
          <p className="mt-1 text-[10px] uppercase tracking-[0.15em] text-white/60">Pts For</p>
        </div>
        <div className="border-x border-white/10 px-2 py-2">
          <p className="font-varsity text-2xl leading-none">{teamStats.pointsAgainstPerGame ?? "—"}</p>
          <p className="mt-1 text-[10px] uppercase tracking-[0.15em] text-white/60">Pts Agnst</p>
        </div>
        <div className="px-2 py-2">
          <p
            className={clsx(
              "font-varsity text-2xl leading-none",
              margin == null ? "" : margin >= 0 ? "text-[#7BC47F]" : "text-[#F08080]",
            )}
          >
            {margin == null ? "—" : `${margin >= 0 ? "+" : ""}${margin.toFixed(1)}`}
          </p>
          <p className="mt-1 text-[10px] uppercase tracking-[0.15em] text-white/60">Margin</p>
        </div>
      </div>
      <div className="mt-2.5 grid grid-cols-4 gap-1">
        <YardCell side="off" label="Pass O" value={teamStats.passingOffense} />
        <YardCell side="off" label="Rush O" value={teamStats.rushingOffense} />
        <YardCell side="def" label="Pass D" value={teamStats.passingDefense} />
        <YardCell side="def" label="Rush D" value={teamStats.rushingDefense} />
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

function tileLabel(week) {
  if (week.conferenceChampionship) return "CONF";
  if (week.postSeason) return `BOWL ${(week.name || "").match(/\d+/)?.[0] ?? ""}`.trim();
  return `WK ${week.number}`;
}

function ScheduleTile({ week, isNext }) {
  const opp = week.opponent;
  const result = week.result;

  const tone = result
    ? result.won
      ? "border-success/30 bg-success/10"
      : "border-danger/30 bg-danger/10"
    : isNext
      ? "border-burnt bg-burnt/10 ring-1 ring-burnt"
      : opp
        ? "border-border bg-charcoal/[0.03] dark:border-darkborder dark:bg-white/5"
        : "border-dashed border-border dark:border-darkborder";

  const inner = (
    <>
      <div className="flex items-center justify-between text-[9px] font-semibold uppercase tracking-wide text-textSecondary">
        <span className="flex items-center gap-1">
          {tileLabel(week)}
          {opp?.conferenceGame && conferenceLogo(opp.conference) ? (
            <img src={conferenceLogo(opp.conference)} alt="" className="h-3 w-3 object-contain dark:bg-white/90" />
          ) : null}
        </span>
        {opp ? <span>{opp.home ? "vs" : "@"}</span> : null}
      </div>
      {opp ? (
        <>
          <div className="relative my-1 flex justify-center">
            <TeamLogo src={opp.logoUrl} name={opp.name} className="h-6 w-6" />
            {opp.userCoached ? (
              <i className="fa-solid fa-gamepad absolute -right-0.5 top-0 text-[10px] text-burnt" title="User-coached opponent" />
            ) : null}
            {week.missingStats ? (
              <span className="absolute -left-0.5 top-0 text-[10px]" title="Missing box-score or player stats — open this game to finish the upload">
                ⚠️
              </span>
            ) : null}
          </div>
          <p className="truncate text-center text-[10px] leading-tight text-textPrimary dark:text-white" title={opp.name}>
            {opp.rank ? <span className="text-textSecondary">#{opp.rank} </span> : null}
            {opp.name}
          </p>
          <p
            className={clsx(
              "mt-0.5 text-center font-varsity text-[11px] leading-tight",
              result ? (result.won ? "text-success" : "text-danger") : isNext ? "text-burnt" : "text-textSecondary/50",
            )}
          >
            {result ? `${result.won ? "W" : "L"} ${result.teamScore}-${result.opponentScore}` : isNext ? "NEXT" : "—"}
          </p>
        </>
      ) : (
        <p className="py-3 text-center font-varsity text-xs tracking-widest text-textSecondary/50">
          {week.conferenceChampionship ? "TBD" : "BYE"}
        </p>
      )}
    </>
  );

  const className = clsx("block rounded-md border px-1.5 py-1.5", tone);
  if (week.gameId) {
    return (
      <Link to={`/dynasty/games/${week.gameId}`} className={clsx(className, "transition hover:-translate-y-0.5 hover:shadow-card")}>
        {inner}
      </Link>
    );
  }
  return <div className={className}>{inner}</div>;
}

function currentStreak(weeks) {
  const results = weeks
    .filter((w) => w.result)
    .sort((a, b) => a.number - b.number)
    .map((w) => w.result.won);
  if (results.length === 0) return null;
  const last = results[results.length - 1];
  let count = 0;
  for (let i = results.length - 1; i >= 0 && results[i] === last; i -= 1) count += 1;
  return { won: last, count };
}

function ScheduleGrid({ weeks, nextWeekNumber }) {
  // Postseason slots with no opponent yet are pure noise until the bracket is set.
  const visible = weeks.filter((w) => !(w.postSeason && !w.opponent));
  const streak = currentStreak(weeks);

  return (
    <div>
      <SectionTitle
        right={
          streak ? (
            <span
              className={clsx(
                "flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-bold",
                streak.won ? "bg-success/15 text-success" : "bg-danger/15 text-danger",
              )}
            >
              {streak.won && streak.count >= 3 ? <i className="fa-solid fa-fire" /> : null}
              {streak.won ? "W" : "L"}
              {streak.count}
            </span>
          ) : null
        }
      >
        Schedule
      </SectionTitle>
      <div className="grid grid-cols-4 gap-1.5">
        {visible.map((week) => (
          <ScheduleTile key={week.id} week={week} isNext={!week.result && week.number === nextWeekNumber} />
        ))}
      </div>
    </div>
  );
}

function NextGamePanel({ team }) {
  const nextGame = team.nextGame;

  if (!nextGame) {
    return (
      <div className="bg-charcoal/5 px-4 py-3 text-center text-xs italic text-textSecondary dark:bg-white/5">
        Season complete — no games remaining
      </div>
    );
  }

  const label = nextGame.week.name || `Week ${nextGame.week.number}`;
  const opp = nextGame.opponent;
  const theirs = nextGame.opponentOverall;
  const injuryCount = nextGame.activeInjuryCount;

  return (
    <div className="bg-gradient-to-br from-burnt/20 via-burnt/15 to-burnt-5 px-4 py-2.5 border-b border-border">
      <div className="flex items-center justify-between">
        <p className="text-[10px] font-semibold uppercase tracking-[0.18em] text-burnt">Next Up — {label}</p>
        <span className="flex items-center gap-1.5">
          {opp?.conferenceGame && conferenceLogo(opp.conference) ? (
            <img
              src={conferenceLogo(opp.conference)}
              alt=""
              title={`${opp.conference} game`}
              className="h-5 w-5 rounded-sm object-contain dark:bg-white/90"
            />
          ) : null}
          {opp?.userCoached ? <i className="fa-solid fa-gamepad text-xs text-burnt" title="User-coached opponent" /> : null}
          {injuryCount > 0 ? (
            <span
              className="flex items-center gap-1 rounded-full bg-danger/10 px-1.5 py-0.5 text-[10px] font-bold text-danger"
              title={`${injuryCount} player${injuryCount === 1 ? "" : "s"} banged up heading into this game`}
            >
              <i className="fa-solid fa-square-plus" />
              {injuryCount}
            </span>
          ) : null}
        </span>
      </div>

      {opp ? (
        <div className="mt-1.5 flex items-center gap-3">
          <TeamLogo src={opp.logoUrl} name={opp.name} className="h-10 w-10" />
          <div className="min-w-0 flex-1">
            <p className="truncate font-varsity text-lg uppercase leading-tight tracking-[0.04em]">
              <span className="mr-1.5 text-xs tracking-[0.2em] text-textSecondary">{opp.home ? "VS" : "AT"}</span>
              {opp.rank ? <span className="mr-1 text-burnt">#{opp.rank}</span> : null}
              {opp.name}
            </p>
            <p className="text-xs text-textSecondary">
              {nextGame.opponentRecord ? `${nextGame.opponentRecord.wins ?? 0}-${nextGame.opponentRecord.losses ?? 0}` : null}
              {nextGame.opponentRecord && theirs != null ? " · " : null}
              {theirs != null ? `${theirs} OVR` : null}
            </p>
          </div>
          {nextGame.spread != null && (
            <span
              className={clsx(
                "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide",
                nextGame.spread < 0 ? "bg-success/15 text-success" : "bg-danger/15 text-danger",
              )}
              title="House line from the Big Game Breakdown"
            >
              {nextGame.spread < 0 ? "Fav" : "Dog"} {nextGame.spread > 0 ? "+" : ""}
              {nextGame.spread}
            </span>
          )}
        </div>
      ) : (
        <p className="mt-1.5 text-sm italic text-textSecondary">TBD</p>
      )}
    </div>
  );
}

// The team header doubles as the link to the full roster.
function HeaderWrapper({ to, children }) {
  const className = "block bg-charcoal px-4 pb-3 pt-3 text-white";
  if (!to) return <div className={className}>{children}</div>;

  return (
    <Link to={to} title="Full roster" className={`${className} transition hover:bg-charcoal/90`}>
      {children}
    </Link>
  );
}

function TeamDashboardCard({ team, dynastyId, seasonId }) {
  const record = team.wins != null || team.losses != null ? `${team.wins ?? 0}-${team.losses ?? 0}` : "—";
  const weeks = (team.weeks || []).filter((w) => w.number !== 0);

  return (
    <Card className="flex flex-col overflow-hidden">
      <HeaderWrapper
        to={dynastyId && seasonId ? `/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${team.id}/roster` : null}
      >
        <div className="flex items-center gap-3">
          <div className="flex h-14 w-14 shrink-0 items-center justify-center rounded-lg bg-white p-1.5 shadow-inner">
            <TeamLogo src={team.college.logoUrl} name={team.college.name} className="h-full w-full" />
          </div>
          <div className="min-w-0 flex-1">
            <h3 className="flex items-center gap-2 font-varsity text-xl uppercase leading-tight tracking-[0.06em]">
              {team.currentRank ? (
                <span className="shrink-0 rounded-full bg-burnt px-2 py-0.5 text-xs">#{team.currentRank}</span>
              ) : null}
              <span className="truncate">{team.college.alternateName ? team.college.alternateName : team.college.name}</span>
            </h3>
            <div className="mt-0.5">
              <PrestigeStars value={team.prestige} />
            </div>
            <p className="mt-0.5 truncate text-xs text-white/70">{team.coach.name}</p>
          </div>
          <div className="shrink-0 text-right">
            <p className="font-varsity text-3xl leading-none">{record}</p>
            {(team.coach.jobSecurity != null) && (
              <p className="mt-2.5 flex items-center gap-3 text-[11px] text-white/60">
                {team.coach.jobSecurity != null ? (
                  <span title="Job security">
                    <i className="fa-solid fa-user-shield mr-1" />
                    {team.coach.jobSecurity}% &middot; {team.coach.jobSecurityLabel}
                  </span>
                ) : null}
              </p>
            )}
          </div>
        </div>

        <div className="mt-3 grid grid-cols-3 gap-1.5">
          <RatingTile label="OVR" value={team.overall} />
          <RatingTile label="OFF" value={team.offense} />
          <RatingTile label="DEF" value={team.defense} />
        </div>

      </HeaderWrapper>

      <NextGamePanel team={team} />

      <div className="space-y-3 px-4 py-4">
        <PerGameGroup teamStats={team.teamStats} />
        <ScheduleGrid weeks={weeks} nextWeekNumber={team.nextGame?.week.number} />
        {team.statLeaders ? (
          <StatLeadersGroup statLeaders={team.statLeaders} />
        ) : (
          <div className="space-y-3">
            <KeyPlayersGroup label="Offense" players={team.bestOffensivePlayers} />
            <KeyPlayersGroup label="Defense" players={team.bestDefensivePlayers} />
          </div>
        )}
      </div>

      <PositionGroupAveragesCollapsible averages={team.positionGroupAverages} />

      {dynastyId && seasonId && (
        <div className="grid grid-cols-2 divide-x divide-border border-t border-border dark:divide-darkborder dark:border-darkborder">
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${team.id}/signing-class`}
            className="px-4 py-2.5 text-center text-xs font-semibold uppercase tracking-wide text-burnt hover:bg-burnt/5"
          >
            Signing Class &rarr;
          </Link>
          <Link
            to={`/dynasty/${dynastyId}/player-stats?collegeId=${team.college.id}`}
            className="px-4 py-2.5 text-center text-xs font-semibold uppercase tracking-wide text-burnt hover:bg-burnt/5"
          >
            Player Stats &rarr;
          </Link>
        </div>
      )}
    </Card>
  );
}

export default TeamDashboardCard;
