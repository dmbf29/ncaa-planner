import { useEffect, useRef, useState } from "react";
import Card from "./Card";
import { exportTeamBuilderCsv } from "../lib/apiClient";

const STAGE_LABELS = {
  uploading: "Uploading…",
  queued: "Waiting for another export to finish…",
  starting: "Starting…",
  scanning: "Scanning video…",
  reading: "Reading the roster table…",
  players: "Reading player details…",
};

// Each phase gets a slice of one progress bar: scanning is quick, the table OCR is the long part.
const STAGE_RANGE = { scanning: [0, 15], reading: [15, 80], players: [80, 99] };

const downloadCsv = (csv, filename) => {
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
};

function ExportTeamBuilderForm({ dynastyId, seasonId, collegeSeasonId, teamName, onClose }) {
  const [status, setStatus] = useState(null); // { name, stage, percent, done, total } while a video is processing
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [dragOver, setDragOver] = useState(false);
  const cancelledRef = useRef(false);

  useEffect(() => {
    cancelledRef.current = false;
    return () => {
      cancelledRef.current = true;
    };
  }, []);

  const handleFile = async (file) => {
    if (!file) return;
    if (!file.type.startsWith("video/") && !/\.(mov|mp4|m4v)$/i.test(file.name)) {
      setError("That doesn't look like a video file (.mov or .mp4).");
      return;
    }
    setError(null);
    setResult(null);
    setStatus({ name: file.name, stage: "uploading", percent: 0 });
    try {
      const analysis = await exportTeamBuilderCsv(dynastyId, seasonId, collegeSeasonId, file, {
        isCancelled: () => cancelledRef.current,
        onProgress: (progress) => {
          if (cancelledRef.current || !progress) return;
          const [from, to] = STAGE_RANGE[progress.stage] || [0, 0];
          const fraction = progress.total ? progress.done / progress.total : 0;
          setStatus({ name: file.name, stage: progress.stage, percent: Math.round(from + (to - from) * fraction) });
        },
      });
      if (cancelledRef.current) return;
      setStatus(null);
      setResult(analysis);
      downloadCsv(analysis.csv, analysis.filename);
    } catch (err) {
      if (cancelledRef.current) return;
      setStatus(null);
      setError(err.message);
    }
  };

  return (
    <Card>
      <div className="space-y-3 p-5">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
          Export {teamName} to Team Builder
        </h3>
        <p className="text-sm text-textSecondary">
          Record the roster table with every column scrolled into view: all the way right and back to the left, then
          down to the next page, until the last player. Drop the video here to get a CSV for the Team Builder
          Unleashed extension. This doesn&rsquo;t change your dynasty.
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
            if (!status) handleFile(e.dataTransfer.files?.[0]);
          }}
          className={`rounded-md border-2 border-dashed px-3 py-3 text-sm transition ${
            dragOver ? "border-burnt bg-burnt/10" : "border-border dark:border-darkborder"
          }`}
        >
          {status ? (
            <div className="space-y-1.5">
              <p className="font-semibold text-textPrimary dark:text-white">{status.name}</p>
              <p className="text-textSecondary">{STAGE_LABELS[status.stage] || "Working…"} (a few minutes)</p>
              <div className="h-1.5 overflow-hidden rounded-full bg-border dark:bg-darkborder">
                <div className="h-full bg-burnt transition-all" style={{ width: `${status.percent ?? 0}%` }} />
              </div>
            </div>
          ) : (
            <p className="text-textSecondary">
              Drop a roster screen recording here, or{" "}
              <label className="cursor-pointer font-semibold text-burnt hover:underline">
                choose a video
                <input
                  type="file"
                  accept="video/*,.mov"
                  className="hidden"
                  onChange={(e) => {
                    handleFile(e.target.files?.[0]);
                    e.target.value = "";
                  }}
                />
              </label>
              .
            </p>
          )}
        </div>
        {error && <p className="text-sm text-danger">{error}</p>}
        {result && (
          <div className="space-y-2">
            <p className="text-sm font-semibold text-success">
              Downloaded {result.filename} ({result.playerCount} players).
            </p>
            {result.flagged.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">
                  {result.flagged.length} player{result.flagged.length === 1 ? "" : "s"} had a shaky read — the CSV
                  uses the most common reading, but double-check:
                </p>
                <ul className="mt-1 list-disc pl-5">
                  {result.flagged.map((flag, index) => (
                    <li key={index}>{flag}</li>
                  ))}
                </ul>
              </div>
            )}
            <button
              type="button"
              onClick={() => downloadCsv(result.csv, result.filename)}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Download again
            </button>
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
    </Card>
  );
}

export default ExportTeamBuilderForm;
