// Overall rating → heat-map chip. Ascending tiers: black, two reds, two
// ambers, two greens, purple for elite. Shared by the All Players search
// page and the team roster page so the two read the same at a glance.
const OVERALL_TIERS = [
  { min: 90, className: "bg-purple-600 text-white" },
  { min: 85, className: "bg-emerald-400 text-white" },
  { min: 80, className: "bg-green-700 text-white" },
  { min: 75, className: "bg-yellow-400 text-neutral-900" },
  { min: 70, className: "bg-amber-500 text-neutral-900" },
  { min: 65, className: "bg-red-500 text-white" },
  { min: 60, className: "bg-red-700 text-white" },
  { min: 0, className: "bg-neutral-900 text-white" },
];

function OverallBadge({ value }) {
  if (value == null) return <span className="text-textSecondary">—</span>;
  const tier = OVERALL_TIERS.find((t) => value >= t.min) ?? OVERALL_TIERS.at(-1);
  return (
    <span
      className={`text-shadow-lg inline-flex w-9 items-center justify-center rounded-md px-2 py-1 text-sm font-bold tabular-nums ${tier.className}`}
    >
      {value}
    </span>
  );
}

export default OverallBadge;
