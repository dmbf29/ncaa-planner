import { Link } from "react-router-dom";
import { clsx } from "clsx";

export const weekLabel = (week) => week.name || (week.number === 0 ? "Week 0" : `Week ${week.number}`);

const gameDateLabel = (time) =>
  time ? new Date(time).toLocaleDateString(undefined, { month: "short", day: "numeric" }) : null;

function TeamName({ side }) {
  return (
    <span className="inline-flex items-center gap-1">
      {side.rank ? <span className="text-textSecondary">#{side.rank}</span> : null}
      {side.name}
      {side.coachedByUs ? <i className="fa-solid fa-gamepad text-[10px] text-burnt/80" title="User-coached" /> : null}
    </span>
  );
}

// Game pages are public (view results, screenshots, box score for anyone;
// editing is gated separately on that page itself), so every game row
// links there regardless of login state.
function LeagueGameRow({ game }) {
  const dateLabel = gameDateLabel(game.time);

  const rowClass =
    "flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60";

  return (
    <Link to={`/dynasty/games/${game.id}`} className={clsx(rowClass, "hover:bg-charcoal/5 dark:hover:bg-white/5")}>
      <div className="flex min-w-0 items-center gap-2">
        {dateLabel && <span className="shrink-0 text-xs text-textSecondary">{dateLabel}</span>}
        <span className="truncate text-textPrimary dark:text-white">
          <TeamName side={game.away} /> <span className="text-textSecondary">@</span> <TeamName side={game.home} />
        </span>
      </div>
      {game.result ? (
        <span className="shrink-0 rounded-full bg-charcoal/5 px-2 py-0.5 text-xs font-semibold dark:bg-white/10">
          {game.result.awayScore}-{game.result.homeScore}
        </span>
      ) : (
        <span className="shrink-0 text-xs text-textSecondary/60">Upcoming</span>
      )}
    </Link>
  );
}

export default LeagueGameRow;
