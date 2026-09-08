import Card from "./Card";
import { weekLabel } from "./LeagueGameRow";

// The screen's CLASS column, kept verbatim by the backend: "HS" for a high
// schooler, "JC (JR)"/"JC (SO)" for juco, or a plain class year for a
// portal transfer's year at their old school. Shorten "JC (..)" for the
// dense list; leave the rest as-is.
function classYearLabel(recruit) {
  if (!recruit.classYear) return recruit.transfer ? "Transfer" : null;
  return recruit.classYear.replace(/^JC\s*\((\w+)\)$/i, "JUCO $1");
}

function RecruitRow({ recruit }) {
  const classLabel = classYearLabel(recruit);

  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <div className="flex min-w-0 items-center gap-1.5">
        {recruit.starRating ? (
          <span className="shrink-0 text-xs font-semibold text-burnt">{recruit.starRating}★</span>
        ) : null}
        <span className="text-xs text-textSecondary">{recruit.position}</span>
        <span className="truncate text-textPrimary dark:text-white">{recruit.name}</span>
        {recruit.transfer && (
          <i className="fa-solid fa-right-left shrink-0 text-[10px] text-textSecondary" title="Portal transfer" />
        )}
      </div>
      <span className="flex shrink-0 items-center gap-1.5 text-xs text-textSecondary">
        {classLabel && <span>{classLabel}</span>}
        {recruit.state && <span>{recruit.state}</span>}
        <span className="text-textSecondary/70">{weekLabel(recruit.week)}</span>
      </span>
    </div>
  );
}

function TeamRecruits({ group }) {
  return (
    <div className="mb-3 last:mb-0">
      <p className="mb-1 flex items-center justify-between text-xs font-semibold uppercase tracking-wide text-textSecondary">
        <span>{group.college.name}</span>
        <span className="normal-case text-textSecondary/70">
          {group.recruits.length} signed
        </span>
      </p>
      {group.recruits.map((recruit) => (
        <RecruitRow key={recruit.id} recruit={recruit} />
      ))}
    </div>
  );
}

function SignedRecruits({ recruits }) {
  const groups = (recruits || []).filter((group) => group.recruits.length > 0);

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Recruits</h3>
      </div>
      <div className="px-4 py-3">
        {groups.length > 0 ? (
          groups.map((group) => <TeamRecruits key={group.college.id} group={group} />)
        ) : (
          <p className="text-sm text-textSecondary">No recruits signed yet this season.</p>
        )}
      </div>
    </Card>
  );
}

export default SignedRecruits;
