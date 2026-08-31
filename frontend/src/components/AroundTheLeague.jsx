import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { clsx } from "clsx";
import Card from "./Card";
import LeagueGameRow, { weekLabel } from "./LeagueGameRow";

function WeekPanel({ group, dynastyId, seasonId, bordered }) {
  if (!group) {
    return <p className="text-sm text-textSecondary/60">No earlier week to show.</p>;
  }

  return (
    <div className={bordered ? "sm:border-l sm:border-border sm:pl-4 dark:sm:border-darkborder" : ""}>
      <div className="mb-1.5 flex items-center justify-between gap-2">
        <p className="text-xs font-semibold uppercase tracking-wide text-textSecondary">{weekLabel(group.week)}</p>
        {dynastyId && seasonId && (
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${group.week.number}/games`}
            className="shrink-0 text-xs text-burnt hover:underline"
          >
            View full week &rarr;
          </Link>
        )}
      </div>
      <div className="max-h-96 overflow-y-auto">
        {group.games.length > 0 ? (
          group.games.map((game) => <LeagueGameRow key={game.id} game={game} />)
        ) : (
          <p className="text-sm text-textSecondary">No other games to show for this week.</p>
        )}
      </div>
    </div>
  );
}

function AroundTheLeague({ weeks, currentWeekNumber, dynastyId, seasonId }) {
  const availableWeeks = weeks || [];
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const defaultIndex = availableWeeks.findIndex((w) => w.week.number === currentWeekNumber);
    setIndex(defaultIndex >= 0 ? defaultIndex : 0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentWeekNumber, weeks]);

  const currentGroup = availableWeeks[index];
  const previousGroup = index > 0 ? availableWeeks[index - 1] : null;
  const atStart = index <= 0;
  const atEnd = index >= availableWeeks.length - 1;

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Around the League</h3>
        {currentGroup && (
          <div className="flex items-center gap-2 text-sm">
            <button
              type="button"
              onClick={() => setIndex((i) => Math.max(i - 1, 0))}
              disabled={atStart}
              aria-label="Previous week"
              className={clsx("px-1", atStart ? "cursor-not-allowed text-white/30" : "text-white/80 hover:text-white")}
            >
              <i className="fa-solid fa-chevron-left" />
            </button>
            <span className="min-w-[5.5rem] text-center normal-case">{weekLabel(currentGroup.week)}</span>
            <button
              type="button"
              onClick={() => setIndex((i) => Math.min(i + 1, availableWeeks.length - 1))}
              disabled={atEnd}
              aria-label="Next week"
              className={clsx("px-1", atEnd ? "cursor-not-allowed text-white/30" : "text-white/80 hover:text-white")}
            >
              <i className="fa-solid fa-chevron-right" />
            </button>
          </div>
        )}
      </div>
      {currentGroup ? (
        <div className="grid gap-4 px-4 py-3 sm:grid-cols-2">
          <WeekPanel group={previousGroup} dynastyId={dynastyId} seasonId={seasonId} />
          <WeekPanel group={currentGroup} dynastyId={dynastyId} seasonId={seasonId} bordered />
        </div>
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No games scheduled yet this season.</p>
      )}
    </Card>
  );
}

export default AroundTheLeague;
