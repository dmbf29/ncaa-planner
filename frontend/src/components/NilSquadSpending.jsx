import Card from "./Card";

// NIL spend is entered in the game's abstract "points"; the dollar figure
// is the same conversion the Team Breakdown broadcast uses (see
// TeamBreakdownSerializer::DOLLARS_PER_NIL_POINT) and comes pre-computed
// from the dashboard serializer as `dollars`.
function compactDollars(amount) {
  if (amount == null) return "—";
  if (amount >= 1_000_000) return `$${(amount / 1_000_000).toFixed(amount >= 10_000_000 ? 0 : 1)}M`;
  if (amount >= 1_000) return `$${Math.round(amount / 1_000)}K`;
  return `$${amount}`;
}

const fullDollars = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

function PositionBar({ entry, maxPoints }) {
  const width = maxPoints > 0 && entry.points > 0 ? Math.max(2, Math.round((entry.points / maxPoints) * 100)) : 0;

  return (
    <div className="flex items-center gap-2 text-xs">
      <span className="w-9 shrink-0 text-textSecondary">{entry.position}</span>
      <div className="h-2 flex-1 overflow-hidden rounded-full bg-olive/10 dark:bg-white/10">
        <div className="h-full rounded-full bg-olive" style={{ width: `${width}%` }} />
      </div>
      <span className="w-12 shrink-0 text-right font-semibold text-textPrimary dark:text-white">
        {compactDollars(entry.dollars)}
      </span>
    </div>
  );
}

function TeamSpendBlock({ team }) {
  const byPosition = team.nilSpendByPosition || [];
  const maxPoints = byPosition.reduce((max, entry) => Math.max(max, entry.points || 0), 0);

  return (
    <div className="space-y-2 border-b border-border px-4 py-3 last:border-0 dark:border-darkborder">
      <div className="flex items-baseline justify-between gap-2">
        <span className="truncate font-varsity text-sm uppercase tracking-[0.04em] text-textPrimary dark:text-white">
          {team.college.alternateName || team.college.name}
        </span>
        <span className="shrink-0 text-right">
          <span className="text-sm font-bold text-textPrimary dark:text-white">
            {team.nilSpendDollars != null ? fullDollars.format(team.nilSpendDollars) : "—"}
          </span>
          {team.nilSpend != null && (
            <span className="ml-1 text-xs text-textSecondary">· {team.nilSpend} pts</span>
          )}
        </span>
      </div>
      {byPosition.length > 0 ? (
        <div className="space-y-1">
          {byPosition.map((entry) => (
            <PositionBar key={entry.position} entry={entry} maxPoints={maxPoints} />
          ))}
        </div>
      ) : (
        <p className="text-xs italic text-textSecondary/70">No position breakdown uploaded.</p>
      )}
    </div>
  );
}

function NilSquadSpending({ teams }) {
  const funded = (teams || []).filter((team) => team.nilSpend != null || (team.nilSpendByPosition || []).length > 0);

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">NIL Squad Spending</h3>
      </div>
      {funded.length > 0 ? (
        funded.map((team) => <TeamSpendBlock key={team.id} team={team} />)
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No NIL spend uploaded yet for this season.</p>
      )}
    </Card>
  );
}

export default NilSquadSpending;
