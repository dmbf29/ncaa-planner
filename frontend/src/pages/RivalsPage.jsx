import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchRivals } from "../lib/apiClient";

const record = (c) => `${c.wins}-${c.losses}${c.ties ? `-${c.ties}` : ""}`;
const pct = (value) => (value == null ? "—" : value.toFixed(3).replace(/^0/, ""));
const signed = (value) => (value > 0 ? `+${value}` : String(value));

const gameTitle = (game) => game.label || game.weekName || `Week ${game.weekNumber}`;

function Logo({ college, size = "h-6 w-6" }) {
  return college?.logoUrl ? (
    <img src={college.logoUrl} alt="" className={clsx(size, "shrink-0 object-contain")} />
  ) : (
    <span className={clsx(size, "shrink-0 rounded-full bg-charcoal/10 dark:bg-white/10")} />
  );
}

function SectionTitle({ children, sub }) {
  return (
    <div className="mb-3 mt-10">
      <h2 className="inline-block border-b-2 border-burnt pb-0.5 font-varsity text-xl tracking-[0.06em] uppercase">
        {children}
      </h2>
      {sub && <p className="mt-1 text-sm text-textSecondary dark:text-white/60">{sub}</p>}
    </div>
  );
}

function StatTile({ label, value }) {
  return (
    <Card className="p-3 text-center">
      <div className="font-varsity text-2xl text-burnt">{value}</div>
      <div className="mt-0.5 text-[11px] font-semibold uppercase tracking-wide text-textSecondary dark:text-white/60">{label}</div>
    </Card>
  );
}

function Scoreline({ side, won }) {
  return (
    <div
      className={clsx(
        "flex items-center gap-2 rounded-md px-2 py-1.5",
        won ? "bg-burnt/10 dark:bg-burnt/20" : "bg-charcoal/[0.04] dark:bg-white/5",
      )}
    >
      <Logo college={side.college} />
      <div className="min-w-0 flex-1 truncate text-sm">
        {side.rank ? <span className="mr-1 text-textSecondary">#{side.rank}</span> : null}
        <span className={clsx(won ? "font-bold" : "text-charcoal/70 dark:text-white/70")}>{side.college.name}</span>
        <span className="ml-1 text-xs text-textSecondary dark:text-white/50">{side.coachName}</span>
      </div>
      <div className={clsx("font-varsity text-xl tabular-nums", won ? "text-burnt" : "text-charcoal/60 dark:text-white/60")}>{side.score}</div>
    </div>
  );
}

function GameCard({ game, compact = false }) {
  const winnerId = game.winnerCoachId;
  const badges = [
    game.overtime && "OT",
    game.upset && "Upset",
    game.bothRanked && "Ranked clash",
    game.comeback && `${game.comeback}-pt comeback`,
  ].filter(Boolean);

  return (
    <Link
      to={`/dynasty/games/${game.id}`}
      className="flex flex-col gap-1.5 rounded-xl border border-border bg-surface p-3 shadow-card transition hover:-translate-y-0.5 hover:border-burnt/60 dark:border-darkborder dark:bg-darksurface"
    >
      <div className="mb-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] uppercase tracking-wide text-textSecondary dark:text-white/60">
        <span className="font-semibold text-charcoal dark:text-white">{game.year}</span>
        <span className={clsx(game.cfpRound && "font-semibold text-burnt")}>{gameTitle(game)}</span>
        {badges.map((badge) => (
          <span key={badge} className="rounded-full bg-burnt px-2 py-0.5 font-semibold text-white">
            {badge}
          </span>
        ))}
      </div>
      <Scoreline side={game.away} won={winnerId === game.away.coachId} />
      <Scoreline side={game.home} won={winnerId === game.home.coachId} />
      {!compact && (
        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 border-t border-border/60 pt-2 text-xs text-textSecondary dark:border-darkborder dark:text-white/60">
          <span>
            Yards: {game.away.stats.totalYards ?? "—"}–{game.home.stats.totalYards ?? "—"}
          </span>
          <span>
            Turnovers: {game.away.stats.turnovers ?? "—"}–{game.home.stats.turnovers ?? "—"}
          </span>
          {game.offensivePlayerOfGame && (
            <span>
              <i className="fa-solid fa-bolt mr-1 text-burnt" />
              {game.offensivePlayerOfGame.name}
            </span>
          )}
          {game.defensivePlayerOfGame && (
            <span>
              <i className="fa-solid fa-shield mr-1 text-olive" />
              {game.defensivePlayerOfGame.name}
            </span>
          )}
        </div>
      )}
    </Link>
  );
}

function FunFacts({ facts }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
      {facts.map((fact) => (
        <Card key={fact.id} className="flex flex-col gap-1 p-4">
          <div className="text-[11px] font-semibold uppercase tracking-wide text-textSecondary">{fact.title}</div>
          <div className="font-varsity text-2xl text-burnt">{fact.value}</div>
          <div className="text-sm">{fact.detail}</div>
          {fact.game && (
            <Link to={`/dynasty/games/${fact.game.id}`} className="mt-1 text-xs font-semibold text-burnt hover:underline">
              View game →
            </Link>
          )}
        </Card>
      ))}
    </div>
  );
}

function Leaderboard({ coaches }) {
  const rows = coaches.filter((c) => c.games > 0);
  return (
    <Card className="overflow-x-auto">
      <table className="w-full min-w-[640px] text-sm">
        <thead>
          <tr className="border-b border-border text-left text-[11px] uppercase tracking-wide text-textSecondary dark:border-darkborder">
            <th className="px-3 py-2">#</th>
            <th className="px-3 py-2">Coach</th>
            <th className="px-3 py-2 text-center">Record</th>
            <th className="px-3 py-2 text-center">Pct</th>
            <th className="px-3 py-2 text-center">PF–PA</th>
            <th className="px-3 py-2 text-center">Margin</th>
            <th className="px-3 py-2 text-center">Best streak</th>
            <th className="px-3 py-2 text-center">Ranked W</th>
            <th className="px-3 py-2 text-center">CFP W</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((coach, index) => (
            <tr key={coach.id} className="border-b border-border/50 last:border-0 dark:border-darkborder/60">
              <td className="px-3 py-2 text-textSecondary">{index + 1}</td>
              <td className="px-3 py-2">
                <div className="font-semibold">{coach.name}</div>
                <div className="flex items-center gap-1 text-xs text-textSecondary">
                  {coach.schools.map((s) => (
                    <span key={s.college.id} className="inline-flex items-center gap-1" title={s.years.join(", ")}>
                      <Logo college={s.college} size="h-4 w-4" />
                      {s.college.abbrev || s.college.name}
                    </span>
                  ))}
                </div>
              </td>
              <td className="px-3 py-2 text-center font-semibold tabular-nums">{record(coach)}</td>
              <td className="px-3 py-2 text-center tabular-nums">{pct(coach.winPct)}</td>
              <td className="px-3 py-2 text-center tabular-nums">
                {coach.pointsFor}–{coach.pointsAgainst}
              </td>
              <td
                className={clsx(
                  "px-3 py-2 text-center tabular-nums",
                  coach.avgMargin > 0 ? "text-success" : coach.avgMargin < 0 ? "text-danger" : "",
                )}
              >
                {coach.avgMargin == null ? "—" : signed(coach.avgMargin)}
              </td>
              <td className="px-3 py-2 text-center tabular-nums">{coach.bestStreak}</td>
              <td className="px-3 py-2 text-center tabular-nums">{coach.rankedWins}</td>
              <td className="px-3 py-2 text-center tabular-nums">{coach.playoffWins}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

// Row coach's record against the column coach, from the series data.
function Matrix({ coaches, rivalries, onPick }) {
  const rows = coaches.filter((c) => c.games > 0);
  const seriesFor = (a, b) => rivalries.find((r) => r.coaches.some((c) => c.id === a) && r.coaches.some((c) => c.id === b));

  return (
    <Card className="overflow-x-auto">
      <table className="w-full min-w-[480px] text-center text-sm">
        <thead>
          <tr className="border-b border-border text-[11px] uppercase tracking-wide text-textSecondary dark:border-darkborder">
            <th className="px-3 py-2 text-left">vs.</th>
            {rows.map((c) => (
              <th key={c.id} className="px-3 py-2">
                {c.name.split(" ")[0]}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id} className="border-b border-border/50 last:border-0 dark:border-darkborder/60">
              <th className="px-3 py-2 text-left font-semibold">{row.name}</th>
              {rows.map((col) => {
                if (row.id === col.id) return <td key={col.id} className="bg-charcoal/5 dark:bg-white/5" />;
                const series = seriesFor(row.id, col.id);
                if (!series) return <td key={col.id} className="px-3 py-2 text-textSecondary">—</td>;
                const mine = series.coaches.find((c) => c.id === row.id);
                const theirs = series.coaches.find((c) => c.id === col.id);
                return (
                  <td key={col.id} className="p-1">
                    <button
                      onClick={() => onPick(series.key)}
                      className={clsx(
                        "w-full rounded-md px-2 py-1.5 font-semibold tabular-nums hover:ring-2 hover:ring-burnt/50",
                        mine.wins > theirs.wins && "bg-success/15 text-success",
                        mine.wins < theirs.wins && "bg-danger/10 text-danger",
                        mine.wins === theirs.wins && "bg-warning/15 text-warning",
                      )}
                    >
                      {mine.wins}-{theirs.wins}
                      {series.ties ? `-${series.ties}` : ""}
                    </button>
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </Card>
  );
}

function CoachHeader({ coach, info, align, detail }) {
  const right = align === "right";
  return (
    <div className={clsx("flex min-w-0 flex-1 items-center gap-3", right && "flex-row-reverse text-right")}>
      <div className="flex shrink-0 -space-x-2">
        {coach.schools.map((school) => (
          <span key={school.id} className="rounded-full bg-white p-1 ring-2 ring-charcoal">
            <Logo college={school} size="h-8 w-8 md:h-10 md:w-10" />
          </span>
        ))}
      </div>
      <div className="min-w-0">
        <div className="truncate font-varsity text-base uppercase leading-tight tracking-[0.04em] md:text-xl">{info.name}</div>
        {detail && <div className="text-xs text-white/60">{detail}</div>}
      </div>
    </div>
  );
}

function Bar({ label, a, b, lowerIsBetter, suffix = "" }) {
  const total = (a ?? 0) + (b ?? 0);
  const left = total ? ((a ?? 0) / total) * 100 : 50;
  const aWins = a != null && b != null && a !== b && (lowerIsBetter ? a < b : a > b);
  const bWins = a != null && b != null && a !== b && (lowerIsBetter ? b < a : b > a);
  return (
    <div>
      <div className="flex items-baseline justify-between text-sm tabular-nums">
        <span className={clsx("text-base", aWins ? "font-bold text-burnt" : "text-charcoal/70 dark:text-white/70")}>
          {a ?? "—"}
          {suffix}
        </span>
        <span className="text-[11px] font-semibold uppercase tracking-wide text-textSecondary dark:text-white/60">{label}</span>
        <span className={clsx("text-base", bWins ? "font-bold text-olive dark:text-[#9bb38a]" : "text-charcoal/70 dark:text-white/70")}>
          {b ?? "—"}
          {suffix}
        </span>
      </div>
      <div className="mt-1 flex h-2.5 gap-0.5 overflow-hidden rounded-full">
        <div className={clsx("rounded-l-full", aWins ? "bg-burnt" : "bg-burnt/45")} style={{ width: `${left}%` }} />
        <div className={clsx("rounded-r-full", bWins ? "bg-olive" : "bg-olive/45")} style={{ width: `${100 - left}%` }} />
      </div>
    </div>
  );
}

function Superlative({ title, game }) {
  if (!game) return null;
  return (
    <div>
      <div className="mb-1.5 text-xs font-bold uppercase tracking-wide text-charcoal dark:text-white">{title}</div>
      <GameCard game={game} compact />
    </div>
  );
}

function Performances({ performances }) {
  if (!performances.length) return null;
  return (
    <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
      {performances.map((category) => (
        <Card key={category.key} className="p-3">
          <div className="mb-2 text-xs font-bold uppercase tracking-wide text-charcoal dark:text-white">
            Best single game · {category.label}
          </div>
          <ol className="flex flex-col gap-2">
            {category.top.map((entry, index) => (
              <li key={`${entry.gameId}-${entry.player}`} className="flex items-start gap-2">
                <span className="w-4 text-xs text-textSecondary">{index + 1}</span>
                <Logo college={entry.college} size="h-5 w-5" />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold">
                    {entry.player} <span className="font-normal text-textSecondary dark:text-white/60">{entry.position}</span>
                  </div>
                  <div className="text-xs text-textSecondary dark:text-white/60">
                    {entry.line} · {entry.year} · vs {entry.opponent.name}
                  </div>
                </div>
                <Link to={`/dynasty/games/${entry.gameId}`} className="text-xs font-semibold text-burnt hover:underline">
                  Box
                </Link>
              </li>
            ))}
          </ol>
        </Card>
      ))}
    </div>
  );
}

function SeriesDetail({ series, coachInfo }) {
  const isAll = !series.coaches;
  const [a, b] = series.coaches || [];
  const names = Object.fromEntries(Object.values(coachInfo).map((c) => [c.id, c.name]));
  const streak = series.currentStreak;
  const leader = isAll || a.wins === b.wins ? null : a.wins > b.wins ? a : b;
  const sites = (c) => `${c.home.wins}-${c.home.games - c.home.wins} home · ${c.away.wins}-${c.away.games - c.away.wins} away`;
  const flags = [
    ["Overtime games", series.flags.overtime],
    ["Ranked vs. ranked", series.flags.bothRanked],
    ["Postseason meetings", series.flags.postseason],
    ["Comebacks", series.flags.comebacks],
    ["One-score games", series.flags.oneScoreGames],
    ["Shutouts", series.flags.shutouts],
  ].filter(([, n]) => n > 0);

  return (
    <div className="flex flex-col gap-6">
      {!isAll && (
      <Card className="overflow-hidden">
        <div className="bg-charcoal px-4 py-4 text-white md:px-6 dark:bg-black/40">
          <div className="flex items-center gap-3">
            <CoachHeader coach={a} info={coachInfo[a.id]} align="left" detail={sites(a)} />
            <div className="shrink-0 text-center">
              <div className="font-varsity text-4xl leading-none tabular-nums md:text-5xl">
                <span className="text-burnt">{a.wins}</span>
                <span className="mx-1 text-white/40">–</span>
                <span className="text-[#a9c294]">{b.wins}</span>
              </div>
              <div className="mt-1 text-[11px] uppercase tracking-wide text-white/60">
                {series.gamesPlayed} {series.gamesPlayed === 1 ? "game" : "games"}
                {series.ties ? ` · ${series.ties} tied` : ""}
              </div>
            </div>
            <CoachHeader coach={b} info={coachInfo[b.id]} align="right" detail={sites(b)} />
          </div>
          <p className="mt-3 border-t border-white/10 pt-2 text-center text-sm text-white/90">
            {leader ? `${names[leader.id]} leads the series` : "The series is tied"}
            {streak && streak.length > 1 ? ` · ${names[streak.coachId]} has won ${streak.length} straight` : ""}
          </p>
        </div>
        <div className="grid gap-3 px-4 pb-4 pt-5 md:px-6">
          <Bar label="Total points" a={a.pointsFor} b={b.pointsFor} />
          {series.teamAverages.map((row) => (
            <Bar
              key={row.key}
              label={row.key === "third_down_pct" ? row.label : `${row.label} / game`}
              a={row.values[a.id]}
              b={row.values[b.id]}
              lowerIsBetter={row.lowerIsBetter}
              suffix={row.key === "third_down_pct" ? "%" : ""}
            />
          ))}
        </div>
        <div className="mx-4 flex flex-wrap gap-x-5 gap-y-1 border-t border-border/60 py-3 text-xs md:mx-6 text-textSecondary dark:border-darkborder dark:text-white/60">
          <span>
            Avg margin: {names[a.id]} {signed(a.avgMargin)}
          </span>
          <span>
            Longest streak: {names[a.id].split(" ")[0]} {series.longestStreaks[a.id]}, {names[b.id].split(" ")[0]}{" "}
            {series.longestStreaks[b.id]}
          </span>
          <span>
            Players of the game: {a.playerOfGame.offense + a.playerOfGame.defense} / {b.playerOfGame.offense + b.playerOfGame.defense}
          </span>
          {flags.map(([label, n]) => (
            <span key={label}>
              {label}: <strong className="text-charcoal dark:text-white">{n}</strong>
            </span>
          ))}
        </div>
      </Card>
      )}

      <div>
        <h3 className="mb-3 inline-block border-b-2 border-burnt pb-0.5 font-varsity text-lg uppercase tracking-[0.06em]">{isAll ? "Moments" : "Series moments"}</h3>
        <div className="grid gap-3 md:grid-cols-2">
          <Superlative title="Biggest win" game={series.superlatives.biggestWin} />
          <Superlative title="Closest game" game={series.superlatives.closestGame} />
          <Superlative title="Highest scoring" game={series.superlatives.highestScoring} />
          <Superlative title="Lowest scoring" game={series.superlatives.lowestScoring} />
        </div>
      </div>

      <div>
        <h3 className="mb-3 inline-block border-b-2 border-burnt pb-0.5 font-varsity text-lg uppercase tracking-[0.06em]">Player performances</h3>
        <Performances performances={series.performances} />
      </div>

      <div>
        <h3 className="mb-3 inline-block border-b-2 border-burnt pb-0.5 font-varsity text-lg uppercase tracking-[0.06em]">{isAll ? "Every game" : "Every meeting"}</h3>
        <div className="grid gap-3 md:grid-cols-2">
          {[...series.games].reverse().map((game) => (
            <GameCard key={game.id} game={game} />
          ))}
        </div>
      </div>
    </div>
  );
}

function RivalsPage() {
  const { dynastyId } = useParams();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [selected, setSelected] = useState(null);

  useEffect(() => {
    let cancelled = false;
    fetchRivals(dynastyId)
      .then((result) => {
        if (cancelled) return;
        setData(result);
        setSelected("all");
      })
      .catch((err) => !cancelled && setError(err.message));
    return () => {
      cancelled = true;
    };
  }, [dynastyId]);

  const coachInfo = useMemo(() => Object.fromEntries((data?.coaches || []).map((c) => [c.id, c])), [data]);
  const series = selected === "all" ? data?.allGames : data?.rivalries.find((r) => r.key === selected);

  if (error) return <p className="text-danger">{error}</p>;
  if (!data) return <p className="text-textSecondary">Loading rivalries…</p>;

  const { summary } = data;

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        eyebrow={data.dynasty.name}
        title="Rivals"
        actions={
          <Link to={`/dynasty/${dynastyId}`} className="text-sm text-textSecondary hover:underline">
            ← Dashboard
          </Link>
        }
      />

      {summary.games === 0 ? (
        <Card className="p-6 text-center text-textSecondary">
          No two user-coached teams have played each other yet. When they do, the rivalry shows up here.
        </Card>
      ) : (
        <>
          <p className="mb-4 text-sm text-textSecondary">
            Every game where one user coached team played another, {summary.firstYear}
            {summary.lastYear !== summary.firstYear ? `–${summary.lastYear}` : ""}. Series follow the coach, so moving
            schools doesn&apos;t reset a rivalry.
          </p>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <StatTile label="Games" value={summary.games} />
            <StatTile label="Avg home score" value={summary.avgHomeScore} />
            <StatTile label="Avg away score" value={summary.avgAwayScore} />
            <StatTile label="Avg margin" value={summary.avgMargin} />
            <StatTile label="Avg INTs / game" value={summary.avgInterceptions} />
            <StatTile label="CFP games" value={summary.cfpGames} />
          </div>

          <SectionTitle sub="Records in games against other user coaches only">All-time standings</SectionTitle>
          <Leaderboard coaches={data.coaches} />

          <SectionTitle sub="Each row's record against the coach in the column. Click one to open the series.">
            Head to head
          </SectionTitle>
          <Matrix coaches={data.coaches} rivalries={data.rivalries} onPick={(key) => {
            setSelected(key);
            document.getElementById("series")?.scrollIntoView({ behavior: "smooth" });
          }} />

          <SectionTitle>Hall of records</SectionTitle>
          <FunFacts facts={data.funFacts} />

          <div id="series" />
          <SectionTitle sub="Pick a rivalry, or see every user game together">The rivalries</SectionTitle>
          <div className="mb-4 flex flex-wrap gap-2">
            {[{ key: "all", all: true }, ...data.rivalries].map((r) => {
              if (r.all) {
                return (
                  <button
                    key="all"
                    onClick={() => setSelected("all")}
                    className={clsx(
                      "rounded-xl border-2 px-4 py-2.5 text-left text-sm shadow-card transition",
                      selected === "all"
                        ? "border-burnt bg-burnt text-white"
                        : "border-border bg-surface hover:border-burnt/60 dark:border-darkborder dark:bg-darksurface",
                    )}
                  >
                    <div className="font-semibold">All games</div>
                    <div className={clsx("text-xs", selected === "all" ? "text-white/90" : "text-textSecondary dark:text-white/60")}>
                      {data.allGames.gamesPlayed} games
                    </div>
                  </button>
                );
              }
              const [a, b] = r.coaches;
              return (
                <button
                  key={r.key}
                  onClick={() => setSelected(r.key)}
                  className={clsx(
                    "rounded-xl border-2 px-4 py-2.5 text-left text-sm shadow-card transition",
                    r.key === selected
                      ? "border-burnt bg-burnt text-white"
                      : "border-border bg-surface hover:border-burnt/60 dark:border-darkborder dark:bg-darksurface",
                  )}
                >
                  <div className="font-semibold">
                    {coachInfo[a.id].name.split(" ")[0]} vs. {coachInfo[b.id].name.split(" ")[0]}
                  </div>
                  <div className={clsx("text-xs", r.key === selected ? "text-white/90" : "text-textSecondary dark:text-white/60")}>
                    {a.wins}-{b.wins}
                    {r.ties ? `-${r.ties}` : ""} · {r.gamesPlayed} {r.gamesPlayed === 1 ? "game" : "games"}
                  </div>
                </button>
              );
            })}
          </div>
          {series && <SeriesDetail series={series} coachInfo={coachInfo} />}
        </>
      )}
    </div>
  );
}

export default RivalsPage;
