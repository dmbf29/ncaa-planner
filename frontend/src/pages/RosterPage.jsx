import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchRoster, createInjury, updateInjury, deleteInjury } from "../lib/apiClient";

function ClassBreakdownChart({ classBreakdown }) {
  if (!classBreakdown) return null;

  const { total, buckets } = classBreakdown;
  const max = Math.max(1, ...buckets.map((b) => b.count));

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center justify-between gap-2 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Class Breakdown</h3>
        <span className="text-xs text-white/70">{total} Total</span>
      </div>
      <div className="flex items-end gap-4 px-4 py-4">
        {buckets.map((bucket) => (
          <div key={bucket.bucket} className="flex flex-1 flex-col items-center gap-1">
            <span className="text-xs font-semibold text-textPrimary dark:text-white">{bucket.count}</span>
            <div className="flex h-28 w-full items-end">
              <div
                className="w-full rounded-t-sm bg-burnt/70"
                style={{ height: `${Math.max(4, (bucket.count / max) * 100)}%` }}
              />
            </div>
            <span className="text-[11px] uppercase tracking-wide text-textSecondary">{bucket.bucket}</span>
          </div>
        ))}
      </div>
    </Card>
  );
}

function latestInjury(injuries) {
  if (!injuries || injuries.length === 0) return null;
  return [...injuries].sort((a, b) => b.id - a.id)[0];
}

function injuryTooltip(injury) {
  const status = injury.outForSeason ? "Out for the season" : `Expected back Week ${injury.returnWeekNumber}`;
  return `${injury.description} — ${status}`;
}

function PositionGroupTable({ group, authed, onReportInjury }) {
  if (group.players.length === 0) return null;

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{group.positionGroup}</h3>
      </div>
      <div className="flex flex-wrap gap-x-4 gap-y-1 border-b border-border bg-charcoal/5 px-4 py-2 text-xs text-textSecondary dark:border-darkborder dark:bg-white/5">
        <span>
          Avg <strong className="font-semibold text-textPrimary dark:text-white">{group.averageOverall ?? "—"}</strong>
        </span>
        <span>
          High <strong className="font-semibold text-textPrimary dark:text-white">{group.highOverall ?? "—"}</strong>
        </span>
        <span>
          Low <strong className="font-semibold text-textPrimary dark:text-white">{group.lowOverall ?? "—"}</strong>
        </span>
        <span>
          Avg Spd <strong className="font-semibold text-textPrimary dark:text-white">{group.averageSpeed ?? "—"}</strong>
        </span>
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
              {authed && <th className="px-2 py-2 font-semibold text-center">Injury</th>}
            </tr>
          </thead>
          <tbody>
            {group.players.map((player) => {
              const currentInjury = latestInjury(player.injuries);
              return (
                <tr key={player.id} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                  <td className="px-4 py-1.5 text-textPrimary dark:text-white">{player.name}</td>
                  <td className="px-2 py-1.5 text-textSecondary">{player.position}</td>
                  <td className="px-2 py-1.5 text-textSecondary">{player.classYear}</td>
                  <td className="px-2 py-1.5 text-right font-semibold">{player.overall ?? "—"}</td>
                  <td className="px-2 py-1.5 text-right text-textSecondary">{player.speed ?? "—"}</td>
                  <td className="px-4 py-1.5 text-textSecondary">{player.devTrait ?? "—"}</td>
                  {authed && (
                    <td className="px-2 py-1.5 text-center">
                      <button
                        type="button"
                        onClick={() => onReportInjury(player, currentInjury)}
                        title={currentInjury ? injuryTooltip(currentInjury) : "Report Injury"}
                        className={
                          currentInjury
                            ? "text-danger transition hover:text-danger/70"
                            : "text-textSecondary/40 transition hover:text-textSecondary"
                        }
                      >
                        <i className="fa-solid fa-user-injured"></i>
                      </button>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function InjuryModal({ player, injury, games, onClose, onSaved }) {
  const [gameId, setGameId] = useState(injury ? String(injury.gameId) : games[0] ? String(games[0].id) : "");
  const [description, setDescription] = useState(injury?.description || "");
  const [weeksOut, setWeeksOut] = useState(injury ? String(injury.weeksOut) : "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  if (!player) return null;

  const handleSave = async () => {
    if (!gameId || !description.trim() || !weeksOut) {
      setError("Game, injury, and weeks out are all required.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const payload = { gameId: Number(gameId), description: description.trim(), weeksOut: Number(weeksOut) };
      if (injury) {
        await updateInjury(player.id, injury.id, payload);
      } else {
        await createInjury(player.id, payload);
      }
      onSaved();
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  const handleDelete = async () => {
    if (!injury || !window.confirm(`Remove this injury for ${player.name}?`)) return;
    setBusy(true);
    setError(null);
    try {
      await deleteInjury(player.id, injury.id);
      onSaved();
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-md rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <h3 className="font-varsity text-xl uppercase tracking-[0.06em]">
            {injury ? "Edit Injury" : "Report Injury"} — {player.name}
          </h3>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>

        <div className="mt-4 space-y-3">
          <label className="block space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Game</span>
            <select
              value={gameId}
              onChange={(e) => setGameId(e.target.value)}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            >
              {games.length === 0 && <option value="">No games played yet</option>}
              {games.map((game) => (
                <option key={game.id} value={game.id}>
                  Week {game.weekNumber} {game.home ? "vs" : "@"} {game.opponent}
                </option>
              ))}
            </select>
          </label>

          <label className="block space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Injury</span>
            <input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Dislocated Hip"
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
          </label>

          <label className="block space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Weeks Out</span>
            <input
              type="number"
              min={1}
              value={weeksOut}
              onChange={(e) => setWeeksOut(e.target.value)}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
          </label>

          {error && <p className="text-sm text-danger">{error}</p>}
        </div>

        <div className="mt-4 flex items-end justify-end">
          <div className="flex gap-1">
            {injury && (
              <button
                onClick={handleDelete}
                disabled={busy}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-danger/10 disabled:opacity-60"
              >
                <i className="fa-solid fa-trash-can"></i>
              </button>
            )}
            <button
              onClick={onClose}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={busy}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function RosterPage() {
  const { dynastyId, seasonId, collegeSeasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [injuryModal, setInjuryModal] = useState(null);
  const authed = Boolean(localStorage.getItem("jwt"));

  const reload = useCallback(() => {
    setLoading(true);
    setError(null);
    return fetchRoster(dynastyId, seasonId, collegeSeasonId)
      .then((result) => setData(result))
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [dynastyId, seasonId, collegeSeasonId]);

  useEffect(() => {
    reload();
  }, [reload]);

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
          <ClassBreakdownChart classBreakdown={data.classBreakdown} />
          {data.positionGroups.map((group) => (
            <PositionGroupTable
              key={group.positionGroup}
              group={group}
              authed={authed}
              onReportInjury={(player, injury) => setInjuryModal({ player, injury })}
            />
          ))}
        </div>
      )}

      {injuryModal && (
        <InjuryModal
          player={injuryModal.player}
          injury={injuryModal.injury}
          games={data?.games || []}
          onClose={() => setInjuryModal(null)}
          onSaved={() => {
            setInjuryModal(null);
            reload();
          }}
        />
      )}
    </div>
  );
}

export default RosterPage;
