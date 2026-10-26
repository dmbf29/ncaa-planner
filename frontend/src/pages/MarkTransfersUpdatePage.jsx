import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, analyzeTransferVideo, commitTransfers } from "../lib/apiClient";

const buttonClass =
  "rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 disabled:opacity-50 dark:border-darkborder dark:text-white dark:hover:bg-white/10";

const stageText = (status) =>
  ({
    uploading: "Uploading…",
    queued: "Waiting for another video to finish…",
    starting: "Starting…",
    scanning: "Scanning video…",
    reading: `Reading players… ${status.done} of ${status.total}`,
  })[status.stage];

const prettyRating = (key) =>
  key
    .replace(/([A-Z])/g, " $1")
    .replace(/^./, (c) => c.toUpperCase())
    .replace("Run Block Finesse", "RB Finesse")
    .replace("Run Block Power", "RB Power")
    .replace("Pass Block Power", "PB Power");

// "74" when unchanged, "74 → 78" when the screen shows a different value than what's on file.
function ValueChange({ current, incoming }) {
  if (incoming == null) return <span className="text-textSecondary">{current ?? "—"}</span>;
  if (incoming === current) return <span>{current}</span>;
  return (
    <span className="font-semibold text-burnt">
      {current ?? "—"} → {incoming}
    </span>
  );
}

const feetInches = (inches) => (inches == null ? null : `${Math.floor(inches / 12)}'${inches % 12}"`);

// Archetype, height and weight under the player's name; a changed value shows old → new.
function BioLine({ row }) {
  const { current = {}, incoming = {} } = row;
  const parts = [
    ["archetype", (v) => v],
    ["heightInches", feetInches],
    ["weightLbs", (v) => (v == null ? null : `${v} lbs`)],
  ].map(([field, format]) => {
    if (incoming[field] == null) return null;
    const next = format(incoming[field]);
    return current[field] == null || current[field] === incoming[field] ? next : `${format(current[field])} → ${next}`;
  });
  const shown = parts.filter(Boolean);
  return shown.length > 0 ? <p className="text-xs text-textSecondary">{shown.join(" · ")}</p> : null;
}

// The six tiles the game shows for this player's position (Throw Power for a QB, Run Block for a lineman, ...).
function RatingsCell({ row }) {
  const keys = Object.keys(row.incomingRatings || {});
  if (keys.length === 0) return <span className="text-textSecondary">—</span>;
  return (
    <div className="flex flex-wrap justify-end gap-x-3 gap-y-0.5 text-xs">
      {keys.map((key) => (
        <span key={key} className="whitespace-nowrap text-textSecondary">
          {prettyRating(key)} <ValueChange current={row.currentRatings?.[key]} incoming={row.incomingRatings[key]} />
        </span>
      ))}
    </div>
  );
}

function MarkTransfersUpdatePage() {
  const navigate = useNavigate();
  const [dynastyId, setDynastyId] = useState(null);
  const [season, setSeason] = useState(null);
  const [error, setError] = useState(null);
  const [videoStatus, setVideoStatus] = useState(null);
  const [dragOver, setDragOver] = useState(false);
  const [rows, setRows] = useState([]); // matched + unmatched rows from every video read so far
  const [excluded, setExcluded] = useState(() => new Set());
  const [clearFirst, setClearFirst] = useState(false);
  const [saving, setSaving] = useState(false);
  const [result, setResult] = useState(null);
  const cancelledRef = useRef(false);

  useEffect(() => {
    const load = async () => {
      try {
        const dynasty = (await fetchDynasties())[0];
        const latest = [...(dynasty?.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latest) {
          setError("This dynasty doesn't have a season yet.");
          return;
        }
        setDynastyId(dynasty.id);
        setSeason(latest);
      } catch (err) {
        setError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) navigate("/auth/login");
      }
    };
    load();
    return () => {
      cancelledRef.current = true;
    };
  }, [navigate]);

  const handleVideoFile = async (file) => {
    if (!file || !season) return;
    cancelledRef.current = false;
    setError(null);
    setResult(null);
    setVideoStatus({ name: file.name, stage: "uploading" });
    try {
      const analysis = await analyzeTransferVideo(dynastyId, season.id, file, {
        isCancelled: () => cancelledRef.current,
        onProgress: (progress) => {
          if (cancelledRef.current || !progress) return;
          const fraction = progress.total ? progress.done / progress.total : 0;
          const percent = Math.min(99, Math.round(progress.stage === "scanning" ? fraction * 30 : 30 + fraction * 70));
          setVideoStatus({ name: file.name, ...progress, percent });
        },
      });
      if (cancelledRef.current) return;
      // A later video replaces an earlier reading of the same player.
      setRows((prev) => {
        const incomingKeys = new Set(analysis.rows.filter((r) => r.studentSeasonId).map((r) => r.studentSeasonId));
        return [...prev.filter((r) => !r.studentSeasonId || !incomingKeys.has(r.studentSeasonId)), ...analysis.rows];
      });
      setVideoStatus(null);
    } catch (err) {
      if (cancelledRef.current) return;
      setVideoStatus(null);
      setError(err.message);
    }
  };

  const matched = useMemo(
    () =>
      rows
        .filter((r) => r.status === "matched")
        .sort((a, b) => a.collegeName.localeCompare(b.collegeName) || (b.incoming?.overall ?? 0) - (a.incoming?.overall ?? 0)),
    [rows],
  );
  const unresolved = rows.filter((r) => r.status !== "matched");
  const selected = matched.filter((r) => !excluded.has(r.studentSeasonId));

  const toggle = (id) =>
    setExcluded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const handleCommit = async () => {
    setSaving(true);
    setError(null);
    try {
      const payload = selected.map((r) => ({
        studentSeasonId: r.studentSeasonId,
        name: r.matchedName,
        ...r.incoming,
        ratings: r.incomingRatings,
      }));
      const response = await commitTransfers(dynastyId, season.id, payload, clearFirst);
      setResult({ saved: payload.length - response.warnings.length, warnings: response.warnings });
      setRows([]);
      setExcluded(new Set());
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="max-w-5xl mx-auto px-4 space-y-4">
      <PageHeader
        title="Mark Transfers"
        eyebrow="Dynasty Updates"
        actions={
          <Link to="/dynasty/updates" className={buttonClass}>
            Back to Updates
          </Link>
        }
      />

      {error && <p className="text-sm text-danger">{error}</p>}

      <p className="text-sm text-textSecondary">
        {season ? `${season.year} season. ` : ""}Record the &ldquo;players leaving&rdquo; screen for each team with the highlight stepping
        through the rows. Everyone whose reason is Transfer is flagged &ldquo;In Portal&rdquo; and has their overall and visible ratings
        refreshed. Pro Draft, Graduation and Staying rows are ignored, and no new players are created. The video is read on this
        computer — no AI. You can add several videos before saving.
      </p>

      <Card className="p-4">
        <div
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={(e) => {
            e.preventDefault();
            setDragOver(false);
            if (!videoStatus) handleVideoFile(e.dataTransfer.files?.[0]);
          }}
          className={`rounded-md border-2 border-dashed px-3 py-4 text-sm transition ${
            dragOver ? "border-burnt bg-burnt/10" : "border-border dark:border-darkborder"
          }`}
        >
          {videoStatus ? (
            <div className="space-y-1.5">
              <p className="font-semibold text-textPrimary dark:text-white">{videoStatus.name}</p>
              <p className="text-textSecondary">{stageText(videoStatus)}</p>
              <div className="h-1.5 overflow-hidden rounded-full bg-border dark:bg-darkborder">
                <div className="h-full bg-burnt transition-all" style={{ width: `${videoStatus.percent ?? 0}%` }} />
              </div>
            </div>
          ) : (
            <p className="text-textSecondary">
              Drop a screen recording here, or{" "}
              <label className="cursor-pointer font-semibold text-burnt hover:underline">
                choose a video
                <input
                  type="file"
                  accept="video/*,.mov"
                  className="hidden"
                  disabled={!season}
                  onChange={(e) => {
                    handleVideoFile(e.target.files?.[0]);
                    e.target.value = "";
                  }}
                />
              </label>
              .
            </p>
          )}
        </div>
      </Card>

      {result && (
        <Card className="space-y-2 p-4 text-sm">
          <p className="font-semibold text-success">
            Marked {result.saved} player{result.saved === 1 ? "" : "s"} as in the portal.
          </p>
          {result.warnings.map((w) => (
            <p key={w.player} className="text-danger">
              {w.player}: {w.error}
            </p>
          ))}
          <Link
            to={`/dynasty/${dynastyId}/seasons/${season.id}/players`}
            className="inline-block font-semibold text-burnt hover:underline"
          >
            View players in the portal &rarr;
          </Link>
        </Card>
      )}

      {matched.length > 0 && (
        <Card className="overflow-hidden">
          <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3 text-sm dark:border-darkborder">
            <p className="text-textSecondary">
              {selected.length} of {matched.length} matched players will be marked.
            </p>
            <div className="flex items-center gap-4">
              <label className="flex items-center gap-1.5 text-textSecondary">
                <input type="checkbox" checked={clearFirst} onChange={(e) => setClearFirst(e.target.checked)} />
                Un-flag everyone else first
              </label>
              <button
                type="button"
                onClick={handleCommit}
                disabled={saving || (selected.length === 0 && !clearFirst)}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
              >
                {saving ? "Saving…" : "Mark in portal"}
              </button>
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                  <th className="w-8 px-3 py-2" />
                  <th className="px-3 py-2 text-left">Player</th>
                  <th className="px-3 py-2 text-left">Reason</th>
                  <th className="px-2 py-2 text-right">OVR</th>
                  <th className="px-2 py-2 text-right">Position ratings</th>
                </tr>
              </thead>
              <tbody>
                {matched.map((row) => (
                  <tr key={row.studentSeasonId} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                    <td className="px-3 py-2">
                      <input
                        type="checkbox"
                        checked={!excluded.has(row.studentSeasonId)}
                        onChange={() => toggle(row.studentSeasonId)}
                      />
                    </td>
                    <td className="px-3 py-2">
                      <p className="font-semibold">
                        {row.matchedName}
                        {row.alreadyInPortal && <span className="ml-1.5 text-xs font-normal text-textSecondary">already in portal</span>}
                        {row.needsReview.length > 0 && <span className="ml-1.5 text-xs font-normal text-warning">check</span>}
                      </p>
                      <BioLine row={row} />
                      <p className="text-xs text-textSecondary">
                        {row.collegeName} &middot; {row.position} &middot; {row.classYear}
                        {row.partial && " · read from the table only, ratings unchanged"}
                      </p>
                    </td>
                    <td className="px-3 py-2 text-xs text-textSecondary">{row.transferReason}</td>
                    <td className="px-2 py-2 text-right tabular-nums">
                      <ValueChange current={row.current?.overall} incoming={row.incoming?.overall} />
                    </td>
                    <td className="px-2 py-2 tabular-nums">
                      <RatingsCell row={row} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {unresolved.length > 0 && (
        <Card className="space-y-2 p-4 text-sm">
          <p className="font-semibold text-warning">
            {unresolved.length} row{unresolved.length === 1 ? "" : "s"} couldn&rsquo;t be tied to one player and won&rsquo;t be saved
          </p>
          <ul className="space-y-0.5 text-textSecondary">
            {unresolved.map((row, i) => (
              <li key={`${row.team}-${row.name}-${i}`}>
                {row.name} ({row.position || "?"}, {row.team}) &mdash;{" "}
                {{ unmatched: "not on that team's roster", ambiguous: "more than one possible match", unmatchedTeam: "team not recognised" }[row.status]}
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}

export default MarkTransfersUpdatePage;
