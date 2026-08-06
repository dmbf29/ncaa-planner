import { Link } from "react-router-dom";
import Card from "./Card";
import AllAmericanTierList from "./AllAmericanTierList";

function AllAmericansSnapshot({ allAmericans, coachedConferences, dynastyId, seasonId }) {
  const relevant = (allAmericans?.conferences || []).filter((c) => coachedConferences.includes(c.conference));

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">All-Americans</h3>
        <Link
          to={`/dynasty/${dynastyId}/seasons/${seasonId}/all-americans`}
          className="text-xs text-white/70 hover:text-white hover:underline"
        >
          View full &rarr;
        </Link>
      </div>
      {relevant.length > 0 ? (
        relevant.map((conference) => (
          <div key={conference.conference} className="border-b border-border last:border-0 dark:border-darkborder">
            <p className="px-4 pt-3 text-xs font-semibold uppercase tracking-wide text-textSecondary">
              {conference.conference}
            </p>
            <AllAmericanTierList tiers={conference.tiers} />
          </div>
        ))
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No All-Americans entered yet for this season.</p>
      )}
    </Card>
  );
}

export default AllAmericansSnapshot;
