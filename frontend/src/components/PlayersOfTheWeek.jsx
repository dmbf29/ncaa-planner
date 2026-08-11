import Card from "./Card";
import { weekLabel } from "./LeagueGameRow";

function scopeLabel(honoree) {
  return honoree.national ? "National" : honoree.conference;
}

function PlayerOfTheWeekRow({ honoree }) {
  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="shrink-0 rounded-full bg-burnt/10 px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-burnt">
          {scopeLabel(honoree)} {honoree.side === "offensive" ? "Off" : "Def"}
        </span>
        <span className="text-xs text-textSecondary">{honoree.position}</span>
        <span className="truncate text-textPrimary dark:text-white">{honoree.name}</span>
      </div>
      <span className="shrink-0 truncate text-xs text-textSecondary">
        {honoree.college.rank ? `#${honoree.college.rank} ` : ""}
        {honoree.college.name}
      </span>
    </div>
  );
}

function PlayersOfTheWeekGroup({ group }) {
  return (
    <div className="mb-3 last:mb-0">
      <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">{weekLabel(group.week)}</p>
      {group.honorees.map((honoree) => (
        <PlayerOfTheWeekRow key={honoree.id} honoree={honoree} />
      ))}
    </div>
  );
}

function PlayersOfTheWeek({ playersOfTheWeek }) {
  const weeks = playersOfTheWeek?.weeks || [];

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Players of the Week</h3>
      </div>
      <div className="px-4 py-3">
        {weeks.length > 0 ? (
          weeks.map((group) => <PlayersOfTheWeekGroup key={group.week.id} group={group} />)
        ) : (
          <p className="text-sm text-textSecondary">No Players of the Week entered yet for this season.</p>
        )}
      </div>
    </Card>
  );
}

export default PlayersOfTheWeek;
