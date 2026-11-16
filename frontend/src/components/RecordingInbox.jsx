import { useEffect, useState } from "react";
import { attachScoringSummary, dismissRecording, fetchRecordingInbox } from "../lib/apiClient";

// Local-only: stream recordings the scouter has read that aren't attached to a game yet. Attaching one gives the game its
// scoring summary right away (before the box score) and starts the highlights + full-game upload in the background, so
// videos go up the day a game is played. Renders nothing when there's nothing waiting.
function RecordingInbox({ dynastyId }) {
  const [recordings, setRecordings] = useState([]);
  const [choice, setChoice] = useState({});
  const [busy, setBusy] = useState(null);
  const [message, setMessage] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    let cancelled = false;
    fetchRecordingInbox(dynastyId)
      .then((data) => {
        if (cancelled) return;
        setRecordings(data.recordings);
        setChoice(Object.fromEntries(data.recordings.map((r) => [r.id, r.suggestion?.gameId ?? ""])));
      })
      .catch(() => !cancelled && setRecordings([]));
    return () => {
      cancelled = true;
    };
  }, [dynastyId]);

  const remove = (id) => setRecordings((list) => list.filter((r) => r.id !== id));

  const run = async (id, action, done) => {
    setBusy(id);
    setError(null);
    try {
      await action();
      remove(id);
      setMessage(done);
    } catch (e) {
      setError(e.response?.data?.error || "Something went wrong.");
    } finally {
      setBusy(null);
    }
  };

  if (recordings.length === 0 && !message) return null;

  return (
    <div className="mb-4 rounded-lg border border-border bg-white p-4 shadow-card dark:border-darkborder dark:bg-white/5">
      <h2 className="text-sm font-semibold text-charcoal dark:text-white">New stream recordings</h2>
      {message && <p className="mt-1 text-xs text-success">{message}</p>}
      {error && <p className="mt-1 text-xs text-danger">{error}</p>}
      <ul className="mt-2 space-y-3">
        {recordings.map((recording) => (
          <li key={recording.id} className="flex flex-col gap-2 text-sm md:flex-row md:items-center md:justify-between">
            <div className="text-charcoal dark:text-white">
              <span className="font-semibold">{recording.channel}</span>{" "}
              <span className="text-textSecondary">
                · {(recording.teams || []).join(" vs ")} · {recording.plays} scores · {new Date(recording.startedAt).toLocaleString()}
              </span>
            </div>
            <div className="flex items-center gap-2">
              <select
                value={choice[recording.id] ?? ""}
                onChange={(e) => setChoice((c) => ({ ...c, [recording.id]: e.target.value }))}
                className="max-w-[18rem] rounded-md border border-border bg-transparent px-2 py-1.5 text-xs dark:border-darkborder"
              >
                <option value="">{recording.suggestion ? "Pick another game…" : "Pick the game…"}</option>
                {recording.openGames.map((game) => (
                  <option key={game.gameId} value={game.gameId}>
                    {game.label}
                    {game.gameId === recording.suggestion?.gameId ? " (suggested)" : ""}
                  </option>
                ))}
              </select>
              <button
                type="button"
                disabled={busy === recording.id || !choice[recording.id]}
                onClick={() =>
                  run(
                    recording.id,
                    () => attachScoringSummary(choice[recording.id], recording.id),
                    "Attached. The highlights and the full game are being uploaded in the background (backend/log/youtube_publish.log).",
                  )
                }
                className="shrink-0 rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                Attach &amp; upload
              </button>
              <button
                type="button"
                disabled={busy === recording.id}
                onClick={() => run(recording.id, () => dismissRecording(dynastyId, recording.id), "Dismissed.")}
                className="shrink-0 rounded-md border border-border px-3 py-1.5 text-xs text-charcoal transition hover:bg-border/30 disabled:opacity-60 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Dismiss
              </button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default RecordingInbox;
