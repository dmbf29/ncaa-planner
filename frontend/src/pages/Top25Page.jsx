import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { weekLabel } from "../components/LeagueGameRow";
import { fetchRankings } from "../lib/apiClient";

function RankingRow({ entry }) {
  const record = entry.record ? `${entry.record.wins ?? 0}-${entry.record.losses ?? 0}` : null;
  const lastResult = entry.lastResult;

  return (
    <div
      className={clsx(
        "flex items-center gap-3 border-b border-border/60 py-2 text-sm last:border-0 dark:border-darkborder/60",
        entry.coachedByUs && "font-semibold text-burnt",
      )}
    >
      <span className="w-6 shrink-0 text-textSecondary">{entry.rank}</span>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-textPrimary dark:text-white">{entry.college.name}</span>
          {record && <span className="shrink-0 font-normal text-textSecondary">({record})</span>}
          {entry.coachedByUs && <i className="fa-solid fa-gamepad shrink-0 text-[10px] text-burnt/80" title="User-coached" />}
        </div>
        {lastResult && (
          <p className="mt-0.5 truncate text-xs font-normal text-textSecondary">
            <span className={lastResult.won ? "text-success" : "text-danger"}>{lastResult.won ? "W" : "L"}</span>{" "}
            {lastResult.teamScore}-{lastResult.opponentScore} vs {lastResult.opponent.name}
          </p>
        )}
      </div>
      <span className="shrink-0 text-xs text-textSecondary">{entry.college.conference}</span>
    </div>
  );
}

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
    <div className="max-w-2xl mx-auto px-4">
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
            <div className="px-4 py-2">
              {data.rankings.map((entry) => (
                <RankingRow key={entry.rank} entry={entry} />
              ))}
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
