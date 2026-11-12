import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import useLatestSeason from "../lib/useLatestSeason";
import {
  fetchScheduling,
  analyzeSchedulingTeam,
  commitSchedulingTeam,
  startWeekVideo,
  fetchWeekVideoStatus,
  commitSchedulingWeek,
} from "../lib/apiClient";

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

function progressLabel(progress) {
  if (!progress) return "Reading recording...";
  if (progress.stage === "queued") return "Waiting for a free slot...";
  if (progress.stage === "reading") return `Reading cards ${progress.done} of ${progress.total}...`;
  return "Starting...";
}

// Records one open week's possible opponents: upload a screen recording of the in-game opponent picker, review the
// teams read (ranks and ratings come along), save.
function WeekRecorder({ dynastyId, seasonId, team, slot, onSaved, onClose }) {
  const [video, setVideo] = useState(null);
  const [progress, setProgress] = useState(null);
  const [reading, setReading] = useState(false);
  const [analysis, setAnalysis] = useState(null);
  const [cards, setCards] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const read = async () => {
    setReading(true);
    setError(null);
    setProgress(null);
    try {
      const { token } = await startWeekVideo(dynastyId, seasonId, video);
      for (;;) {
        await new Promise((resolve) => setTimeout(resolve, 1500));
        const status = await fetchWeekVideoStatus(dynastyId, seasonId, token);
        if (status.status === "completed") {
          setAnalysis(status.analysis);
          setCards(status.analysis.cards);
          break;
        }
        setProgress(status.progress);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setReading(false);
    }
  };

  const save = async () => {
    setSaving(true);
    setError(null);
    try {
      await commitSchedulingWeek(dynastyId, seasonId, team.id, slot.weekId, cards);
      await onSaved();
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  const updateCard = (index, patch) => setCards(cards.map((card, i) => (i === index ? { ...card, ...patch } : card)));

  return (
    <Card>
      <div className="space-y-4 p-5">
        <div className="flex items-center justify-between">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Week {slot.weekNumber} Possible Opponents</h3>
          <button type="button" onClick={onClose} className="text-sm text-textSecondary hover:underline">
            Close
          </button>
        </div>
        {!cards ? (
          <>
            <p className="text-sm text-textSecondary">
              Record the opponent picker for week {slot.weekNumber}, scrolling through every team one at a time (pause on each card), then upload the
              recording. Ratings and prestige for each team are updated from the cards.
            </p>
            <input type="file" accept="video/*" onChange={(e) => setVideo(e.target.files?.[0] || null)} className="text-sm" />
            {error && <p className="text-sm text-danger">{error}</p>}
            <button
              type="button"
              onClick={read}
              disabled={!video || reading}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card disabled:opacity-60"
            >
              {reading ? progressLabel(progress) : "Read Recording"}
            </button>
          </>
        ) : (
          <>
            <p className="text-sm text-textSecondary">
              {cards.length} teams read{analysis.unmatched > 0 && `, ${analysis.unmatched} need a match`}. Remove any that aren&rsquo;t options for this week.
            </p>
            <div className="max-h-96 overflow-y-auto">
              <table className="w-full border-collapse text-left text-sm">
                <thead>
                  <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="p-2">Team</th>
                    <th className="p-2">Rank</th>
                    <th className="p-2">OVR/OFF/DEF</th>
                    <th className="p-2">Stars</th>
                    <th className="p-2" />
                  </tr>
                </thead>
                <tbody>
                  {cards.map((card, index) => (
                    <tr key={`${card.rawName}-${index}`} className="border-b border-border dark:border-darkborder">
                      <td className="p-2">
                        <select
                          value={card.collegeId ?? ""}
                          onChange={(e) => updateCard(index, { collegeId: e.target.value ? Number(e.target.value) : null })}
                          className={inputClass}
                        >
                          <option value="">— unmatched: {card.rawName} —</option>
                          {analysis.colleges.map((college) => (
                            <option key={college.id} value={college.id}>
                              {college.name}
                            </option>
                          ))}
                        </select>
                      </td>
                      <td className="p-2 text-textPrimary dark:text-white">{card.rank ? `#${card.rank}` : card.rankUnread ? "Ranked" : "—"}</td>
                      <td className="p-2 text-textPrimary dark:text-white">
                        {card.overall ?? "?"}/{card.offense ?? "?"}/{card.defense ?? "?"}
                      </td>
                      <td className="p-2 text-textPrimary dark:text-white">{card.prestige ?? "?"}</td>
                      <td className="p-2">
                        <button type="button" onClick={() => setCards(cards.filter((_, i) => i !== index))} className="text-xs text-danger hover:underline">
                          Remove
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {error && <p className="text-sm text-danger">{error}</p>}
            <button
              type="button"
              onClick={save}
              disabled={saving}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card disabled:opacity-60"
            >
              {saving ? "Saving..." : `Save ${cards.filter((c) => c.collegeId).length} Opponents`}
            </button>
          </>
        )}
      </div>
    </Card>
  );
}

function SlotGrid({ team, onRecord }) {
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
                <button type="button" onClick={() => onRecord(slot)} className="text-left text-burnt hover:underline">
                  Open &middot; {slot.optionCount} option{slot.optionCount === 1 ? "" : "s"}
                  {slot.rankedCount > 0 && ` (${slot.rankedCount} ranked)`}
                </button>
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
  const [recordingSlot, setRecordingSlot] = useState(null);
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

      {team.uploaded && !rows && <SlotGrid team={team} onRecord={setRecordingSlot} />}

      {recordingSlot && !rows && (
        <WeekRecorder
          key={recordingSlot.weekId}
          dynastyId={dynastyId}
          seasonId={seasonId}
          team={team}
          slot={recordingSlot}
          onSaved={async () => {
            await load();
            setRecordingSlot(null);
          }}
          onClose={() => setRecordingSlot(null)}
        />
      )}

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
