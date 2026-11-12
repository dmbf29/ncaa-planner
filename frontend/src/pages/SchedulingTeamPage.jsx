import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import useLatestSeason from "../lib/useLatestSeason";
import { fetchScheduling, analyzeSchedulingTeam, commitSchedulingTeam } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const STATE_LABELS = { locked: "Locked", bye: "Bye", option: "Open (suggested)", open: "Open" };

function ReviewRow({ row, colleges, onChange }) {
  const fixed = row.state === "bye" || row.state === "open";
  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 text-sm font-semibold text-textPrimary dark:text-white">{row.weekNumber}</td>
      <td className="p-2">
        <select value={row.state} onChange={(e) => onChange({ ...row, state: e.target.value })} className={inputClass}>
          {Object.entries(STATE_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </td>
      <td className="p-2">
        {fixed ? (
          <span className="text-sm text-textSecondary">&mdash;</span>
        ) : (
          <>
            <select
              value={row.opponentCollegeId ?? ""}
              onChange={(e) => onChange({ ...row, opponentCollegeId: e.target.value ? Number(e.target.value) : null })}
              className={inputClass}
            >
              <option value="">— none —</option>
              {colleges.map((college) => (
                <option key={college.id} value={college.id}>
                  {college.name}
                </option>
              ))}
            </select>
            {row.opponentRawName && !row.opponentCollegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.opponentRawName}&rdquo;</p>}
          </>
        )}
      </td>
      <td className="p-2">
        {!fixed && (
          <label className="flex items-center gap-1 text-xs text-textSecondary">
            <input type="checkbox" checked={Boolean(row.isAway)} onChange={(e) => onChange({ ...row, isAway: e.target.checked })} />
            Away
          </label>
        )}
      </td>
    </tr>
  );
}

function SlotGrid({ team }) {
  return (
    <Card>
      <div className="space-y-3 p-5">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Schedule</h3>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {team.slots.map((slot) => (
            <div key={slot.weekId} className="rounded-md border border-border p-2 text-sm dark:border-darkborder">
              <p className="text-xs uppercase tracking-wide text-textSecondary">Week {slot.weekNumber}</p>
              {slot.state === "bye" && <p className="text-textSecondary">Bye</p>}
              {slot.state === "locked" && (
                <p className="font-semibold text-textPrimary dark:text-white">
                  {slot.isAway ? "@" : "vs"} {slot.opponent.name}
                </p>
              )}
              {slot.state === "open" && (
                <p className="text-burnt">
                  Open &middot; {slot.optionCount} option{slot.optionCount === 1 ? "" : "s"}
                  {slot.rankedCount > 0 && ` (${slot.rankedCount} ranked)`}
                </p>
              )}
            </div>
          ))}
        </div>
      </div>
    </Card>
  );
}

function SchedulingTeamPage() {
  const { collegeSeasonId } = useParams();
  const { dynastyId, seasonId, error: seasonError } = useLatestSeason();
  const [team, setTeam] = useState(null);
  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analysis, setAnalysis] = useState(null);
  const [rows, setRows] = useState(null);
  const [saving, setSaving] = useState(false);
  const [warnings, setWarnings] = useState([]);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    try {
      const overview = await fetchScheduling(dynastyId, seasonId);
      setTeam(overview.teams.find((t) => String(t.id) === collegeSeasonId) || null);
    } catch (err) {
      setError(err.message);
    }
  }, [dynastyId, seasonId, collegeSeasonId]);

  useEffect(() => {
    if (dynastyId) load();
  }, [dynastyId, load]);

  const analyze = async () => {
    setAnalyzing(true);
    setError(null);
    try {
      const result = await analyzeSchedulingTeam(dynastyId, seasonId, files);
      setAnalysis(result);
      setRows(result.rows);
    } catch (err) {
      setError(err.message);
    } finally {
      setAnalyzing(false);
    }
  };

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      const result = await commitSchedulingTeam(dynastyId, seasonId, team.college.id, rows);
      setWarnings(result.warnings || []);
      setAnalysis(null);
      setRows(null);
      setFiles([]);
      await load();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  if (seasonError) return <p className="mx-auto max-w-4xl px-4 text-sm text-danger">{seasonError}</p>;
  if (!team) return <p className="mx-auto max-w-4xl px-4 text-sm text-textSecondary">{error || "Loading..."}</p>;

  const teamMismatch = analysis && analysis.collegeId !== team.college.id;

  return (
    <div className="mx-auto max-w-4xl space-y-6 px-4">
      <PageHeader
        title={team.college.name}
        eyebrow="Schedule Setup"
        actions={
          <Link
            to="/dynasty/updates/scheduling"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            All teams
          </Link>
        }
      />

      {team.uploaded && !rows && <SlotGrid team={team} />}

      {warnings.length > 0 && (
        <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
          <p className="font-semibold">Some weeks couldn&rsquo;t be saved:</p>
          <ul className="mt-1 list-disc pl-5">
            {warnings.map((w, i) => (
              <li key={i}>
                Week {w.weekLabel}: {w.error}
              </li>
            ))}
          </ul>
        </div>
      )}

      {!rows ? (
        <Card>
          <div className="space-y-4 p-5">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
              {team.uploaded ? "Re-upload Schedule" : "Upload Schedule Screenshots"}
            </h3>
            <p className="text-sm text-textSecondary">
              Upload both screenshots of {team.college.name}&rsquo;s schedule (weeks 0&ndash;13). They&rsquo;re read on this Mac &mdash; no AI calls.
            </p>
            <FileDropZone title="Schedule Screenshots" hint="Two screenshots cover every week." files={files} onFilesChange={setFiles} />
            {error && <p className="text-sm text-danger">{error}</p>}
            <button
              type="button"
              onClick={analyze}
              disabled={analyzing || files.length === 0}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {analyzing ? "Reading..." : "Read Schedule"}
            </button>
          </div>
        </Card>
      ) : (
        <Card>
          <div className="space-y-4 p-5">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review</h3>
            {teamMismatch && (
              <p className="rounded-md border border-danger/40 bg-danger/10 p-3 text-sm text-danger">
                These screenshots look like {analysis.collegeRawName}, not {team.college.name}. Check before saving.
              </p>
            )}
            {analysis.warnings.length > 0 && (
              <ul className="list-disc rounded-md border border-warning/40 bg-warning/10 p-3 pl-8 text-sm text-textPrimary dark:text-white">
                {analysis.warnings.map((w, i) => (
                  <li key={i}>{w}</li>
                ))}
              </ul>
            )}
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] border-collapse text-left">
                <thead>
                  <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="p-2">Week</th>
                    <th className="p-2">Type</th>
                    <th className="p-2">Opponent</th>
                    <th className="p-2">Away?</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, index) => (
                    <ReviewRow key={row.weekNumber} row={row} colleges={analysis.colleges} onChange={(next) => setRows(rows.map((r, i) => (i === index ? next : r)))} />
                  ))}
                </tbody>
              </table>
            </div>
            {error && <p className="text-sm text-danger">{error}</p>}
            <div className="flex gap-3">
              <button
                type="button"
                onClick={save}
                disabled={saving}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
              >
                {saving ? "Saving..." : "Save Schedule"}
              </button>
              <button type="button" onClick={() => { setRows(null); setAnalysis(null); }} className="rounded-md border border-border px-4 py-2 text-sm dark:border-darkborder dark:text-white">
                Cancel
              </button>
            </div>
          </div>
        </Card>
      )}
    </div>
  );
}

export default SchedulingTeamPage;
