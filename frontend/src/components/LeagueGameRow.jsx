import { Link } from "react-router-dom";
import { clsx } from "clsx";

export const weekLabel = (week) => week.name || (week.number === 0 ? "Week 0" : `Week ${week.number}`);

const gameDateLabel = (time) =>
  time ? new Date(time).toLocaleDateString(undefined, { month: "short", day: "numeric" }) : null;

function TeamName({ side }) {
  return (
    <span className="inline-flex items-center gap-1">
      {side.name}
      {side.coachedByUs ? <i className="fa-solid fa-gamepad text-[10px] text-burnt/80" title="User-coached" /> : null}
    </span>
  );
}

function LeagueGameRow({ game, linkToGame }) {
  const dateLabel = gameDateLabel(game.time);

  const content = (
    <>
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
    </>
  );

  const rowClass =
    "flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60";

  if (linkToGame) {
    return (
      <Link to={`/dynasty/games/${game.id}`} className={clsx(rowClass, "hover:bg-charcoal/5 dark:hover:bg-white/5")}>
        {content}
      </Link>
    );
  }

  return <div className={rowClass}>{content}</div>;
}

export default LeagueGameRow;
