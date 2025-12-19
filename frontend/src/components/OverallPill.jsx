function OveralPill({ value, tone = "muted" }) {
  const tones = {
    muted: "bg-charcoal/5 text-textSecondary dark:bg-white/10 dark:text-white/80",
    positive: "bg-success/15 text-success",
    warning: "bg-warning/15 text-warning",
  };

  return (
    <div className={`inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-medium ${tones[tone]}`}>
      <span className="font-semibold text-sm">{value}</span>
    </div>
  );
}

export default OveralPill;
