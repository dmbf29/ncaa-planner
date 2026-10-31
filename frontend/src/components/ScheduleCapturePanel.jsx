import { useEffect, useState } from "react";
import Card from "./Card";
import { collectScheduleCapture, fetchScheduleCaptureStatus, startScheduleCapture, stopScheduleCapture } from "../lib/apiClient";

const POLL_MS = 1500;

const defaultApi = { start: startScheduleCapture, status: fetchScheduleCaptureStatus, stop: stopScheduleCapture, collect: collectScheduleCapture };

// Local-only: starts tools/capture/watch.py via the Rails server, which screenshots the PS Remote Play window each
// time you pause on a new screen (or every half second while the list scrolls) with a controller. Stopping reads the
// screens on this Mac (no AI) and hands the games to onResult for review. Rendered only in dev; the backend refuses
// otherwise.
function ScheduleCapturePanel({ dynastyId, seasonId, onResult, api = defaultApi, title = "Capture from Remote Play", instructions = "Click Capture, then scroll down the schedule in Remote Play, pausing on each screen. Click Stop when you reach the bottom and the games are read for you to review." }) {
  const [status, setStatus] = useState({ running: false, dir: null, screens: [] });
  const [busy, setBusy] = useState(false);
  const [reading, setReading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!dynastyId || !seasonId) return undefined;
    let cancelled = false;
    const load = () =>
      api.status(dynastyId, seasonId)
        .then((s) => !cancelled && setStatus(s))
        .catch(() => {});
    load();
    const timer = setInterval(() => status.running && load(), POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [api, dynastyId, seasonId, status.running]);

  const run = async (action) => {
    setBusy(true);
    setError(null);
    try {
      setStatus(await action(dynastyId, seasonId));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleStop = async () => {
    setBusy(true);
    setError(null);
    try {
      const stopped = await api.stop(dynastyId, seasonId);
      setStatus({ running: false, dir: stopped.dir, screens: stopped.screens });
      setReading(true);
      onResult(await api.collect(dynastyId, seasonId, stopped.token));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
      setReading(false);
    }
  };

  const folder = status.dir?.split("/").pop();

  return (
    <Card>
      <div className="p-5 space-y-3">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h3>
        <p className="text-sm text-textSecondary">{instructions}</p>
        {status.running ? (
          <button
            type="button"
            onClick={handleStop}
            disabled={busy}
            className="rounded-md bg-danger px-4 py-2 text-sm font-semibold text-white shadow-card disabled:opacity-60"
          >
            {busy ? "Stopping..." : `Stop and read (${status.screens.length} saved)`}
          </button>
        ) : (
          <button
            type="button"
            onClick={() => run(api.start)}
            disabled={busy}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
          >
            {reading ? "Reading the screens..." : busy ? "Starting..." : "Capture"}
          </button>
        )}
        {folder && (
          <p className="text-sm text-textSecondary">
            {status.running ? "Recording" : "Saved"} {status.screens.length} screen{status.screens.length === 1 ? "" : "s"} in pod/captures/{folder}
          </p>
        )}
        {error && <p className="text-sm text-danger">{error}</p>}
      </div>
    </Card>
  );
}

export default ScheduleCapturePanel;
