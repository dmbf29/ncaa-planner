function OveralPill({ value, tone = "muted" }) {
  const tones = {
    muted: "text-textSecondary dark:bg-white/10 dark:text-white/80 border border-border",
    positive: "bg-success/15 text-success",
    warning: "bg-warning/15 text-warning",
  };

  return (
    <div className={`inline-flex items-center gap-2 rounded-full px-2 text-xs ${tones[tone]}`}>
      <span className="font-semibold text-sm">{value}</span>
    </div>
  );
}

export default OveralPill;
