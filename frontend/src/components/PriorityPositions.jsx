function PriorityPositions({ boards, squadList, onSelectBoard, onClearAll }) {
  const prioritized = (boards || []).filter((b) => (b.priorities || 0) > 0);
  if (prioritized.length === 0) return null;

  const squadOrder = (squadId) => {
    const idx = squadList.findIndex((sq) => String(sq.id) === String(squadId));
    return idx === -1 ? 999 : idx;
  };
  const sorted = [...prioritized].sort((a, b) => {
    const sqDiff = squadOrder(a.squadId ?? a.squad_id) - squadOrder(b.squadId ?? b.squad_id);
    if (sqDiff !== 0) return sqDiff;
    return (a.sortOrder ?? a.sort_order ?? 0) - (b.sortOrder ?? b.sort_order ?? 0);
  });
  const totalCount = prioritized.reduce((sum, b) => sum + (b.priorities || 0), 0);
  const offenseSquadId = squadList[0]?.id;

  return (
    <div className="space-y-2">
      <h3 className="text-xs font-semibold text-textSecondary uppercase tracking-[0.12em] flex items-center gap-2">
        <span><span className="font-crayon">Priority Positions</span> ({totalCount})</span>
        <button
          type="button"
          onClick={onClearAll}
          title="Clear all priority positions"
          className="text-textSecondary/50 hover:text-error transition-colors"
        >
          <i className="fa-solid fa-trash-can" aria-hidden="true" />
        </button>
      </h3>
      <div className="flex flex-wrap gap-0.5">
        {sorted
          .filter((board) => String(board.squadId ?? board.squad_id) === String(offenseSquadId))
          .map((board) => (
            <button
              key={board.id}
              type="button"
              onClick={() => onSelectBoard(board)}
              className="inline-flex items-center justify-center w-10 truncate rounded-full border px-8 bg-white py-1 text-xs font-semibold shadow-sm border-border text-burnt dark:border-darkborder dark:bg-darksurface"
            >
              {board.name} ({board.priorities})
            </button>
          ))}
      </div>
      <div className="flex flex-wrap gap-0.5">
        {sorted
          .filter((board) => String(board.squadId ?? board.squad_id) !== String(offenseSquadId))
          .map((board) => (
            <button
              key={board.id}
              type="button"
              onClick={() => onSelectBoard(board)}
              className="inline-flex items-center justify-center w-10 truncate rounded-full border px-8 bg-white py-1 text-xs font-semibold shadow-sm border-border text-charcoal dark:border-darkborder dark:bg-darksurface dark:text-white"
            >
              {board.name} ({board.priorities})
            </button>
          ))}
      </div>
    </div>
  );
}

export default PriorityPositions;
