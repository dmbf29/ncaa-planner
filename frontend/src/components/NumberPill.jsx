import { clsx } from "clsx";

function NumberPill({ label, value, bold = null }) {
  const positionGroupShortLabels = {
    Quarterbacks: "QB",
    "Running Backs": "RB",
    "Wide Receivers": "WR",
    "Tight Ends": "TE",
    "Offensive Line": "OL",
    "Defensive Line": "DL",
    Linebackers: "LB",
    Secondary: "DB",
    "Kickers/Punters": "K/P",
  };

  const positionAverageToneClasses = {
    muted: "bg-textSecondary/10 text-gray-500 text-shadow-lg",
    positive: "bg-success/10 text-gray-500 text-shadow-lg",
    warning: "bg-warning/10 text-gray-500 text-shadow-lg",
    danger: "bg-danger/10 text-gray-500 text-shadow-lg",
  };

  const positionAverageTone = (value) => {
    if (value == null) return "muted";
    if (value >= 80) return "positive";
    if (value < 70) return "danger";
    return "warning";
  };

  return (
    <div
      key={label}
      title={label}
      className={clsx(
        "flex items-center justify-between gap-1 rounded-md border border-border px-2 py-1.5 text-xs dark:border-darkborder",
        positionAverageToneClasses[positionAverageTone(value)],
      )}
    >
      <span
        className={clsx(
          "text-textSecondary",
          bold && "font-bold text-gray-600",
        )}
      >{positionGroupShortLabels[label] || label}</span>
      <span
        className={clsx(
          "shrink-0 rounded-full px-2 py-0.5 font-medium border border-1 border-gray-300",
          bold && "font-bold",
        )}
      >
        {value ?? "—"}
      </span>
    </div>
  );
}

export default NumberPill;
