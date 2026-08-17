import Card from "./Card";
import { weekLabel } from "./LeagueGameRow";

function HeismanCandidateRow({ candidate }) {
  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="text-xs text-textSecondary">{candidate.position}</span>
        <span className="truncate text-textPrimary dark:text-white">{candidate.name}</span>
      </div>
      <span className="flex shrink-0 items-center gap-1 truncate text-xs text-textSecondary">
        {candidate.coachedByUs && <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />}
        {candidate.college.rank ? `#${candidate.college.rank} ` : ""}
        {candidate.college.name}
      </span>
    </div>
  );
}

function HeismanWeekGroup({ group }) {
  return (
    <div className="mb-3 last:mb-0">
      <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">{weekLabel(group.week)}</p>
      {group.candidates.map((candidate) => (
        <HeismanCandidateRow key={candidate.id} candidate={candidate} />
      ))}
    </div>
  );
}

function HeismanWatch({ heismanWatch }) {
  const winner = heismanWatch?.winner;
  const weeks = heismanWatch?.weeks || [];

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Heisman Watch</h3>
      </div>
      <div className="px-4 py-3">
        {winner ? (
          <div className="mb-3 flex items-center justify-between gap-2 rounded-md bg-burnt/10 px-3 py-2">
            <div className="flex min-w-0 items-center gap-1.5">
              <i className="fa-solid fa-trophy text-burnt" />
              <span className="truncate font-semibold text-textPrimary dark:text-white">{winner.name}</span>
            </div>
            <span className="flex shrink-0 items-center gap-1 text-xs text-textSecondary">
              {winner.coachedByUs && <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />}
              {winner.college.rank ? `#${winner.college.rank} ` : ""}
              {winner.college.name}
            </span>
          </div>
        ) : null}
        {weeks.length > 0 ? (
          weeks.map((group) => <HeismanWeekGroup key={group.week.id} group={group} />)
        ) : !winner ? (
          <p className="text-sm text-textSecondary">No Heisman candidates entered yet for this season.</p>
        ) : null}
      </div>
    </Card>
  );
}

export default HeismanWatch;
