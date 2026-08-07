import { Link } from "react-router-dom";
import Card from "./Card";
import LeagueGameRow, { weekLabel } from "./LeagueGameRow";

function WeekPanel({ tag, group, dynastyId, seasonId }) {
  return (
    <div className="border-b border-border px-4 py-3 last:border-0 sm:border-b-0 dark:border-darkborder">
      <p className="mb-1.5 flex items-center justify-between text-xs font-semibold uppercase tracking-wide text-textSecondary">
        <span>
          {tag} &mdash; {weekLabel(group.week)}
        </span>
        {dynastyId && seasonId && (
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${group.week.number}/games`}
            className="normal-case text-burnt hover:underline"
          >
            View full week &rarr;
          </Link>
        )}
      </p>
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

function AroundTheLeague({ weeks, lastPlayedWeekNumber, dynastyId, seasonId }) {
  const availableWeeks = weeks || [];
  const hasPlayedWeek = lastPlayedWeekNumber != null;
  const previewNumber = hasPlayedWeek ? lastPlayedWeekNumber + 1 : 0;

  const panels = [
    hasPlayedWeek && { tag: "Review", group: availableWeeks.find((w) => w.week.number === lastPlayedWeekNumber) },
    { tag: "Preview", group: availableWeeks.find((w) => w.week.number === previewNumber) },
  ].filter((panel) => panel && panel.group);

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Around the League</h3>
      </div>
      {panels.length > 0 ? (
        <div className="sm:grid sm:grid-cols-2 sm:divide-x sm:divide-border dark:sm:divide-darkborder">
          {panels.map(({ tag, group }) => (
            <WeekPanel key={group.week.id} tag={tag} group={group} dynastyId={dynastyId} seasonId={seasonId} />
          ))}
        </div>
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No games scheduled yet this season.</p>
      )}
    </Card>
  );
}

export default AroundTheLeague;
