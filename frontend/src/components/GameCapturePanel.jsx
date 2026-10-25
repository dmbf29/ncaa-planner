import { useEffect, useRef, useState } from "react";
import Card from "./Card";
import { cancelGameCapture, fetchGameCaptureStatus, finishGameCapture, startGameCapture } from "../lib/apiClient";

const POLL_MS = 1500;

// Player Stats screens to expect per team. Defense spans two pages of rows and
// each page also has a scrolled-right view, whose columns the watcher grafts
// names onto (category "defense_extra") — so 2 + 2.
const TEAM_CHECKLIST = [
  { category: "passing", label: "Passing", need: 1 },
  { category: "rushing", label: "Rushing", need: 1 },
  { category: "receiving", label: "Receiving", need: 1 },
  { category: "defense", label: "Defense", need: 2 },
  { category: "defense_extra", label: "Defense, scrolled right", need: 2 },
];

const countFor = (screens, test) => screens.filter(test).length;

function ChecklistRow({ label, have, need }) {
  const done = have >= need;
  return (
    <li className={`flex items-center justify-between gap-2 text-sm ${done ? "text-success" : "text-textSecondary"}`}>
      <span>
        {done ? "✓" : "○"} {label}
      </span>
      {need > 1 && (
        <span className="text-xs">
          {Math.min(have, need)}/{need}
        </span>
      )}
    </li>
  );
}

// Local-only: starts tools/capture/watch.py via the Rails server, which
// screenshots the PS Remote Play window each time you pause on a new screen
// while navigating with a controller. "Finish" hands the captures to the
// normal analyze flow. Rendered only in dev; the backend refuses otherwise.
function GameCapturePanel({ gameId, homeName, awayName, disabled, onFinished, onBusyChange }) {
  const [phase, setPhase] = useState("idle"); // idle | running | saved | analyzing
  const [screens, setScreens] = useState([]);
  const [unpaired, setUnpaired] = useState([]);
  const [skipped, setSkipped] = useState([]);
  const [error, setError] = useState(null);
  const [note, setNote] = useState(null);
  const onBusyRef = useRef(onBusyChange);
  onBusyRef.current = onBusyChange;

  // Resume a capture that was already running (page refresh, navigation).
  useEffect(() => {
    let cancelled = false;
    fetchGameCaptureStatus(gameId)
      .then((s) => {
        if (cancelled || (!s.running && s.screens.length === 0)) return;
        setScreens(s.screens);
        setUnpaired(s.unpaired || []);
        setSkipped(s.skipped || []);
        // Not running but screens on disk: a finished-but-unanalyzed capture (e.g. the server restarted).
        setPhase(s.running ? "running" : "saved");
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [gameId]);

  useEffect(() => {
    if (phase !== "running") return undefined;
    const timer = setInterval(() => {
      fetchGameCaptureStatus(gameId)
        .then((s) => {
          setScreens(s.screens);
          setUnpaired(s.unpaired || []);
          setSkipped(s.skipped || []);
        })
        .catch(() => {});
    }, POLL_MS);
    return () => clearInterval(timer);
  }, [phase, gameId]);

  useEffect(() => {
    onBusyRef.current?.(phase === "analyzing");
  }, [phase]);

  const handleStart = async () => {
    setError(null);
    setNote(null);
    try {
      const s = await startGameCapture(gameId);
      setScreens(s.screens);
      setPhase("running");
    } catch (err) {
      setError(err.response?.data?.error || err.message);
    }
  };

  const phaseBeforeAnalyze = useRef("running");
  const handleFinish = async () => {
    setError(null);
    phaseBeforeAnalyze.current = phase;
    setPhase("analyzing");
    try {
      const { analysis, unassigned, unpaired: leftUnpaired, partialRows } = await finishGameCapture(gameId);
      const notes = [];
      if (unassigned?.length) {
        notes.push(`${unassigned.length} captured screen(s) couldn't be matched to either team and were skipped: ${unassigned.join(", ")}`);
      }
      if (leftUnpaired > 0) {
        notes.push(`${leftUnpaired} Defense screen(s) never got their matching left/right view, so the right-hand Defense stats for those pages were skipped.`);
      }
      if (partialRows > 0) {
        notes.push(`The Defense list scrolled between some left/right captures, so ${partialRows} player row(s) are missing their right-hand stats (FFUMB, FMBREC, ...). Everything else for them was saved.`);
      }
      if (analysis.warnings?.length) notes.push(...analysis.warnings);
      if (analysis.usage?.calls) {
        notes.push(`Analysis used ${analysis.usage.calls} AI calls (${analysis.usage.inputTokens.toLocaleString()} tokens in, ${analysis.usage.outputTokens.toLocaleString()} out), about $${analysis.usage.cost.toFixed(2)}.`);
      }
      setNote(notes.length ? notes.join(" · ") : null);
      await onFinished(analysis);
      setScreens([]);
      setUnpaired([]);
      setPhase("idle");
    } catch (err) {
      setError(err.response?.data?.error || err.message);
      setPhase(phaseBeforeAnalyze.current);
    }
  };

  const handleCancel = async () => {
    await cancelGameCapture(gameId).catch(() => {});
    setScreens([]);
    setPhase("idle");
  };

  const boxScoreCount = countFor(screens, (s) => s.kind === "box_score");
  const teams = [
    { name: awayName, label: "Away" },
    { name: homeName, label: "Home" },
  ];

  return (
    <Card>
      <div className="space-y-3 px-5 py-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
              Capture from Remote Play
            </h3>
            <p className="mt-0.5 text-xs text-textSecondary">
              {phase === "idle" &&
                "Local only. Start, then page through the box score and each team's player stats with your controller, pausing on each screen until you hear a Tink."}
              {phase === "running" && "Capturing. Pause about a second on each screen until you hear the Tink. For Defense: page 1, scroll right, scroll down, scroll left."}
              {phase === "saved" && `A capture with ${screens.length} saved screens is waiting. Analyze it, or discard it to start over.`}
              {phase === "analyzing" && "Wrapping up the last captures and running the analysis..."}
            </p>
          </div>

          {phase === "idle" && (
            <button
              type="button"
              onClick={handleStart}
              disabled={disabled}
              className="rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Start Capture
            </button>
          )}
          {(phase === "running" || phase === "saved") && (
            <div className="flex gap-2">
              <button
                type="button"
                onClick={handleFinish}
                disabled={screens.length === 0}
                className="rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {phase === "saved" ? "Analyze Saved Capture" : "Finish & Analyze"} ({screens.length})
              </button>
              <button
                type="button"
                onClick={handleCancel}
                className="rounded-md border border-border px-3 py-1.5 text-xs text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                {phase === "saved" ? "Discard" : "Cancel"}
              </button>
            </div>
          )}
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}
        {note && <p className="text-sm text-warning">{note}</p>}

        {(phase === "running" || phase === "saved") && skipped.length > 0 && (
          <p className="text-xs text-warning">
            Not counted: {skipped.map((s) => `${s.team || "a team"} ${s.category}`).join(", ")} showed only players with 0 carries. Sort the
            table by CAR so the most carries are on top, then pause on it again.
          </p>
        )}

        {phase === "running" && unpaired.length > 0 && (
          <p className="text-xs text-warning">
            Waiting for the matching Defense view: {unpaired.map((u) => `${u.team} (${u.hscroll})`).join(", ")}. Scroll sideways
            without moving up or down, then pause — if the list scrolled in between, go back to that page and redo the pair.
          </p>
        )}

        {(phase === "running" || phase === "saved") && (
          <div className="grid gap-x-6 gap-y-3 sm:grid-cols-3">
            <div>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">Box Score</p>
              <ul className="space-y-0.5">
                <ChecklistRow label="Both pages" have={boxScoreCount} need={2} />
              </ul>
            </div>
            {teams.map(({ name, label }) => (
              <div key={label}>
                <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                  {label} · {name}
                </p>
                <ul className="space-y-0.5">
                  {TEAM_CHECKLIST.map(({ category, label: rowLabel, need }) => (
                    <ChecklistRow
                      key={category}
                      label={rowLabel}
                      have={countFor(screens, (s) => s.team === name && s.category === category)}
                      need={need}
                    />
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </div>
    </Card>
  );
}

export default GameCapturePanel;
