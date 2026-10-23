import { useCallback, useEffect, useRef, useState } from "react";
import { clsx } from "clsx";
import Card from "./Card";
import {
  fetchPodcastEpisode,
  fetchPodcastFileUrl,
  fetchPodcastScript,
  savePodcastScript,
  startPodcastStep,
} from "../lib/apiClient";

const POLL_MS = 3000;

const buttonPrimary =
  "rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:translate-y-0";
const buttonSecondary =
  "rounded-md border border-border px-4 py-2 text-sm text-charcoal transition hover:bg-border/30 disabled:cursor-not-allowed disabled:opacity-60 dark:border-darkborder dark:text-white dark:hover:bg-white/10";

function StepRow({ state, label, detail }) {
  const icon = { done: "✓", running: "…", failed: "✕", pending: "○" }[state];
  return (
    <li className="flex items-start gap-3">
      <span
        className={clsx(
          "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs font-bold",
          state === "done" && "bg-success text-white",
          state === "running" && "animate-pulse bg-burnt text-white",
          state === "failed" && "bg-danger text-white",
          state === "pending" && "border border-border text-textSecondary dark:border-darkborder",
        )}
        aria-hidden="true"
      >
        {icon}
      </span>
      <div className="min-w-0">
        <p className={clsx("text-sm", state === "pending" ? "text-textSecondary" : "text-charcoal dark:text-white")}>
          {label}
        </p>
        {detail && <p className="text-xs text-textSecondary">{detail}</p>}
      </div>
    </li>
  );
}

function Collapsible({ title, children, onOpen }) {
  return (
    <details
      className="rounded-md border border-border dark:border-darkborder"
      onToggle={(event) => event.currentTarget.open && onOpen?.()}
    >
      <summary className="cursor-pointer px-3 py-2 text-sm font-semibold text-charcoal dark:text-white">{title}</summary>
      <div className="border-t border-border p-3 dark:border-darkborder">{children}</div>
    </details>
  );
}

function ScriptEditor({ dynastyId, seasonId, weekNumber, locked, onSaved }) {
  const [text, setText] = useState(null);
  const [saved, setSaved] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(async () => {
    if (text !== null) return;
    try {
      const script = await fetchPodcastScript(dynastyId, seasonId, weekNumber);
      setText(script || "");
      setSaved(script || "");
    } catch (err) {
      setError(err.message);
    }
  }, [dynastyId, seasonId, weekNumber, text]);

  const save = async () => {
    setBusy(true);
    setError(null);
    try {
      await savePodcastScript(dynastyId, seasonId, weekNumber, text);
      setSaved(text);
      onSaved();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Collapsible title="Script (edit before approving)" onOpen={load}>
      {text === null ? (
        <p className="text-sm text-textSecondary">{error || "Loading the script..."}</p>
      ) : (
        <div className="space-y-2">
          <p className="text-xs text-textSecondary">
            One line per turn, each starting with &ldquo;ARLIS: &rdquo; or &ldquo;TY: &rdquo;. Editing after the voices
            are made means producing the audio again.
          </p>
          <textarea
            value={text}
            onChange={(event) => setText(event.target.value)}
            disabled={locked}
            rows={16}
            className="w-full rounded-md border border-border bg-transparent p-2 font-mono text-xs text-charcoal dark:border-darkborder dark:text-white"
          />
          <div className="flex items-center gap-3">
            <button type="button" onClick={save} disabled={busy || locked || text === saved} className={buttonSecondary}>
              {busy ? "Saving..." : "Save script"}
            </button>
            {text !== saved && <span className="text-xs text-warning">Unsaved changes</span>}
            {error && <span className="text-xs text-danger">{error}</span>}
          </div>
        </div>
      )}
    </Collapsible>
  );
}

function AudioPlayer({ dynastyId, seasonId, weekNumber, version }) {
  const [url, setUrl] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => () => url && URL.revokeObjectURL(url), [url]);
  useEffect(() => setUrl(null), [version]);

  const load = async () => {
    setBusy(true);
    setError(null);
    try {
      setUrl(await fetchPodcastFileUrl(dynastyId, seasonId, weekNumber, "audio"));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  if (url) return <audio controls src={url} className="w-full" />;
  return (
    <div className="flex items-center gap-3">
      <button type="button" onClick={load} disabled={busy} className={buttonSecondary}>
        {busy ? "Loading audio..." : "Load audio to listen"}
      </button>
      {error && <span className="text-xs text-danger">{error}</span>}
    </div>
  );
}

function PodcastEpisodePanel({ season, weeks }) {
  const [weekNumber, setWeekNumber] = useState(null);
  const [episode, setEpisode] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [actionError, setActionError] = useState(null);
  const [starting, setStarting] = useState(false);
  const [artUrl, setArtUrl] = useState(null);
  const [mediaVersion, setMediaVersion] = useState(0);
  const [episodeNumber, setEpisodeNumber] = useState("");
  const wasRunning = useRef(false);

  const dynastyId = season.dynastyId;
  const seasonId = season.id;

  const load = useCallback(async () => {
    if (weekNumber === null) return null;
    try {
      const data = await fetchPodcastEpisode(dynastyId, seasonId, weekNumber);
      setEpisode(data);
      setLoadError(null);
      return data;
    } catch (err) {
      setLoadError(err.message);
      return null;
    }
  }, [dynastyId, seasonId, weekNumber]);

  // Picking a week resets everything, then loads that week's state.
  useEffect(() => {
    setEpisode(null);
    setActionError(null);
    setEpisodeNumber("");
    wasRunning.current = false;
    load();
  }, [load]);

  const running = episode?.job?.state === "running";

  // Poll while a step runs in the background; when it ends, reload the media it may have changed.
  useEffect(() => {
    if (!running) {
      if (wasRunning.current) setMediaVersion((v) => v + 1);
      wasRunning.current = false;
      return undefined;
    }
    wasRunning.current = true;
    const timer = setInterval(load, POLL_MS);
    return () => clearInterval(timer);
  }, [running, load]);

  const hasArt = episode?.steps?.art;
  useEffect(() => {
    if (!hasArt || weekNumber === null) {
      setArtUrl(null);
      return undefined;
    }
    let cancelled = false;
    let created = null;
    fetchPodcastFileUrl(dynastyId, seasonId, weekNumber, "art")
      .then((url) => {
        created = url;
        if (cancelled) URL.revokeObjectURL(url);
        else setArtUrl(url);
      })
      .catch(() => !cancelled && setArtUrl(null));
    return () => {
      cancelled = true;
      if (created) URL.revokeObjectURL(created);
    };
  }, [hasArt, weekNumber, dynastyId, seasonId, mediaVersion]);

  const start = async (step, body = {}) => {
    setStarting(true);
    setActionError(null);
    try {
      setEpisode(await startPodcastStep(dynastyId, seasonId, weekNumber, step, body));
    } catch (err) {
      setActionError(err.message);
    } finally {
      setStarting(false);
    }
  };

  const steps = episode?.steps || {};
  const job = episode?.job || {};
  const failed = job.state === "failed" || job.state === "interrupted";
  const busy = starting || running;
  const prepared = steps.factCheck;
  const needsAudio = prepared && !steps.published && (!steps.audio || episode.audioStale);
  const episodeToPublish = episodeNumber === "" ? episode?.suggestedEpisode : Number(episodeNumber);

  const publish = () => {
    const replacing = steps.published ? "\n\nThis episode is already in the feed; publishing replaces its audio and details." : "";
    const ok = window.confirm(
      `Publish "${episode.title}" as Season ${episode.seasonNumber}, Episode ${episodeToPublish}?\n\n` +
        `Spotify and other apps pick it up from the feed on their own.${replacing}`,
    );
    if (ok) start("publish", { episode: episodeToPublish });
  };

  const stepState = (done, runningNames) => {
    if (done) return "done";
    if (running && runningNames.includes(job.name)) return "running";
    if (failed && runningNames.includes(job.name)) return "failed";
    return "pending";
  };

  const activeDetail = (names) => (running && names.includes(job.name) ? job.message : undefined);
  const factCheck = episode?.factCheck;
  const factCheckSummary =
    factCheck && factCheck.fixed !== undefined
      ? `${factCheck.fixed} fixed automatically, ${factCheck.needsReview} need your call, ${factCheck.rejected} flagged but left alone`
      : undefined;

  return (
    <Card>
      <div className="space-y-5 p-5">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Weekly Episode</h3>
          <p className="mt-1 text-sm text-textSecondary">
            One episode of Rising in the Sun Belt: a recap of the week you pick, then a preview of the next week&rsquo;s
            games with the hosts&rsquo; bets. The script is written and fact-checked from your data, voiced, mixed and
            published to the podcast feed, with a pause for you to review it before anything is voiced.
          </p>
        </div>

        <div className="space-y-1.5">
          <p className="text-xs uppercase tracking-wide text-textSecondary">Week to recap</p>
          <p className="text-xs text-textSecondary/80">
            The week after it is previewed. Run this once the game is advanced, the rosters, poll and lines are updated.
          </p>
          <div className="flex flex-wrap gap-2 pt-1">
            {weeks.map((week) => (
              <button
                key={week.number}
                type="button"
                disabled={running}
                onClick={() => setWeekNumber(week.number)}
                className={clsx(
                  "rounded-md border px-3 py-1.5 text-sm transition disabled:cursor-not-allowed disabled:opacity-60",
                  weekNumber === week.number
                    ? "border-burnt bg-burnt text-white"
                    : "border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10",
                )}
              >
                {week.label}
              </button>
            ))}
          </div>
        </div>

        {loadError && <p className="text-sm text-danger">{loadError}</p>}

        {weekNumber !== null && episode && (
          <div className="grid gap-6 border-t border-border pt-5 dark:border-darkborder md:grid-cols-[minmax(0,22rem)_1fr]">
            <div className="space-y-3">
              <div className="aspect-square overflow-hidden rounded-lg border border-border bg-charcoal/5 dark:border-darkborder dark:bg-white/5">
                {artUrl ? (
                  <img src={artUrl} alt={`Cover art for Week ${weekNumber}`} className="h-full w-full object-cover" />
                ) : (
                  <div className="flex h-full items-center justify-center p-6 text-center text-sm text-textSecondary">
                    {running && ["prepare", "regenerate_art"].includes(job.name)
                      ? "Artwork is generated early in the run..."
                      : "The cover art shows up here once the episode is prepared."}
                  </div>
                )}
              </div>
              {steps.art && !steps.published && (
                <button type="button" disabled={busy} onClick={() => start("regenerate_art")} className={buttonSecondary}>
                  Regenerate art
                </button>
              )}
              {episode.recapOnly && (
                <p className="text-xs text-textSecondary">
                  No coached team plays Week {episode.previewWeek}, so this is a recap-only episode with the show cover.
                </p>
              )}
            </div>

            <div className="space-y-4">
              <div>
                <p className="font-semibold text-charcoal dark:text-white">
                  {episode.title || `${season.year} Week ${weekNumber} Reactions | Week ${episode.previewWeek} Preview`}
                </p>
                <p className="text-xs text-textSecondary">
                  Season {episode.seasonNumber} · Episode {steps.published ? episode.published.episode : episodeToPublish}
                </p>
              </div>

              <ul className="space-y-3">
                <StepRow
                  state={stepState(steps.markdown, ["prepare"])}
                  label={`Recap and Week ${episode.previewWeek} preview from your data`}
                  detail={activeDetail(["prepare"])}
                />
                <StepRow state={steps.art ? "done" : stepState(false, ["prepare", "regenerate_art"])} label="Cover art" />
                <StepRow
                  state={steps.script ? "done" : stepState(false, ["prepare"])}
                  label="Script"
                  detail={episode.scriptWords ? `${episode.scriptWords.toLocaleString()} words, about ${Math.round(episode.scriptWords / 189)} min` : undefined}
                />
                <StepRow state={stepState(steps.factCheck, ["prepare"])} label="Fact-check" detail={factCheckSummary} />
                <StepRow
                  state={stepState((steps.audio && !episode.audioStale) || steps.published, ["produce"])}
                  label="Voices and music mix"
                  detail={activeDetail(["produce"]) || (episode.audioStale ? "The script changed since the voices were made" : undefined)}
                />
                <StepRow
                  state={stepState(steps.published, ["publish"])}
                  label="Published to the podcast feed"
                  detail={activeDetail(["publish"])}
                />
              </ul>

              {failed && (
                <div className="rounded-md border border-danger/40 bg-danger/5 p-3 text-sm text-danger">
                  <p className="font-semibold">
                    {job.state === "interrupted" ? "The last step was interrupted" : `The ${job.name?.replace("_", " ")} step failed`}
                  </p>
                  <p className="mt-1 break-words text-xs">{job.error || job.message}</p>
                  <p className="mt-1 text-xs">Run the step again: finished work is kept, so it picks up where it stopped.</p>
                </div>
              )}
              {actionError && <p className="text-sm text-danger">{actionError}</p>}

              {!prepared && (
                <div className="space-y-2">
                  <button type="button" disabled={busy} onClick={() => start("prepare")} className={buttonPrimary}>
                    {running && job.name === "prepare" ? "Preparing..." : failed && job.name === "prepare" ? "Retry preparing" : "Prepare episode"}
                  </button>
                  <p className="text-xs text-textSecondary">
                    Builds the recap and preview, generates the cover, writes the script and fact-checks it (about 12 minutes).
                    Previewing locks Week {episode.previewWeek}&rsquo;s lines and picks, the same as the old export did. Nothing is
                    voiced or published yet.
                  </p>
                </div>
              )}

              {prepared && (
                <div className="space-y-3">
                  {factCheck?.report && (
                    <Collapsible title={`Fact-check report${factCheckSummary ? ` (${factCheckSummary})` : ""}`}>
                      <pre className="max-h-96 overflow-auto whitespace-pre-wrap text-xs text-textSecondary">{factCheck.report}</pre>
                    </Collapsible>
                  )}
                  <ScriptEditor
                    key={`${weekNumber}-${mediaVersion}`}
                    dynastyId={dynastyId}
                    seasonId={seasonId}
                    weekNumber={weekNumber}
                    locked={busy}
                    onSaved={load}
                  />
                </div>
              )}

              {needsAudio && (
                <div className="space-y-2 border-t border-border pt-4 dark:border-darkborder">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => start("produce", { redo: Boolean(episode.audioStale) })}
                    className={buttonPrimary}
                  >
                    {running && job.name === "produce" ? "Producing..." : episode.audioStale ? "Produce the audio again" : "Approve and produce audio"}
                  </button>
                  <p className="text-xs text-textSecondary">
                    Voices and mixes the reviewed script (about 10 minutes, and it uses paid voice credits), then writes the
                    description. You can listen before anything is published.
                  </p>
                </div>
              )}

              {steps.audio && !episode.audioStale && (
                <div className="space-y-3 border-t border-border pt-4 dark:border-darkborder">
                  <AudioPlayer dynastyId={dynastyId} seasonId={seasonId} weekNumber={weekNumber} version={mediaVersion} />
                  {episode.description && (
                    <Collapsible title="Episode description">
                      <p className="whitespace-pre-wrap text-sm text-textSecondary">{episode.description}</p>
                    </Collapsible>
                  )}
                  <div className="flex flex-wrap items-end gap-3">
                    <label className="space-y-1">
                      <span className="block text-xs uppercase tracking-wide text-textSecondary">Episode number</span>
                      <input
                        type="number"
                        min="1"
                        value={episodeNumber === "" ? episode.suggestedEpisode ?? "" : episodeNumber}
                        onChange={(event) => setEpisodeNumber(event.target.value)}
                        disabled={steps.published}
                        className="w-24 rounded-md border border-border bg-transparent px-2 py-1.5 text-sm text-charcoal dark:border-darkborder dark:text-white"
                      />
                    </label>
                    <button type="button" disabled={busy} onClick={publish} className={buttonPrimary}>
                      {running && job.name === "publish" ? "Publishing..." : steps.published ? "Publish again (replaces)" : "Publish to the podcast feed"}
                    </button>
                  </div>
                </div>
              )}

              {steps.published && (
                <div className="rounded-md border border-success/40 bg-success/5 p-3 text-sm text-charcoal dark:text-white">
                  <p className="font-semibold text-success">Published</p>
                  <p className="mt-1 text-xs text-textSecondary">
                    Season {episode.published.season}, Episode {episode.published.episode}. Spotify picks it up from the feed on
                    its own; paste the episode link into the group chat once it appears.
                  </p>
                  <p className="mt-1 break-all font-mono text-xs text-textSecondary">{episode.feedUrl}</p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </Card>
  );
}

export default PodcastEpisodePanel;
