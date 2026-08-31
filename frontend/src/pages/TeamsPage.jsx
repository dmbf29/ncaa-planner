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
    <div className="max-w-6xl mx-auto px-4">
      <PageHeader
        title="Teams"
        eyebrow="Dashboard"
        actions={
          <Link
            to="/teams/new"
            className="rounded-md bg-burnt px-3 py-2 text-white text-sm shadow-card transition hover:-translate-y-0.5"
          >
            New Team
          </Link>
        }
      />
      {loading && <p className="text-sm text-textSecondary">Loading teams...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}
      {teams.length === 0 && !loading && !error ? (
        <p className="text-sm text-textSecondary">Setup your first team to get started!</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {teams.map((team) => (
            <Card key={team.id}>
              <div className="p-5">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="font-varsity text-xl uppercase tracking-[0.07em] flex items-center">
                      {team.name}
                      <Link
                        to={`/teams/${team.id}/setup`}
                        className="px-2 text-xs text-charcoal transition dark:text-white dark:hover:bg-white/10"
                      >
                        <i className="fa-solid fa-gear"></i>
                      </Link>
                    </h3>
                  </div>
                  <StatPill label="Players" value={team.players?.length || 0} />
                </div>
                <div className="mt-4 flex gap-3">
                  {team.squads?.[0] && (
                    <Link
                      to={`/teams/${team.id}/squads/${team.squads[0].id}`}
                      className="rounded-md bg-burnt  border border-border px-3 py-2 text-sm text-charcoal transition border-burnt hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                    >
                      Offense
                    </Link>
                  )}
                  {team.squads?.[1] && (
                    <Link
                      to={`/teams/${team.id}/squads/${team.squads[1].id}`}
                      className="rounded-md bg-burnt  border border-border px-3 py-2 text-sm text-charcoal transition border-burnt hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                    >
                      Defense
                    </Link>
                  )}
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

export default TeamsPage;
