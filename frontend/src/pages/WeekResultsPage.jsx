import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import LeagueGameRow, { weekLabel } from "../components/LeagueGameRow";
import { fetchWeekGames } from "../lib/apiClient";

const MIN_WEEK = 0;
const MAX_WEEK = 19;

function WeekResultsPage() {
  const { dynastyId, seasonId, weekNumber } = useParams();
  const navigate = useNavigate();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    fetchWeekGames(dynastyId, seasonId, weekNumber)
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

  const goToWeek = (number) => navigate(`/dynasty/${dynastyId}/seasons/${seasonId}/weeks/${number}/games`);
  const currentNumber = Number(weekNumber);

  return (
    <div className="max-w-2xl mx-auto px-4">
      <PageHeader
        title="Weekly Results"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading results...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
            <button
              type="button"
              onClick={() => goToWeek(currentNumber - 1)}
              disabled={currentNumber <= MIN_WEEK}
              className="rounded-md px-2 py-1 text-xs text-white/80 hover:bg-white/10 disabled:opacity-30"
            >
              &larr; Prev
            </button>
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{weekLabel(data.week)}</h3>
            <button
              type="button"
              onClick={() => goToWeek(currentNumber + 1)}
              disabled={currentNumber >= MAX_WEEK}
              className="rounded-md px-2 py-1 text-xs text-white/80 hover:bg-white/10 disabled:opacity-30"
            >
              Next &rarr;
            </button>
          </div>
          {data.games.length > 0 ? (
            <div className="px-4 py-2">
              {data.games.map((game) => (
                <LeagueGameRow key={game.id} game={game} />
              ))}
            </div>
          ) : (
            <p className="px-4 py-3 text-sm text-textSecondary">No games scheduled for this week.</p>
          )}
        </Card>
      )}
    </div>
  );
}

export default WeekResultsPage;
