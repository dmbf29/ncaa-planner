import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { clsx } from "clsx";
import Card from "./Card";
import LeagueGameRow, { weekLabel } from "./LeagueGameRow";

function AroundTheLeague({ weeks, currentWeekNumber, dynastyId, seasonId }) {
  const availableWeeks = weeks || [];
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const defaultIndex = availableWeeks.findIndex((w) => w.week.number === currentWeekNumber);
    setIndex(defaultIndex >= 0 ? defaultIndex : 0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentWeekNumber, weeks]);

  const group = availableWeeks[index];
  const atStart = index <= 0;
  const atEnd = index >= availableWeeks.length - 1;

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Around the League</h3>
        {group && (
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
            <span className="min-w-[5.5rem] text-center normal-case">{weekLabel(group.week)}</span>
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
      {group ? (
        <div className="px-4 py-3">
          {dynastyId && seasonId && (
            <div className="mb-1.5 flex justify-end text-xs">
              <Link
                to={`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${group.week.number}/games`}
                className="text-burnt hover:underline"
              >
                View full week &rarr;
              </Link>
            </div>
          )}
          <div className="max-h-96 overflow-y-auto">
            {group.games.length > 0 ? (
              group.games.map((game) => <LeagueGameRow key={game.id} game={game} />)
            ) : (
              <p className="text-sm text-textSecondary">No other games to show for this week.</p>
            )}
          </div>
        </div>
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No games scheduled yet this season.</p>
      )}
    </Card>
  );
}

export default AroundTheLeague;
