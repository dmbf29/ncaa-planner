import { clsx } from "clsx";

function RankTrend({ trend }) {
  if (trend === "up") return <i className="fa-solid fa-caret-up text-success" title="Moved up from last week" />;
  if (trend === "down") return <i className="fa-solid fa-caret-down text-danger" title="Moved down from last week" />;

  return (
    <span className="text-textSecondary" title="No change from last week">
      &mdash;
    </span>
  );
}

function MatchupCell({ matchup }) {
  if (!matchup) return <span className="text-textSecondary/50">&mdash;</span>;

  return (
    <span className="whitespace-nowrap">
      {matchup.home ? "vs" : "@"} {matchup.opponent.rank && `#${matchup.opponent.rank} `}
      {matchup.opponent.name}
    </span>
  );
}

function LastResultCell({ lastResult }) {
  if (!lastResult) return <span className="text-textSecondary/50">&mdash;</span>;

  return (
    <span className="whitespace-nowrap">
      <span className={clsx("font-semibold", lastResult.won ? "text-success" : "text-danger")}>
        {lastResult.won ? "W" : "L"} {lastResult.teamScore}-{lastResult.opponentScore}
      </span>{" "}
      <span className="text-textSecondary">{lastResult.opponent.abbrev ?? lastResult.opponent.name}</span>
    </span>
  );
}

function RankingRow({ entry }) {
  return (
    <tr
      className={clsx(
        "border-b border-border/60 last:border-0 dark:border-darkborder/60",
        entry.coachedByUs && "bg-burnt/10 font-semibold",
      )}
    >
      <td className="px-3 py-1.5 text-textSecondary">{entry.rank}</td>
      <td className="px-2 py-1.5 text-center">
        <RankTrend trend={entry.rankTrend} />
      </td>
      <td className="min-w-0 px-2 py-1.5">
        <span className="flex items-center gap-1.5">
          <span className="truncate text-textPrimary dark:text-white">{entry.college.name}</span>
          {entry.record && (
            <span className="shrink-0 font-normal text-textSecondary">
              ({entry.record.wins ?? 0}-{entry.record.losses ?? 0})
            </span>
          )}
          {entry.coachedByUs && <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />}
        </span>
      </td>
      <td className="px-2 py-1.5 text-right text-textSecondary">
        <LastResultCell lastResult={entry.lastResult} />
      </td>
      <td className="px-3 py-1.5 text-right text-textSecondary">
        <MatchupCell matchup={entry.thisWeek} />
      </td>
    </tr>
  );
}

function Top25TableBody({ rankings }) {
  return (
    <table className="w-full text-xs">
      <thead>
        <tr className="border-b border-border text-left uppercase tracking-wide text-textSecondary dark:border-darkborder">
          <th className="px-3 py-2 font-semibold">#</th>
          <th className="px-2 py-2 text-center font-semibold">Chg</th>
          <th className="px-2 py-2 font-semibold">Team</th>
          <th className="px-2 py-2 text-right font-semibold">Last Wk</th>
          <th className="px-3 py-2 text-right font-semibold">This Wk</th>
        </tr>
      </thead>
      <tbody>
        {rankings.map((entry) => (
          <RankingRow key={entry.rank} entry={entry} />
        ))}
      </tbody>
    </table>
  );
}

export default Top25TableBody;
