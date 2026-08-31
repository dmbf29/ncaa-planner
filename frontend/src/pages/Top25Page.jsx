import { useEffect, useState } from "react";
import { useNavigate, useParams, Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import Top25TableBody from "../components/Top25TableBody";
import { weekLabel } from "../components/LeagueGameRow";
import { fetchRankings } from "../lib/apiClient";

function Top25Page() {
  const { dynastyId, seasonId, weekNumber } = useParams();
  const navigate = useNavigate();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchRankings(dynastyId, seasonId, weekNumber)
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((err) => {
        if (!cancelled) setError(err.message);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [dynastyId, seasonId, weekNumber]);

  return (
    <div className="max-w-3xl mx-auto px-4">
      <PageHeader
        title="Top 25"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading rankings...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{weekLabel(data.week)}</h3>
            {data.rankedWeeks.length > 1 && (
              <select
                value={data.week.number}
                onChange={(e) => navigate(`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${e.target.value}/rankings`)}
                className="rounded-md border border-white/20 bg-white/10 px-2 py-1 text-xs text-white focus:outline-none"
              >
                {data.rankedWeeks.map((week) => (
                  <option key={week.id} value={week.number} className="text-charcoal">
                    {weekLabel(week)}
                  </option>
                ))}
              </select>
            )}
          </div>
          {data.rankings.length > 0 ? (
            <div className="overflow-x-auto">
              <Top25TableBody rankings={data.rankings} fullOpponentNames />
            </div>
          ) : (
            <p className="px-4 py-3 text-sm text-textSecondary">No rankings entered for this week.</p>
          )}
        </Card>
      )}
    </div>
  );
}

export default Top25Page;
