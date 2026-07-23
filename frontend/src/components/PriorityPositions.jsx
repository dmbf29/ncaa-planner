function PriorityPositions({ needs, squadList, onSelectNeed, onClearAll }) {
  if (needs.length === 0) return null;

  // Group by boardId
  const seen = new Map();
  needs.forEach((need) => {
    if (!seen.has(need.boardId)) seen.set(need.boardId, { need, count: 0 });
    seen.get(need.boardId).count += 1;
  });
  // Sort by squad order (squadList index) then board sortOrder
  const squadOrder = (squadId) => {
    const idx = squadList.findIndex((sq) => String(sq.id) === String(squadId));
    return idx === -1 ? 999 : idx;
  };
  const sorted = Array.from(seen.values()).sort((a, b) => {
    const sqDiff = squadOrder(a.need.squadId) - squadOrder(b.need.squadId);
    if (sqDiff !== 0) return sqDiff;
    return a.need.boardSortOrder - b.need.boardSortOrder;
  });
  const offenseSquadId = squadList[0]?.id;

  return (
    <div className="space-y-2">
      <h3 className="text-xs font-semibold text-textSecondary uppercase tracking-[0.12em] flex items-center gap-2">
        <span><span className="font-crayon">Priority Positions</span> ({needs.length})</span>
        <button
          type="button"
          onClick={onClearAll}
          title="Clear all priority positions"
          className="text-textSecondary/50 hover:text-error transition-colors"
        >
          <i className="fa-solid fa-trash-can" aria-hidden="true" />
        </button>
      </h3>
      <div className="flex flex-wrap gap-1">
        {sorted.map(({ need, count }) => {
          const isOffense = String(need.squadId) === String(offenseSquadId);
          return (
            <button
              key={need.boardId}
              type="button"
              onClick={() => onSelectNeed(need)}
              className={`inline-flex items-center rounded-full border px-2 bg-white py-1 text-xs font-semibold shadow-sm ${
                need.resolved
                  ? "border-success/70 text-success"
                  : isOffense
                  ? "border-border text-burnt dark:border-darkborder dark:bg-darksurface"
                  : "border-border text-charcoal dark:border-darkborder dark:bg-darksurface dark:text-white"
              }`}
            >
              {need.boardName}{count > 1 ? ` (${count})` : ""}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default PriorityPositions;
