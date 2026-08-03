import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import TeamDashboardCard from "../components/TeamDashboardCard";
import { fetchDynasties, fetchSeason } from "../lib/apiClient";

function DynastyDashboardPage() {
  const [season, setSeason] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const navigate = useNavigate();

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setError("This dynasty doesn't have a season yet.");
          return;
        }
        const data = await fetchSeason(dynasty.id, latestSeason.id);
        setSeason(data);
      } catch (err) {
        setError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate]);

  return (
    <div className="max-w-7xl mx-auto px-4">
      <PageHeader
        title={season ? `${season.dynasty.name} - ${season.year} Season` : "Dynasty"}
        actions={
          <Link
            to="/dynasty/export"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Export
          </Link>
        }
      />
      {loading && <p className="text-sm text-textSecondary">Loading dynasty...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}
      {!loading && !error && season && season.teams.length === 0 && (
        <p className="text-sm text-textSecondary">No coached teams yet for this season.</p>
      )}
      {season && season.teams.length > 0 && (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {season.teams.map((team) => (
            <TeamDashboardCard key={team.id} team={team} />
          ))}
        </div>
      )}
    </div>
  );
}

export default DynastyDashboardPage;
