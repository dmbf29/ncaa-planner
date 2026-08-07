import { Link } from "react-router-dom";
import Card from "./Card";
import Top25TableBody from "./Top25TableBody";

function Top25Snapshot({ top25, dynastyId, seasonId }) {
  const week = top25?.week;
  const rankings = top25?.rankings || [];

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Top 25</h3>
        {week && dynastyId && seasonId && (
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${week.number}/rankings`}
            className="text-xs text-white/70 hover:text-white hover:underline"
          >
            View full &rarr;
          </Link>
        )}
      </div>
      {rankings.length > 0 ? (
        <div className="overflow-x-auto">
          <Top25TableBody rankings={rankings} />
        </div>
      ) : (
        <p className="px-4 py-3 text-sm text-textSecondary">No rankings entered yet for this season.</p>
      )}
    </Card>
  );
}

export default Top25Snapshot;
