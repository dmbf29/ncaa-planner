import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StandingsTable from "../components/StandingsTable";
import { fetchStandings } from "../lib/apiClient";

function ConferenceStandingsPage() {
  const { dynastyId, seasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchStandings(dynastyId, seasonId)
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
  }, [dynastyId, seasonId]);

  return (
    <div className="max-w-5xl mx-auto px-4">
      <PageHeader
        eyebrow={data ? `${data.season.year} Season` : undefined}
        title="Conference Standings"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading standings...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="grid gap-4 md:grid-cols-2">
          {data.conferences.map((conference) => (
            <StandingsTable key={conference.conference} conference={conference} dynastyId={dynastyId} seasonId={seasonId} />
          ))}
        </div>
      )}
    </div>
  );
}

export default ConferenceStandingsPage;
