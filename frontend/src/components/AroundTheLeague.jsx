import { useState } from "react";
import { Link } from "react-router-dom";
import Card from "./Card";
import LeagueGameRow, { weekLabel } from "./LeagueGameRow";

function AroundTheLeague({ weeks, currentWeekNumber, dynastyId, seasonId }) {
  const availableWeeks = weeks || [];
  const defaultNumber =
    availableWeeks.find((w) => w.week.number === currentWeekNumber)?.week.number ?? availableWeeks[0]?.week.number;
  const [selectedNumber, setSelectedNumber] = useState(defaultNumber);

  const active = availableWeeks.find((w) => w.week.number === selectedNumber) || availableWeeks[0];

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Around the League</h3>
        {availableWeeks.length > 1 && (
          <select
            value={active?.week.number ?? ""}
            onChange={(e) => setSelectedNumber(Number(e.target.value))}
            className="rounded-md border border-white/20 bg-white/10 px-2 py-1 text-xs text-white focus:outline-none"
          >
            {availableWeeks.map(({ week }) => (
              <option key={week.id} value={week.number} className="text-charcoal">
                {weekLabel(week)}
              </option>
            ))}
          </select>
        )}
      </div>
      <div className="max-h-96 overflow-y-auto px-4 py-3">
        {active && (
          <p className="mb-1.5 flex items-center justify-between text-xs font-semibold uppercase tracking-wide text-textSecondary">
            <span>{weekLabel(active.week)}</span>
            {dynastyId && seasonId && (
              <Link
                to={`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${active.week.number}/games`}
                className="normal-case text-burnt hover:underline"
              >
                View full week &rarr;
              </Link>
            )}
          </p>
        )}
        {active && active.games.length > 0 ? (
          <div className="grid gap-x-6 sm:grid-cols-2">
            {active.games.map((game) => (
              <LeagueGameRow key={game.id} game={game} />
            ))}
          </div>
        ) : (
          <p className="text-sm text-textSecondary">No other games to show for this week.</p>
        )}
      </div>
    </Card>
  );
}

export default AroundTheLeague;
