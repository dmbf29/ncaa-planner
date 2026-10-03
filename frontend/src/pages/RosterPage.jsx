import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { keysToSnake } from "../lib/case";
import OverallBadge from "../components/OverallBadge";
import {
  fetchRoster,
  createInjury,
  updateInjury,
  deleteInjury,
  updateStudentSeason,
  analyzeRosterImport,
  analyzeRosterVideo,
  commitRosterImport,
  searchPreviousStudents,
} from "../lib/apiClient";

const nameInputClass =
  "w-20 rounded border border-transparent bg-transparent px-1 py-0.5 text-textPrimary focus:border-burnt focus:bg-white focus:outline-none dark:text-white dark:focus:bg-darksurface";

const STATUS_BADGE_CLASSES = {
  match: "bg-success/10 text-success",
  new: "bg-textSecondary/10 text-textSecondary",
  ambiguous: "bg-warning/10 text-warning",
};

// Review table order: the rows needing the most attention first.
const STATUS_SORT_ORDER = { ambiguous: 0, new: 1, match: 2 };

const STATUS_LABELS = {
  match: "Match",
  new: "New Player",
  ambiguous: "Needs Review",
};

// Rating columns shown after OVR, matching the All Players search page.
const STAT_COLUMNS = [
  { field: "speed", label: "Spd" },
  { field: "acceleration", label: "Acc" },
  { field: "agility", label: "Agi" },
  { field: "changeOfDirection", label: "CoD" },
  { field: "strength", label: "Str" },
  { field: "awareness", label: "Awr" },
];

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
        await updateStudentSeason(player.id, { firstName: nextFirstName, lastName: nextLastName });
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

function PlayerOverallCell({ player }) {
  const [overall, setOverall] = useState(player.overall ?? "");
  const [error, setError] = useState(null);
  const saveTimer = useRef(null);

  const scheduleSave = (nextOverall) => {
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(async () => {
      try {
        setError(null);
        await updateStudentSeason(player.id, { overall: nextOverall === "" ? null : Number(nextOverall) });
      } catch (err) {
        setError(err.message);
      }
    }, 600);
  };

  useEffect(() => () => saveTimer.current && clearTimeout(saveTimer.current), []);

  return (
    <div className="inline-block">
      <input
        type="number"
        min={0}
        max={99}
        value={overall}
        onChange={(e) => {
          setOverall(e.target.value);
          scheduleSave(e.target.value);
        }}
        className={`${nameInputClass} w-12 text-center`}
        aria-label="Overall"
      />
      {error && <p className="text-xs text-danger">{error}</p>}
    </div>
  );
}

function PositionGroupTable({ group, authed, onReportInjury }) {
  if (group.players.length === 0) return null;

  return (
    <Card className="-mx-4 overflow-hidden rounded-none border-x-0 sm:mx-0 sm:rounded-xl sm:border-x">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{group.positionGroup}</h3>
        <span className="text-xs text-white/70">
          Avg {group.averageOverall ?? "—"} &middot; High {group.highOverall ?? "—"} &middot; Low{" "}
          {group.lowOverall ?? "—"} &middot; Avg Spd {group.averageSpeed ?? "—"}
        </span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-xs md:text-sm">
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="px-3 py-2 text-left font-semibold">Player</th>
              <th className="px-3 py-2 text-center font-semibold">OVR</th>
              {STAT_COLUMNS.map((col) => (
                <th key={col.field} className="px-3 py-2 text-right font-semibold">
                  {col.label}
                </th>
              ))}
              <th className="px-3 py-2 text-left font-semibold">Dev</th>
              {authed && <th className="px-3 py-2 text-center font-semibold">Injury</th>}
            </tr>
          </thead>
          <tbody>
            {group.players.map((player) => {
              const currentInjury = latestInjury(player.injuries);
              return (
                <tr key={player.id} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                  <td className="px-3 py-2">
                    {authed ? (
                      <PlayerNameCell player={player} />
                    ) : (
                      <div className="font-semibold text-textPrimary dark:text-white">{player.name}</div>
                    )}
                    <div className="text-xs font-normal text-textSecondary">
                      {player.position} &middot; {player.classYear}
                    </div>
                  </td>
                  <td className="px-3 py-2 text-center">
                    {authed ? <PlayerOverallCell player={player} /> : <OverallBadge value={player.overall} />}
                  </td>
                  {STAT_COLUMNS.map((col) => (
                    <td key={col.field} className="px-3 py-2 text-right tabular-nums text-textSecondary">
                      {player[col.field] ?? "—"}
                    </td>
                  ))}
                  <td className="px-3 py-2 text-textSecondary">{player.devTrait ?? "—"}</td>
                  {authed && (
                    <td className="px-3 py-2 text-center">
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

function CandidatePicker({ row, onChange }) {
  return (
    <select
      value={row.studentId ?? ""}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className="w-full max-w-[300px] rounded-md border border-warning/50 bg-white px-2 py-1 text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-warning/40 dark:bg-darksurface dark:text-white"
    >
      <option value="">— Create New Player —</option>
      {row.candidates.map((candidate) => (
        <option key={candidate.studentId} value={candidate.studentId}>
          {candidate.name} — {candidate.college} ({candidate.position}, {candidate.classYear}, {candidate.overall ?? "—"} OVR)
        </option>
      ))}
    </select>
  );
}

function NewPlayerNameEditor({ row, onEditName }) {
  return (
    <div className="flex gap-1">
      <input
        value={row.firstName}
        onChange={(e) => onEditName({ firstName: e.target.value, lastName: row.lastName })}
        placeholder="First"
        className="w-20 rounded border border-border bg-white px-1.5 py-1 text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
      />
      <input
        value={row.lastName}
        onChange={(e) => onEditName({ firstName: row.firstName, lastName: e.target.value })}
        placeholder="Last"
        className="w-28 rounded border border-border bg-white px-1.5 py-1 text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
      />
    </div>
  );
}

function PreviousSeasonSearchBox({ dynastyId, seasonId, collegeSeasonId, onPick }) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const timer = useRef(null);

  const handleChange = (value) => {
    setQuery(value);
    if (timer.current) clearTimeout(timer.current);
    if (value.trim().length < 2) {
      setResults([]);
      return;
    }
    timer.current = setTimeout(async () => {
      setSearching(true);
      try {
        const result = await searchPreviousStudents(dynastyId, seasonId, collegeSeasonId, value.trim());
        setResults(result.students || []);
      } catch {
        setResults([]);
      } finally {
        setSearching(false);
      }
    }, 300);
  };

  useEffect(() => () => timer.current && clearTimeout(timer.current), []);

  return (
    <div className="mt-1">
      <input
        value={query}
        onChange={(e) => handleChange(e.target.value)}
        placeholder="Search last season's players..."
        className="w-full max-w-[260px] rounded border border-border bg-white px-2 py-1 text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
      />
      {searching && <p className="mt-1 text-xs text-textSecondary">Searching...</p>}
      {results.length > 0 && (
        <ul className="mt-1 max-h-32 max-w-[260px] overflow-y-auto rounded border border-border bg-white dark:border-darkborder dark:bg-darksurface">
          {results.map((candidate) => (
            <li key={candidate.studentId}>
              <button
                type="button"
                onClick={() => onPick(candidate)}
                className="block w-full px-2 py-1 text-left text-xs hover:bg-border/30 dark:hover:bg-white/10"
              >
                {candidate.name} — {candidate.college} ({candidate.position}, {candidate.classYear}, {candidate.overall ?? "—"} OVR)
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function ImportReviewRow({ row, dynastyId, seasonId, collegeSeasonId, onChange, onEditName, onManualMatch }) {
  const isManuallyMatched = row.status === "new" && row.manualMatch;

  return (
    <tr className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
      <td className="px-2 py-1.5 text-textPrimary dark:text-white">
        {row.status === "new" && !isManuallyMatched ? (
          <NewPlayerNameEditor row={row} onEditName={onEditName} />
        ) : (
          `${row.firstName} ${row.lastName}`
        )}
      </td>
      <td className="px-2 py-1.5 text-textSecondary">
        {row.position} &middot; {row.classYear}
      </td>
      <td className="px-2 py-1.5">
        <span
          className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
            STATUS_BADGE_CLASSES[isManuallyMatched ? "match" : row.status]
          }`}
        >
          {STATUS_LABELS[isManuallyMatched ? "match" : row.status]}
        </span>
      </td>
      <td className="px-2 py-1.5">
        {row.status === "match" && (
          <span className="text-textSecondary">
            {row.matchedName}
            {row.matchedCollege && <span className="text-textSecondary/70"> — {row.matchedCollege}</span>}
          </span>
        )}
        {row.status === "new" &&
          (isManuallyMatched ? (
            <span className="text-textSecondary">
              {row.manualMatch.name}
              <span className="text-textSecondary/70"> — {row.manualMatch.college}</span>
              <button type="button" onClick={() => onManualMatch(null)} className="ml-2 text-xs text-burnt hover:underline">
                Undo
              </button>
            </span>
          ) : (
            <div>
              <span className="text-textSecondary">
                {row.suggestedFirstName
                  ? "New Student — name from signed recruit, verify above"
                  : "New Student — fix the name above if needed"}
              </span>
              <PreviousSeasonSearchBox
                dynastyId={dynastyId}
                seasonId={seasonId}
                collegeSeasonId={collegeSeasonId}
                onPick={onManualMatch}
              />
            </div>
          ))}
        {row.status === "ambiguous" && <CandidatePicker row={row} onChange={onChange} />}
      </td>
    </tr>
  );
}

function ImportRosterForm({ dynastyId, seasonId, collegeSeasonId, onClose, onImported }) {
  const [text, setText] = useState("");
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [rows, setRows] = useState(null);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [warnings, setWarnings] = useState(null);

  const [videoStatus, setVideoStatus] = useState(null); // { name, stage, percent, players } while a video is processing
  const [dragOver, setDragOver] = useState(false);
  const [videoFlags, setVideoFlags] = useState([]); // players the video reader wasn't sure about
  const cancelledRef = useRef(false);
  useEffect(() => {
    cancelledRef.current = false;
    return () => {
      cancelledRef.current = true;
    };
  }, []);

  const handleAnalyze = async (jsonText = text) => {
    let parsed;
    try {
      parsed = JSON.parse(jsonText);
    } catch {
      setAnalyzeError("That's not valid JSON.");
      return;
    }
    if (!Array.isArray(parsed.players)) {
      setAnalyzeError('Expected an object with a "players" array.');
      return;
    }

    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeRosterImport(dynastyId, seasonId, collegeSeasonId, parsed.players);
      setRows(
        result.players.map((row) => ({
          ...row,
          studentId: row.status === "ambiguous" ? row.suggestedStudentId : (row.studentId ?? null),
          firstName: row.status === "new" && row.suggestedFirstName ? row.suggestedFirstName : row.firstName,
          lastName: row.status === "new" && row.suggestedLastName ? row.suggestedLastName : row.lastName,
        })),
      );
    } catch (err) {
      setAnalyzeError(err.message);
    } finally {
      setAnalyzing(false);
    }
  };

  // Dropping a roster-screen recording fills the box with the extracted JSON
  // and goes straight on to the normal analyze/review step.
  const handleVideoFile = async (file) => {
    if (!file) return;
    if (!file.type.startsWith("video/") && !/\.(mov|mp4|m4v)$/i.test(file.name)) {
      setAnalyzeError("That doesn't look like a video file (.mov or .mp4).");
      return;
    }
    setAnalyzeError(null);
    setVideoFlags([]);
    setVideoStatus({ name: file.name, stage: "uploading" });
    try {
      const result = await analyzeRosterVideo(dynastyId, seasonId, file, {
        isCancelled: () => cancelledRef.current,
        onProgress: (progress) => {
          if (cancelledRef.current || !progress) return;
          // One bar across both phases: the quick scan is the first ~30%, reading the players the rest.
          const fraction = progress.total ? progress.done / progress.total : 0;
          const percent = Math.min(99, Math.round(progress.stage === "scanning" ? fraction * 30 : 30 + fraction * 70));
          setVideoStatus({ name: file.name, stage: progress.stage, percent, done: progress.done, total: progress.total });
        },
      });
      if (cancelledRef.current) return;
      setVideoFlags(
        result.players
          .filter((player) => player.needsReview)
          .map((player) => `${player.firstName} ${player.lastName}: ${player.needsReview.join("; ")}`),
      );
      const json = JSON.stringify({ players: result.players.map((player) => keysToSnake(Object.fromEntries(Object.entries(player).filter(([key]) => key !== "needsReview")))) }, null, 1);
      setText(json);
      setVideoStatus(null);
      await handleAnalyze(json);
    } catch (err) {
      if (cancelledRef.current) return;
      setVideoStatus(null);
      setAnalyzeError(err.message);
    }
  };

  const updateRow = (index, studentId) => {
    setRows((prev) => prev.map((row, i) => (i === index ? { ...row, studentId } : row)));
  };

  const editRowName = (index, { firstName, lastName }) => {
    setRows((prev) => prev.map((row, i) => (i === index ? { ...row, firstName, lastName } : row)));
  };

  const setManualMatch = (index, candidate) => {
    setRows((prev) =>
      prev.map((row, i) => (i === index ? { ...row, manualMatch: candidate, studentId: candidate?.studentId ?? null } : row)),
    );
  };

  const handleCommit = async () => {
    setCommitting(true);
    setCommitError(null);
    try {
      const result = await commitRosterImport(dynastyId, seasonId, collegeSeasonId, rows);
      setWarnings(result.warnings || []);
      setSaved(true);
      onImported();
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  const counts = rows
    ? rows.reduce(
        (acc, row) => {
          acc[row.status] += 1;
          return acc;
        },
        { match: 0, new: 0, ambiguous: 0 },
      )
    : null;

  const sortedRows = rows
    ? rows
        .map((row, index) => ({ row, index }))
        .sort((a, b) => STATUS_SORT_ORDER[a.row.status] - STATUS_SORT_ORDER[b.row.status] || a.index - b.index)
    : [];

  return (
    <Card>
      <div className="p-5 space-y-3">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Import Roster</h3>

        {saved ? (
          <div className="space-y-2">
            <p className="text-sm font-semibold text-success">Saved! Roster has been updated.</p>
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
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Close
            </button>
          </div>
        ) : !rows ? (
          <>
            <p className="text-sm text-textSecondary">
              Paste a JSON object with a &ldquo;players&rdquo; array. Returning players are matched to their existing
              record automatically — anything ambiguous gets flagged for you to confirm before saving.
            </p>
            <div
              onDragOver={(e) => {
                e.preventDefault();
                setDragOver(true);
              }}
              onDragLeave={() => setDragOver(false)}
              onDrop={(e) => {
                e.preventDefault();
                setDragOver(false);
                if (!videoStatus && !analyzing) handleVideoFile(e.dataTransfer.files?.[0]);
              }}
              className={`rounded-md border-2 border-dashed px-3 py-3 text-sm transition ${
                dragOver ? "border-burnt bg-burnt/10" : "border-border dark:border-darkborder"
              }`}
            >
              {videoStatus ? (
                <div className="space-y-1.5">
                  <p className="font-semibold text-textPrimary dark:text-white">{videoStatus.name}</p>
                  <p className="text-textSecondary">
                    {videoStatus.stage === "uploading" && "Uploading…"}
                    {videoStatus.stage === "queued" && "Waiting for another video to finish…"}
                    {videoStatus.stage === "starting" && "Starting…"}
                    {videoStatus.stage === "scanning" && "Scanning video…"}
                    {videoStatus.stage === "reading" && `Reading players… ${videoStatus.done} of ${videoStatus.total}`}
                  </p>
                  <div className="h-1.5 overflow-hidden rounded-full bg-border dark:bg-darkborder">
                    <div
                      className="h-full bg-burnt transition-all"
                      style={{ width: `${videoStatus.percent ?? 0}%` }}
                    />
                  </div>
                </div>
              ) : (
                <p className="text-textSecondary">
                  Drop a roster screen recording here to read it automatically, or{" "}
                  <label className="cursor-pointer font-semibold text-burnt hover:underline">
                    choose a video
                    <input
                      type="file"
                      accept="video/*,.mov"
                      className="hidden"
                      onChange={(e) => {
                        handleVideoFile(e.target.files?.[0]);
                        e.target.value = "";
                      }}
                    />
                  </label>
                  . Or paste JSON below.
                </p>
              )}
            </div>
            <textarea
              value={text}
              onChange={(e) => setText(e.target.value)}
              rows={10}
              placeholder='{"players": [...]}'
              className="w-full rounded-md border border-border bg-white px-3 py-2 font-mono text-xs text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
            />
            {analyzeError && <p className="text-sm text-danger">{analyzeError}</p>}
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => handleAnalyze()}
                disabled={analyzing || !!videoStatus || !text.trim()}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {analyzing ? "Analyzing..." : "Analyze"}
              </button>
              <button
                type="button"
                onClick={onClose}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Close
              </button>
            </div>
          </>
        ) : (
          <>
            {videoFlags.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">
                  The video reader wasn&rsquo;t sure about {videoFlags.length} player{videoFlags.length === 1 ? "" : "s"} — double-check:
                </p>
                <ul className="mt-1 list-disc pl-5">
                  {videoFlags.map((flag, index) => (
                    <li key={index}>{flag}</li>
                  ))}
                </ul>
              </div>
            )}
            <p className="text-sm text-textSecondary">
              <span className={rows.length < 85 ? "font-semibold text-danger" : "font-semibold"}>
                {rows.length} total{rows.length < 85 && " (under 85)"}
              </span>{" "}
              &middot; {counts.match} matched &middot; {counts.new} new &middot; {counts.ambiguous} need review
            </p>
            <div className="max-h-[420px] overflow-y-auto overflow-x-auto rounded-md border border-border dark:border-darkborder">
              <table className="w-full min-w-[560px] text-left text-sm">
                <thead className="sticky top-0 bg-surface dark:bg-darksurface">
                  <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="px-2 py-2 font-semibold">Player</th>
                    <th className="px-2 py-2 font-semibold">Pos / Yr</th>
                    <th className="px-2 py-2 font-semibold">Status</th>
                    <th className="px-2 py-2 font-semibold">Match</th>
                  </tr>
                </thead>
                <tbody>
                  {sortedRows.map(({ row, index }) => (
                    <ImportReviewRow
                      key={index}
                      row={row}
                      dynastyId={dynastyId}
                      seasonId={seasonId}
                      collegeSeasonId={collegeSeasonId}
                      onChange={(studentId) => updateRow(index, studentId)}
                      onEditName={(names) => editRowName(index, names)}
                      onManualMatch={(candidate) => setManualMatch(index, candidate)}
                    />
                  ))}
                </tbody>
              </table>
            </div>

            {commitError && <p className="text-sm text-danger">{commitError}</p>}

            <div className="flex gap-2">
              <button
                type="button"
                onClick={handleCommit}
                disabled={committing}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {committing ? "Saving..." : "Confirm Import"}
              </button>
              <button
                type="button"
                onClick={() => setRows(null)}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Back
              </button>
              <button
                type="button"
                onClick={onClose}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Cancel
              </button>
            </div>
          </>
        )}
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
    <div className="mx-auto max-w-4xl">
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
              to={`/dynasty/${dynastyId}/seasons/${seasonId}/players`}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              All Players
            </Link>
            <Link
              to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              &larr; Dashboard
            </Link>
            <Link
              to={`/dynasty/${dynastyId}/seasons/${seasonId}/standings`}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              &larr; Standings
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
