import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchRoster } from "../lib/apiClient";

function PositionGroupTable({ group }) {
  if (group.players.length === 0) return null;

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{group.positionGroup}</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="px-4 py-2 font-semibold">Name</th>
              <th className="px-2 py-2 font-semibold">Pos</th>
              <th className="px-2 py-2 font-semibold">Yr</th>
              <th className="px-2 py-2 font-semibold text-right">OVR</th>
              <th className="px-2 py-2 font-semibold text-right">Spd</th>
              <th className="px-4 py-2 font-semibold">Dev</th>
            </tr>
          </thead>
          <tbody>
            {group.players.map((player) => (
              <tr key={player.id} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                <td className="px-4 py-1.5 text-textPrimary dark:text-white">{player.name}</td>
                <td className="px-2 py-1.5 text-textSecondary">{player.position}</td>
                <td className="px-2 py-1.5 text-textSecondary">{player.classYear}</td>
                <td className="px-2 py-1.5 text-right font-semibold">{player.overall ?? "—"}</td>
                <td className="px-2 py-1.5 text-right text-textSecondary">{player.speed ?? "—"}</td>
                <td className="px-4 py-1.5 text-textSecondary">{player.devTrait ?? "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function RosterPage() {
  const { dynastyId, seasonId, collegeSeasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchRoster(dynastyId, seasonId, collegeSeasonId)
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
  }, [dynastyId, seasonId, collegeSeasonId]);

  return (
    <div className="max-w-4xl mx-auto px-4">
      <PageHeader
        eyebrow={data ? `${data.collegeSeason.season.year} Season` : undefined}
        title={data ? `${data.collegeSeason.college.name} Roster` : "Roster"}
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading roster...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="space-y-4">
          {data.positionGroups.map((group) => (
            <PositionGroupTable key={group.positionGroup} group={group} />
          ))}
        </div>
      )}
    </div>
  );
}

export default RosterPage;
