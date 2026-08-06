import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import AllAmericanTierList from "../components/AllAmericanTierList";
import { fetchAllAmericans } from "../lib/apiClient";

function AllAmericansPage() {
  const { dynastyId, seasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchAllAmericans(dynastyId, seasonId)
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
    <div className="max-w-4xl mx-auto px-4">
      <PageHeader
        eyebrow={data ? `${data.season.year} Season` : undefined}
        title="All-Americans"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading All-Americans...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="grid gap-4 md:grid-cols-2">
          <Card className="overflow-hidden">
            <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
              <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">National</h3>
            </div>
            <AllAmericanTierList tiers={data.national} />
          </Card>

          {data.conferences.map((conference) => (
            <Card key={conference.conference} className="overflow-hidden">
              <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
                <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{conference.conference}</h3>
              </div>
              <AllAmericanTierList tiers={conference.tiers} />
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

export default AllAmericansPage;
