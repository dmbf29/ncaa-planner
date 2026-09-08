import { clsx } from "clsx";
import Card from "./Card";

const CFP_ROUND_LABELS = {
  first_round: "CFP First Round",
  quarterfinal: "CFP Quarterfinal",
  semifinal: "CFP Semifinal",
  championship: "CFP Championship",
};

const MODE_TITLES = {
  awards: "Award Winners",
  bowl_projections: "Bowl Projections",
  recruiting_recap: "Recruiting Recap",
};

function CoachedFlag() {
  return <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />;
}

function TeamName({ team }) {
  if (!team) return <span className="text-textSecondary">TBD</span>;
  return (
    <span className="inline-flex items-center gap-1">
      {team.coachedByUs && <CoachedFlag />}
      {team.rank ? `#${team.rank} ` : ""}
      {team.name}
    </span>
  );
}

function AwardRow({ award }) {
  const college = award.player?.college || award.coach?.college;
  const coachedByUs = award.player?.coachedByUs || award.coach?.coachedByUs;
  const detail = [award.recipientType === "coach" ? "Coach" : award.player?.position, college?.name]
    .filter(Boolean)
    .join(" · ");

  return (
    <div className="border-b border-border/60 py-1.5 last:border-0 dark:border-darkborder/60">
      <p className="text-xs font-semibold uppercase tracking-wide text-textSecondary">{award.award.name}</p>
      <p className="flex items-center gap-1.5 text-sm">
        {coachedByUs && <CoachedFlag />}
        <span className="truncate text-textPrimary dark:text-white">{award.name || "—"}</span>
        {detail && <span className="shrink-0 text-xs text-textSecondary">{detail}</span>}
      </p>
    </div>
  );
}

function BowlProjectionRow({ projection }) {
  const roundLabel = projection.cfpRound ? CFP_ROUND_LABELS[projection.cfpRound] : projection.bowlName;

  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <span
        className={clsx(
          "shrink-0 truncate text-xs",
          projection.cfpRound ? "font-semibold text-burnt" : "text-textSecondary",
        )}
      >
        {roundLabel}
      </span>
      <span className="flex min-w-0 items-center justify-end gap-1 truncate text-xs text-textPrimary dark:text-white">
        <TeamName team={projection.away} />
        <span className="text-textSecondary">at</span>
        <TeamName team={projection.home} />
      </span>
    </div>
  );
}

function starBreakdown(recap) {
  return [5, 4, 3, 2, 1]
    .map((stars) => [stars, recap[`${["one", "two", "three", "four", "five"][stars - 1]}Stars`]])
    .filter(([, count]) => count)
    .map(([stars, count]) => `${count}×${stars}★`)
    .join("  ");
}

function RecruitingRecapRow({ recap }) {
  const stars = starBreakdown(recap);

  return (
    <div className="flex items-center justify-between gap-2 border-b border-border/60 py-1.5 text-sm last:border-0 dark:border-darkborder/60">
      <div className="flex min-w-0 items-center gap-1.5">
        {recap.ranking ? <span className="shrink-0 text-xs font-semibold text-burnt">#{recap.ranking}</span> : null}
        <span className="truncate text-textPrimary dark:text-white">{recap.college.name}</span>
      </div>
      <span className="flex shrink-0 items-center gap-1.5 text-xs text-textSecondary">
        {recap.totalSigned != null && <span>{recap.totalSigned} signed</span>}
        {stars && <span className="text-textSecondary/70">{stars}</span>}
      </span>
    </div>
  );
}

function PostseasonRecap({ postseasonRecap }) {
  const mode = postseasonRecap?.mode || "recruiting_recap";
  const title = MODE_TITLES[mode];

  const awards = postseasonRecap?.awards || [];
  const bowlProjections = postseasonRecap?.bowlProjections || [];
  const recruitingRecap = postseasonRecap?.recruitingRecap || [];

  let body;
  if (mode === "awards") {
    body =
      awards.length > 0 ? (
        awards.map((award) => <AwardRow key={award.id} award={award} />)
      ) : (
        <p className="text-sm text-textSecondary">No award winners recorded yet for this season.</p>
      );
  } else if (mode === "bowl_projections") {
    body =
      bowlProjections.length > 0 ? (
        bowlProjections.map((projection) => <BowlProjectionRow key={projection.id} projection={projection} />)
      ) : (
        <p className="text-sm text-textSecondary">No bowl projections on record yet for this season.</p>
      );
  } else {
    body =
      recruitingRecap.length > 0 ? (
        recruitingRecap.map((recap) => <RecruitingRecapRow key={recap.college.id} recap={recap} />)
      ) : (
        <p className="text-sm text-textSecondary">
          Last season&rsquo;s recruiting classes will show here — then bowl projections, then award winners, as
          the season plays out.
        </p>
      );
  }

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{title}</h3>
      </div>
      <div className="px-4 py-3">{body}</div>
    </Card>
  );
}

export default PostseasonRecap;
