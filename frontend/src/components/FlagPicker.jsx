function FlagPicker({ flags, selectedIds = [], onToggle, disabled }) {
  if (!flags?.length) return null;

  return (
    <div className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
      <span>Flags</span>
      <div className="flex flex-wrap gap-2">
        {flags.map((flag) => {
          const selected = selectedIds.includes(flag.id);
          return (
            <button
              key={flag.id}
              type="button"
              onClick={() => onToggle(flag.id)}
              disabled={disabled}
              aria-pressed={selected}
              title={selected ? `Remove ${flag.name} flag` : `Add ${flag.name} flag`}
              className={`inline-flex items-center gap-2 rounded-md border px-3 py-2 text-sm font-semibold capitalize transition ${
                selected
                  ? "shadow-card"
                  : "border-border text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              }`}
              style={
                selected
                  ? { borderColor: flag.color, color: flag.color, backgroundColor: `${flag.color}1a` }
                  : undefined
              }
            >
              <i className={flag.icon} style={selected ? { color: flag.color } : undefined}></i>
              <span>{flag.name}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default FlagPicker;
