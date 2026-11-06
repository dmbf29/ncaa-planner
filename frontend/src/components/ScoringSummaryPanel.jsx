import { useEffect, useState } from "react";
import { attachScoringSummary, detachScoringSummary, fetchScoringRecordings } from "../lib/apiClient";

const quarterLabel = (quarter) => (quarter <= 4 ? `Quarter ${quarter}` : `Overtime ${quarter - 4}`);

const playLine = (play) =>
  `${play.clock || "?"} ${play.team} ${play.kind.toLowerCase()}${play.extra ? ` (${play.extra})` : ""}${play.approx ? " [approximate]" : ""}`;

function SummaryBody({ summary }) {
  const quarters = [...new Set(summary.plays.map((play) => play.quarter))].sort((a, b) => a - b);
  return (
    <div className="space-y-3">
      {quarters.map((quarter) => (
        <div key={quarter}>
          <h4 className="text-xs font-semibold uppercase tracking-wide text-textSecondary">{quarterLabel(quarter)}</h4>
          <ul className="mt-1 space-y-0.5 text-sm text-charcoal dark:text-white">
            {summary.plays
              .filter((play) => play.quarter === quarter)
              .map((play, index) => (
                <li key={index} className="flex justify-between gap-3">
                  <span>{playLine(play)}</span>
                  <span className="shrink-0 text-textSecondary">
                    {summary.home} {play.homeScore}, {summary.away} {play.awayScore}
                  </span>
                </li>
              ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

// Every score of the game in order, read off the broadcast scoreboard of a stream recording by tools/scouting.
// Attaching is local-only (the backend lists recordings from streams/ on this Mac); once attached it lives on the
// game, feeds the recap's AI pass and prints in the podcast markdown.
function ScoringSummaryPanel({ gameId, played, summary, onChange }) {
  const [recordings, setRecordings] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (summary || !played || !import.meta.env.DEV) return undefined;
    let cancelled = false;
    fetchScoringRecordings(gameId)
      .then((data) => !cancelled && setRecordings(data.recordings))
      .catch(() => !cancelled && setRecordings([]));
    return () => {
      cancelled = true;
    };
  }, [gameId, played, summary]);

  const run = async (action) => {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (e) {
      setError(e.response?.data?.error || "Something went wrong.");
    } finally {
      setBusy(false);
    }
  };

  const handleAttach = (recordingId) => run(async () => onChange((await attachScoringSummary(gameId, recordingId)).scoringSummary));
  const handleDetach = () => run(async () => {
    await detachScoringSummary(gameId);
    onChange(null);
  });

  if (summary) {
    return (
      <div className="space-y-3">
        <div className="flex items-start justify-between gap-3">
          <p className="text-xs text-textSecondary">
            From <span className="font-semibold">{summary.source}</span>.{" "}
            {summary.verified ? "The plays add up to the final score." : "The plays don't add up to the final score, so treat this as a rough guide."}
          </p>
          <button
            type="button"
            onClick={handleDetach}
            disabled={busy}
            className="shrink-0 rounded-md border border-border px-3 py-1.5 text-xs text-charcoal transition hover:bg-border/30 disabled:opacity-60 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Remove
          </button>
        </div>
        <SummaryBody summary={summary} />
        {error && <p className="text-sm text-danger">{error}</p>}
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <p className="text-xs text-textSecondary">
        Optional. Every score in order (who, touchdown or field goal, clock), read from a stream recording of this game. It gives the
        recap and the podcast markdown the flow of the game, not just the quarter totals.
      </p>
      {!played ? (
        <p className="text-sm text-textSecondary">Save the box score first: recordings are matched to the game by its final score.</p>
      ) : !import.meta.env.DEV ? (
        <p className="text-sm text-textSecondary">Attach one from a local checkout, where the stream recordings live.</p>
      ) : recordings === null ? (
        <p className="text-sm text-textSecondary">Looking for recordings…</p>
      ) : recordings.length === 0 ? (
        <p className="text-sm text-textSecondary">No scouted recording has this game&apos;s final score.</p>
      ) : (
        <ul className="space-y-2">
          {recordings.map((recording) => (
            <li key={recording.id} className="flex items-center justify-between gap-3 text-sm">
              <span className="text-charcoal dark:text-white">
                {recording.id} <span className="text-textSecondary">· {recording.plays} scores{recording.verified ? "" : " · doesn't add up"}</span>
              </span>
              <button
                type="button"
                onClick={() => handleAttach(recording.id)}
                disabled={busy}
                className="shrink-0 rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                Attach
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && <p className="text-sm text-danger">{error}</p>}
    </div>
  );
}

export default ScoringSummaryPanel;
