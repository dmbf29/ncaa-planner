import { useMemo } from "react";

const NEEDS_FLAG_NAMES = ["dealbreaker", "draft", "replace"];

function BoardCardStats({ players, emptySlots = 0 }) {
  const stats = useMemo(() => {
    const list = players || [];
    const nilValues = list.map((p) => Number(p.nilAmount ?? p.nil_amount) || 0);
    const nilTotal = nilValues.reduce((sum, n) => sum + n, 0);
    const nilAvg = list.length ? nilTotal / list.length : 0;

    const overalls = list
      .map((p) => Number(p.overall))
      .filter((n) => Number.isFinite(n) && n > 0);
    const overallAvg = overalls.length
      ? overalls.reduce((sum, n) => sum + n, 0) / overalls.length
      : null;

    const playerNeeds = list.filter((p) => {
      const cls = (p.classYear ?? p.class_year ?? "").replace("(RS)", "");
      const flagNames = (p.flags || []).map((f) => f.name.toLowerCase());
      return cls === "SR" || flagNames.some((name) => NEEDS_FLAG_NAMES.includes(name));
    }).length;

    const needs = playerNeeds + (emptySlots || 0);

    return { nilTotal, nilAvg, overallAvg, needs };
  }, [players, emptySlots]);

  if (!players || players.length === 0) return null;

  return (
    <div className="flex flex-wrap items-center gap-x-2 gap-y-1 rounded-lg px-2 py-1.5 text-[11px] dark:bg-white/5">
      <span
        className="flex items-center gap-1 text-textSecondary dark:text-white/70"
        title="Total NIL"
      >
        <i className="fa-solid fa-diamond text-[9px]" aria-hidden="true" />
        {stats.nilTotal.toLocaleString()} tot
      </span>
      <span
        className="flex items-center gap-1 text-textSecondary dark:text-white/70"
        title="Avg NIL / Player"
      >
        <i className="fa-solid fa-diamond text-[9px]" aria-hidden="true" />
        {Math.round(stats.nilAvg).toLocaleString()} avg
      </span>
      <span
        className="flex items-center gap-1 text-textSecondary dark:text-white/70"
        title="Avg Overall"
      >
        <i className="fa-solid fa-star text-[9px]" aria-hidden="true" />
        {stats.overallAvg ? stats.overallAvg.toFixed(1) : "—"} ovr
      </span>
      {stats.needs > 0 && (
        <span className="flex items-center gap-1 text-danger" title="Needs: Empty Slots, Seniors, Dealbreaker, Draft, Replace">
          <i className="fa-solid fa-triangle-exclamation text-[9px]" aria-hidden="true" />
          {stats.needs}
        </span>
      )}
    </div>
  );
}

export default BoardCardStats;
