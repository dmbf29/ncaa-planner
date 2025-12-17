import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatPill from "../components/StatPill";
import { fetchTeams } from "../lib/apiClient";

function TeamsPage() {
  const [teams, setTeams] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const navigate = useNavigate();

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const data = await fetchTeams();
        setTeams(data);
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
    <div>
      <PageHeader
        title="Teams"
        eyebrow="Dashboard"
        actions={
          <Link
            to="/teams/new"
            className="rounded-md bg-burnt px-3 py-2 text-charcoal text-sm font-semibold shadow-card transition hover:-translate-y-0.5"
          >
            New Team
          </Link>
        }
      />
      {loading && <p className="text-sm text-textSecondary">Loading teams...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}
      <div className="grid gap-4 md:grid-cols-2">
        {teams.map((team) => (
          <Card key={team.id}>
            <div className="p-5">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="font-varsity text-xl uppercase tracking-[0.07em]">{team.name}</h3>
                </div>
                <StatPill label="Squads" value={team.squads?.length || 0} />
              </div>
              <div className="mt-4 flex gap-3">
                <Link
                  to={`/teams/${team.id}/setup`}
                  className="rounded-md bg-burnt px-3 py-2 text-charcoal text-sm font-semibold shadow-card transition hover:-translate-y-0.5"
                >
                  Setup
                </Link>
                <Link
                  to={`/teams/${team.id}/graduates`}
                  className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Graduates / Departures
                </Link>
                {team.squads?.[0] && (
                  <Link
                    to={`/teams/${team.id}/squads/${team.squads[0].id}`}
                    className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                  >
                    Open first squad
                  </Link>
                )}
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

export default TeamsPage;
