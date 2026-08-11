import { useState } from "react";

const TIER_LABELS = { 1: "First Team", 2: "Second Team" };
const PAGE_SIZE = 5;

function HonoreeRow({ honoree }) {
  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <div className="flex min-w-0 items-center gap-1.5">
        <span className="w-8 shrink-0 text-xs text-textSecondary">{honoree.position}</span>
        <span className="truncate text-textPrimary dark:text-white">{honoree.name}</span>
        {honoree.coachedByUs && <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />}
      </div>
      <span className="shrink-0 truncate text-xs text-textSecondary">{honoree.college.name}</span>
    </div>
  );
}

function PaginatedHonorees({ honorees }) {
  const [page, setPage] = useState(0);
  const totalPages = Math.max(1, Math.ceil(honorees.length / PAGE_SIZE));
  const start = page * PAGE_SIZE;
  const visible = honorees.slice(start, start + PAGE_SIZE);

  return (
    <div>
      {visible.map((honoree) => (
        <HonoreeRow key={honoree.id} honoree={honoree} />
      ))}
      {totalPages > 1 && (
        <div className="mt-1.5 flex items-center justify-between text-xs text-textSecondary">
          <button
            type="button"
            onClick={() => setPage((p) => Math.max(0, p - 1))}
            disabled={page === 0}
            className="font-semibold hover:text-burnt disabled:opacity-30"
          >
            &larr; Prev
          </button>
          <span>
            {page + 1} / {totalPages}
          </span>
          <button
            type="button"
            onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
            disabled={page >= totalPages - 1}
            className="font-semibold hover:text-burnt disabled:opacity-30"
          >
            Next &rarr;
          </button>
        </div>
      )}
    </div>
  );
}

function AllAmericanTierList({ tiers }) {
  const tierKeys = Object.keys(tiers || {}).sort();

  return (
    <div className="grid gap-x-6 gap-y-3 px-4 py-3 sm:grid-cols-2">
      {tierKeys.map((tier) => (
        <div key={tier}>
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
            {TIER_LABELS[tier] || `Tier ${tier}`}
          </p>
          {tiers[tier].length > 0 ? <PaginatedHonorees honorees={tiers[tier]} /> : <p className="text-sm text-textSecondary/60">—</p>}
        </div>
      ))}
    </div>
  );
}

export default AllAmericanTierList;
