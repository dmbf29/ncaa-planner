// Read-only week-by-week view of a coached team's schedule (weeks 0-13), shared by the commissioner's links page and
// the coach's own page. `onSelect` makes open weeks clickable; `selectedWeekId` highlights one.
function SlotBody({ slot }) {
  if (slot.state === "bye") return <p className="text-textSecondary">Bye</p>;
  if (slot.state === "locked") {
    return (
      <p className="font-semibold text-textPrimary dark:text-white">
        {slot.isAway ? "@" : "vs"} {slot.opponent.name}
      </p>
    );
  }
  if (slot.pick) {
    return (
      <p className="font-semibold text-textPrimary dark:text-white">
        {slot.pick.isAway ? "@" : "vs"} {slot.pick.opponent.name}
        {slot.pick.shared && <span className="ml-1 text-xs font-normal text-textSecondary">(set by opponent)</span>}
      </p>
    );
  }
  return <p className="text-burnt">Open</p>;
}

function ScheduleGrid({ slots, onSelect, selectedWeekId }) {
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
      {slots.map((slot) => {
        const selectable = onSelect && slot.state === "open";
        const classes = `rounded-md border p-2 text-left text-sm ${
          slot.weekId === selectedWeekId ? "border-burnt ring-1 ring-burnt" : "border-border dark:border-darkborder"
        } ${selectable ? "transition hover:bg-border/30 dark:hover:bg-white/10" : ""}`;
        const content = (
          <>
            <p className="text-xs uppercase tracking-wide text-textSecondary">Week {slot.weekNumber}</p>
            <SlotBody slot={slot} />
          </>
        );
        return selectable ? (
          <button key={slot.weekId} type="button" onClick={() => onSelect(slot)} className={classes}>
            {content}
          </button>
        ) : (
          <div key={slot.weekId} className={classes}>
            {content}
          </div>
        );
      })}
    </div>
  );
}

export default ScheduleGrid;
