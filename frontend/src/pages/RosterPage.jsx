import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import {
  fetchRoster,
  createInjury,
  updateInjury,
  deleteInjury,
  updateStudentSeasonName,
  commitRosterImport,
} from "../lib/apiClient";

const nameInputClass =
  "w-20 rounded border border-transparent bg-transparent px-1 py-0.5 text-textPrimary focus:border-burnt focus:bg-white focus:outline-none dark:text-white dark:focus:bg-darksurface";

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

function PlayerNameCell({ player }) {
  const [firstName, setFirstName] = useState(player.firstName || "");
  const [lastName, setLastName] = useState(player.lastName || "");
  const [error, setError] = useState(null);
  const saveTimer = useRef(null);

  const scheduleSave = (nextFirstName, nextLastName) => {
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      try {
        setError(null);
        await updateStudentSeasonName(player.id, { firstName: nextFirstName, lastName: nextLastName });
      } catch (err) {
        setError(err.message);
      }
    }, 600);
  };

  useEffect(() => () => saveTimer.current && clearTimeout(saveTimer.current), []);

  return (
    <div>
      <div className="flex gap-1">
        <input
          value={firstName}
          onChange={(e) => {
            setFirstName(e.target.value);
            scheduleSave(e.target.value, lastName);
          }}
          className={nameInputClass}
          aria-label="First name"
        />
        <input
          value={lastName}
          onChange={(e) => {
            setLastName(e.target.value);
            scheduleSave(firstName, e.target.value);
          }}
          className={`${nameInputClass} w-28`}
          aria-label="Last name"
        />
      </div>
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
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
                  <td className="px-1 py-1.5 text-textPrimary dark:text-white">
                    {authed ? <PlayerNameCell player={player} /> : player.name}
                  </td>
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

function ImportRosterForm({ dynastyId, seasonId, collegeSeasonId, onClose, onImported }) {
  const [text, setText] = useState("");
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState(null);
  const [warnings, setWarnings] = useState(null);

  const handleImport = async () => {
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch {
      setError("That's not valid JSON.");
      return;
    }
    if (!Array.isArray(parsed.players)) {
      setError('Expected an object with a "players" array.');
      return;
    }

    setImporting(true);
    setError(null);
    setWarnings(null);
    try {
      const result = await commitRosterImport(dynastyId, seasonId, collegeSeasonId, parsed.players);
      setWarnings(result.warnings || []);
      onImported();
    } catch (err) {
      setError(err.message);
    } finally {
      setImporting(false);
    }
  };

  return (
    <Card>
      <div className="p-5 space-y-3">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Import Roster</h3>
        <p className="text-sm text-textSecondary">
          Paste a JSON object with a &ldquo;players&rdquo; array. Returning players are matched to last season&rsquo;s
          roster automatically.
        </p>
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={10}
          placeholder='{"players": [...]}'
          className="w-full rounded-md border border-border bg-white px-3 py-2 font-mono text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
        />

        {error && <p className="text-sm text-danger">{error}</p>}
        {warnings && warnings.length > 0 && (
          <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
            <p className="font-semibold">{warnings.length} player{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
            <ul className="mt-1 list-disc pl-5">
              {warnings.map((warning, index) => (
                <li key={index}>
                  {warning.player}: {warning.error}
                </li>
              ))}
            </ul>
          </div>
        )}
        {warnings && warnings.length === 0 && <p className="text-sm font-semibold text-success">Imported successfully.</p>}

        <div className="flex gap-2">
          <button
            type="button"
            onClick={handleImport}
            disabled={importing || !text.trim()}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {importing ? "Importing..." : "Import Roster"}
          </button>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Close
          </button>
        </div>
      </div>
    </Card>
  );
}

function RosterPage() {
  const { dynastyId, seasonId, collegeSeasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [injuryModal, setInjuryModal] = useState(null);
  const [showImport, setShowImport] = useState(false);
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
          <>
            {authed && (
              <button
                type="button"
                onClick={() => setShowImport((prev) => !prev)}
                className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Import
              </button>
            )}
            <Link
              to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              &larr; Back to Dashboard
            </Link>
          </>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading roster...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {showImport && (
        <div className="mb-4">
          <ImportRosterForm
            dynastyId={dynastyId}
            seasonId={seasonId}
            collegeSeasonId={collegeSeasonId}
            onClose={() => setShowImport(false)}
            onImported={reload}
          />
        </div>
      )}

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
