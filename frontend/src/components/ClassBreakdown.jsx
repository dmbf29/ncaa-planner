import { useMemo } from "react";

const STATUS_FLAG_NAMES = ["recruit", "commited"];

const classPalette = {
  SR: { text: "text-[#991B1B]", bg: "bg-[#991B1B1a]", border: "border-[#991B1B33]" },
  JR: { text: "text-[#c99b2b]", bg: "bg-[#c99b2b1a]", border: "border-[#c99b2b33]" },
  SO: { text: "text-[#7595ba]", bg: "bg-[#7595ba1a]", border: "border-[#7595ba33]" },
  FR: { text: "text-[#4C7A4F]", bg: "bg-[#4C7A4F1A]", border: "border-[#4C7A4F33]" },
};

const neutralPalette = { text: "text-textSecondary", bg: "bg-textSecondary/10", border: "border-textSecondary/20" };
// const leavingPalette = { text: "text-danger", bg: "bg-danger/10", border: "border-danger/30" };
const LEAVING_FLAG_NAMES = ["dealbreaker", "draft"];

const flagPalette = (color) => {
  if (!color) return neutralPalette;
  return { text: "", bg: "", border: "", style: { color, backgroundColor: `${color}1A`, borderColor: `${color}33` } };
};

function ClassBreakdown({ players, flags }) {
  const { counts, nilTotals } = useMemo(() => {
    const result = { SR: 0, JR: 0, SO: 0, FR: 0, Commited: 0, Recruits: 0 };
    const nil = { SR: 0, JR: 0, SO: 0, FR: 0, Commited: 0, Recruits: 0 };
    (players || []).forEach((player) => {
      const nilAmount = Number(player.nilAmount ?? player.nil_amount) || 0;
      const flagNames = (player.flags || []).map((f) => f.name);
      if (flagNames.includes("commited")) {
        result.Commited += 1;
        nil.Commited += nilAmount;
        return;
      }
      if (flagNames.includes("recruit")) {
        result.Recruits += 1;
        nil.Recruits += nilAmount;
        return;
      }
      const cls = (player.classYear ?? player.class_year ?? "").replace("(RS)", "");
      if (Object.prototype.hasOwnProperty.call(result, cls)) {
        result[cls] += 1;
        nil[cls] += nilAmount;
      }
    });
    return { counts: result, nilTotals: nil };
  }, [players]);

  const commitedColor = (flags || []).find((f) => STATUS_FLAG_NAMES.includes(f.name) && f.name === "commited")?.color;
  const recruitColor = (flags || []).find((f) => STATUS_FLAG_NAMES.includes(f.name) && f.name === "recruit")?.color;

  const teamCount = counts.SR + counts.JR + counts.SO + counts.FR;
  const teamNilTotal = nilTotals.SR + nilTotals.JR + nilTotals.SO + nilTotals.FR;

  const leavingStats = useMemo(() => {
    let value = 0;
    let nilTotal = 0;
    (players || []).forEach((player) => {
      const flagNames = (player.flags || []).map((f) => f.name.toLowerCase());
      const cls = (player.classYear ?? player.class_year ?? "").replace("(RS)", "");
      const isLeaving = cls === "SR" || flagNames.some((name) => LEAVING_FLAG_NAMES.includes(name));
      if (isLeaving) {
        value += 1;
        nilTotal += Number(player.nilAmount ?? player.nil_amount) || 0;
      }
    });
    return { value, nilTotal };
  }, [players]);

  const extraFlagStats = useMemo(() => {
    return (flags || [])
      .filter((flag) => !STATUS_FLAG_NAMES.includes(flag.name))
      .map((flag) => {
        const matched = (players || []).filter((p) => (p.flags || []).some((pf) => pf.id === flag.id));
        const nilTotal = matched.reduce((sum, p) => sum + (Number(p.nilAmount ?? p.nil_amount) || 0), 0);
        return { label: flag.name, value: matched.length, nilTotal, palette: flagPalette(flag.color) };
      })
      .filter((stat) => stat.value > 0);
  }, [flags, players]);

  const classStats = [
    { label: "Team", value: teamCount, nilTotal: teamNilTotal, palette: neutralPalette },
    { label: "SR", value: counts.SR, nilTotal: nilTotals.SR, palette: classPalette.SR },
    { label: "JR", value: counts.JR, nilTotal: nilTotals.JR, palette: classPalette.JR },
    { label: "SO", value: counts.SO, nilTotal: nilTotals.SO, palette: classPalette.SO },
    { label: "FR", value: counts.FR, nilTotal: nilTotals.FR, palette: classPalette.FR },
  ];

  const otherStats = [
    { label: "Leaving", value: leavingStats.value, nilTotal: leavingStats.nilTotal, palette: neutralPalette },
    ...extraFlagStats,
    { label: "Commited", value: counts.Commited, nilTotal: nilTotals.Commited, palette: flagPalette(commitedColor) },
    { label: "Recruits", value: counts.Recruits, nilTotal: nilTotals.Recruits, palette: flagPalette(recruitColor) },
  ];

  if (!players || players.length === 0) return null;

  const renderTile = ({ label, value, nilTotal, palette }) => (
    <div
      key={label}
      style={palette.style}
      className={`flex flex-col items-center gap-0.5 rounded-lg border px-2 py-2 w-20 ${palette.text} ${palette.bg} ${palette.border}`}
    >
      <span className="text-[10px] font-crayon uppercase tracking-wide text-center leading-tight">{label}</span>
      <span className="text-lg font-bold leading-none">{value}</span>
      <span className="text-xs font-light leading-none mt-1">
        <i className="fa-solid fa-diamond mr-1"></i>
        {nilTotal.toLocaleString()}
      </span>
    </div>
  );

  return (
    <div>
      <p className="font-crayon text-xs uppercase tracking-[0.14em] text-textSecondary mb-2 text-right">Class Breakdown</p>
      <div className="flex flex-wrap gap-2 justify-end">{classStats.map(renderTile)}</div>
      <div className="flex flex-wrap gap-2 justify-end mt-2">{otherStats.map(renderTile)}</div>
    </div>
  );
}

export default ClassBreakdown;
