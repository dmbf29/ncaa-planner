import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import TeamDashboardCard from "../components/TeamDashboardCard";
import Top25Snapshot from "../components/Top25Snapshot";
import HeismanWatch from "../components/HeismanWatch";
import AroundTheLeague from "../components/AroundTheLeague";
import StandingsSnapshot from "../components/StandingsSnapshot";
import AllAmericansSnapshot from "../components/AllAmericansSnapshot";
import { fetchDynastyPortal, fetchDynastyDashboard, fetchStandings, fetchAllAmericans } from "../lib/apiClient";

function TeamTabs({ teams, activeTeamId, onSelect }) {
  if (teams.length < 2) return null;

  return (
    <div className="mb-4 flex gap-1.5 overflow-x-auto lg:hidden">
      {teams.map((team) => (
        <button
          key={team.id}
          type="button"
          onClick={() => onSelect(team.id)}
          className={clsx(
            "shrink-0 rounded-md px-3 py-1.5 text-sm font-semibold transition",
            team.id === activeTeamId
              ? "bg-charcoal text-white dark:bg-white/10"
              : "border border-border text-textSecondary hover:bg-border/30 dark:border-darkborder dark:hover:bg-white/10",
          )}
        >
          {team.college.name}
        </button>
      ))}
    </div>
  );
}

function SeasonSwitcher({ seasons, activeSeasonId, dynastyId }) {
  if (!seasons || seasons.length < 2) return null;

  return (
    <div className="mb-6 flex flex-wrap gap-1.5">
      {seasons.map((season) => (
        <Link
          key={season.id}
          to={`/dynasty/${dynastyId}/seasons/${season.id}`}
          className={clsx(
            "rounded-md px-3 py-1.5 text-sm font-semibold transition",
            String(season.id) === String(activeSeasonId)
              ? "bg-charcoal text-white dark:bg-white/10"
              : "border border-border text-textSecondary hover:bg-border/30 dark:border-darkborder dark:hover:bg-white/10",
          )}
        >
          {season.year}
        </Link>
      ))}
    </div>
  );
}

function DynastyShowPage() {
  const { dynastyId, seasonId } = useParams();
  const navigate = useNavigate();
  const [portal, setPortal] = useState(null);
  const [dashboard, setDashboard] = useState(null);
  const [standings, setStandings] = useState(null);
  const [allAmericans, setAllAmericans] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeTeamId, setActiveTeamId] = useState(null);
  const authed = Boolean(localStorage.getItem("jwt"));

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      setLoading(true);
      setError(null);
      try {
        const portalData = await fetchDynastyPortal(dynastyId);
        if (cancelled) return;
        setPortal(portalData);

        if (!seasonId) {
          const latestSeason = [...(portalData.seasons || [])].sort((a, b) => b.year - a.year)[0];
          if (!latestSeason) {
            setError("This dynasty doesn't have a season yet.");
            return;
          }
          navigate(`/dynasty/${dynastyId}/seasons/${latestSeason.id}`, { replace: true });
          return;
        }

        const [dashboardData, standingsData, allAmericansData] = await Promise.all([
          fetchDynastyDashboard(dynastyId, seasonId),
          fetchStandings(dynastyId, seasonId),
          fetchAllAmericans(dynastyId, seasonId),
        ]);
        if (cancelled) return;
        setDashboard(dashboardData);
        setStandings(standingsData);
        setAllAmericans(allAmericansData);
        setActiveTeamId(dashboardData.teams[0]?.id ?? null);
      } catch (err) {
        if (!cancelled) setError(err.message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    return () => {
      cancelled = true;
    };
  }, [dynastyId, seasonId, navigate]);

  const coachedConferences = dashboard ? [...new Set(dashboard.teams.map((team) => team.college.conference))] : [];

  return (
    <div className="max-w-7xl mx-auto px-4">
      <PageHeader
        title={dashboard ? `${dashboard.dynasty.name} - ${dashboard.year} Season` : portal?.name || "Dynasty"}
        actions={
          authed ? (
            <>
              <Link
                to="/dynasty/updates"
                className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Dynasty Updates
              </Link>
              <Link
                to="/dynasty/export"
                className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Export
              </Link>
            </>
          ) : null
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading dynasty...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {!loading && !error && portal && (
        <SeasonSwitcher seasons={portal.seasons} activeSeasonId={seasonId} dynastyId={dynastyId} />
      )}

      {!loading && !error && dashboard && dashboard.teams.length === 0 && (
        <p className="text-sm text-textSecondary">No coached teams yet for this season.</p>
      )}

      {dashboard && dashboard.teams.length > 0 && (
        <>
          <TeamTabs teams={dashboard.teams} activeTeamId={activeTeamId} onSelect={setActiveTeamId} />

          <div className="grid gap-4 lg:grid-cols-2 xl:grid-cols-4">
            {dashboard.teams.map((team) => (
              <div key={team.id} className={clsx(team.id !== activeTeamId && "hidden lg:block")}>
                <TeamDashboardCard team={team} dynastyId={dynastyId} seasonId={seasonId} />
              </div>
            ))}
          </div>

          <div className="mt-6 grid gap-4 md:grid-cols-2">
            <StandingsSnapshot
              standings={standings}
              coachedConferences={coachedConferences}
              dynastyId={dynastyId}
              seasonId={seasonId}
            />
            <Top25Snapshot top25={dashboard.top25} dynastyId={dynastyId} seasonId={seasonId} />
          </div>

          <div className="mt-6">
            <AroundTheLeague
              weeks={dashboard.aroundTheLeague}
              currentWeekNumber={dashboard.currentWeekNumber}
              dynastyId={dynastyId}
              seasonId={seasonId}
            />
          </div>

          <div className="mt-6 grid gap-4 md:grid-cols-2">
            <HeismanWatch heismanWatch={dashboard.heismanWatch} />
            <AllAmericansSnapshot
              allAmericans={allAmericans}
              coachedConferences={coachedConferences}
              dynastyId={dynastyId}
              seasonId={seasonId}
            />
          </div>
        </>
      )}
    </div>
  );
}

export default DynastyShowPage;
