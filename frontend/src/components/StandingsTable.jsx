import Card from "./Card";
import StandingsTableBody from "./StandingsTableBody";

function StandingsTable({ conference, dynastyId, seasonId }) {
  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{conference.conference}</h3>
      </div>
      <div className="overflow-x-auto">
        <StandingsTableBody teams={conference.teams} dynastyId={dynastyId} seasonId={seasonId} />
      </div>
    </Card>
  );
}

export default StandingsTable;
