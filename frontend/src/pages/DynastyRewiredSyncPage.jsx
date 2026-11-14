import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import useLatestSeason from "../lib/useLatestSeason";
import {
  fetchDynastyRewiredRosterSchools,
  fetchDynastyRewiredSync,
  refreshDynastyRewiredRoster,
  runDynastyRewiredSync,
} from "../lib/apiClient";

const POLL_LABELS = { playoff: "CFP Top 25", media: "Media poll" };

const SECTION_NOUNS = {
  results: ["game score", "game scores"],
  boxScores: ["box score", "box scores"],
  rankings: ["Top 25", "Top 25s"],
  recruiting: ["class ranking", "class rankings"],
};

const plural = (count, [one, many]) => `${count} ${count === 1 ? one : many}`;

function SectionCard({ title, hint, count, checked, onToggle, children }) {
  return (
    <Card>
      <div className="space-y-3 p-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h3>
            <p className="text-sm text-textSecondary">{hint}</p>
          </div>
          {count > 0 ? (
            <label className="flex shrink-0 items-center gap-2 text-sm font-semibold text-charcoal dark:text-white">
              <input type="checkbox" checked={checked} onChange={onToggle} className="h-4 w-4 accent-burnt" />
              Import {count}
            </label>
          ) : (
            <span className="shrink-0 rounded-full bg-success/10 px-2 py-0.5 text-xs font-semibold text-success">Nothing new</span>
          )}
        </div>
        {children}
      </div>
    </Card>
  );
}

function Warning({ children }) {
  return <p className="rounded-md bg-warning/10 px-3 py-2 text-sm text-warning">{children}</p>;
}

function ResultsSection({ results, checked, onToggle }) {
  return (
    <SectionCard
      title="Game results"
      hint="Final scores for every game of each week, including the CPU games."
      count={results.newGames}
      checked={checked}
      onToggle={onToggle}
    >
      <ul className="space-y-1 text-sm text-textPrimary dark:text-white">
        {results.weeks.map((week) => (
          <li key={week.weekNumber}>
            <span className="font-semibold">Week {week.weekNumber}</span>
            {week.newGames > 0 && <span className="text-textSecondary"> · {plural(week.newGames, ["game", "games"])} missing a score</span>}
            {week.conflicts.map((conflict) => (
              <Warning key={`${conflict.game}-${conflict.team}`}>
                {conflict.game}: you have {conflict.team} at {conflict.saved}, Dynasty Rewired says {conflict.api}. Not changed.
              </Warning>
            ))}
            {week.unmatched.map((game) => (
              <Warning key={game}>{game} isn&rsquo;t in your schedule, so it was skipped.</Warning>
            ))}
          </li>
        ))}
      </ul>
    </SectionCard>
  );
}

function BoxScoresSection({ boxScores, checked, onToggle }) {
  return (
    <SectionCard
      title="Box scores"
      hint="Team and player stats. Players are matched to your roster by name; none are created."
      count={boxScores.new.length}
      checked={checked}
      onToggle={onToggle}
    >
      <ul className="space-y-1 text-sm text-textPrimary dark:text-white">
        {boxScores.new.map((game) => (
          <li key={game.gameId}>
            <span className="font-semibold">{game.label}</span>
            <span className="text-textSecondary"> · Week {game.weekNumber} · {game.score} · {game.playerLines} player lines</span>
          </li>
        ))}
      </ul>
      {boxScores.held.map((game) => (
        <Warning key={game.label}>
          Held back: {game.label}. {game.reason}
          {game.players.length > 0 && `: ${game.players.join(", ")}`}.
        </Warning>
      ))}
      {boxScores.saved > 0 && <p className="text-xs text-textSecondary">{boxScores.saved} box scores already saved.</p>}
    </SectionCard>
  );
}

function RankingsSection({ rankings, importable, checked, onToggle }) {
  return (
    <SectionCard
      title="Top 25"
      hint="The media poll before Week 10, the CFP poll from Week 10 on."
      count={importable}
      checked={checked}
      onToggle={onToggle}
    >
      <ul className="space-y-2 text-sm text-textPrimary dark:text-white">
        {rankings.map((item) => (
          <li key={item.weekNumber}>
            <span className="font-semibold">Week {item.weekNumber}</span>
            <span className="text-textSecondary"> · {POLL_LABELS[item.poll] || item.poll} · {item.status === "new" ? "not saved yet" : item.status === "saved" ? "already saved" : item.status}</span>
            {item.status === "new" && item.top && <p className="text-xs text-textSecondary">{item.top.join("  ")} …</p>}
            {item.status === "differs" && <Warning>Dynasty Rewired&rsquo;s poll differs from the Top 25 you saved for this week. Not changed.</Warning>}
            {item.status === "attention" && <Warning>This poll didn&rsquo;t have 25 schools that all matched yours{item.unmatchedSchools?.length ? `: ${item.unmatchedSchools.join(", ")}` : ""}.</Warning>}
            {item.status === "unavailable" && <Warning>{item.message}</Warning>}
          </li>
        ))}
      </ul>
    </SectionCard>
  );
}

function RostersSection({ dynastyId, seasonId }) {
  const [schools, setSchools] = useState(null);
  const [choice, setChoice] = useState("all");
  const [progress, setProgress] = useState(null);
  const [summary, setSummary] = useState(null);
  const [error, setError] = useState(null);
  const running = progress !== null;

  useEffect(() => {
    if (!dynastyId) return;
    fetchDynastyRewiredRosterSchools(dynastyId, seasonId)
      .then((data) => setSchools(data.schools))
      .catch((err) => setError(err.message));
  }, [dynastyId, seasonId]);

  const refresh = async () => {
    const targets = choice === "all" ? schools : schools.filter((school) => school.name === choice);
    const totals = { updated: 0, unchanged: 0, unmatched: [], missing: [] };
    setError(null);
    setSummary(null);
    try {
      for (const [index, school] of targets.entries()) {
        setProgress({ done: index, total: targets.length, name: school.name });
        const result = await refreshDynastyRewiredRoster(dynastyId, seasonId, school.name, school.teamId);
        totals.updated += result.updated;
        totals.unchanged += result.unchanged;
        result.unmatched.forEach((name) => totals.unmatched.push(`${name} (${school.name})`));
        result.missing.forEach((name) => totals.missing.push(`${name} (${school.name})`));
      }
      setSummary({ ...totals, schools: targets.length });
    } catch (err) {
      setError(`${err.message}${totals.updated ? ` Stopped after saving ${plural(totals.updated, ["player", "players"])}.` : ""}`);
    } finally {
      setProgress(null);
    }
  };

  return (
    <Card>
      <div className="space-y-3 p-5">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Rosters</h3>
          <p className="text-sm text-textSecondary">
            Refreshes ratings, height and weight for players already on a roster, matched by name. Positions and class years are never
            changed and nobody is added. Saves as it goes; all schools takes about 4 minutes.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <select
            value={choice}
            onChange={(event) => setChoice(event.target.value)}
            disabled={!schools || running}
            className="rounded-md border border-border bg-transparent px-3 py-2 text-sm text-charcoal dark:border-darkborder dark:text-white"
          >
            <option value="all">All schools{schools ? ` (${schools.length})` : ""}</option>
            {(schools || []).map((school) => (
              <option key={school.teamId} value={school.name}>{school.name}</option>
            ))}
          </select>
          <button
            type="button"
            onClick={refresh}
            disabled={!schools || running}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {running ? "Refreshing..." : "Refresh ratings"}
          </button>
          {running && <span className="text-sm text-textSecondary">{progress.done + 1} of {progress.total}: {progress.name}</span>}
        </div>
        {error && <p className="text-sm text-danger">{error}</p>}
        {summary && (
          <div className="space-y-2">
            <p className="rounded-md bg-success/10 px-3 py-2 text-sm text-success">
              Refreshed {plural(summary.schools, ["school", "schools"])}: {plural(summary.updated, ["player", "players"])} updated, {summary.unchanged} already up to date.
            </p>
            {summary.unmatched.length > 0 && <Warning>In Dynasty Rewired but not on your roster (skipped): {summary.unmatched.join(", ")}.</Warning>}
            {summary.missing.length > 0 && <Warning>On your roster but not in Dynasty Rewired (check the spelling): {summary.missing.join(", ")}.</Warning>}
          </div>
        )}
      </div>
    </Card>
  );
}

function RecruitingSection({ recruiting, checked, onToggle }) {
  const count = recruiting.new + recruiting.changed;
  return (
    <SectionCard
      title="Recruiting classes"
      hint="National class rankings for every school: rank, points, commits and star counts. NIL spent is never changed."
      count={count}
      checked={checked}
      onToggle={onToggle}
    >
      <p className="text-sm text-textPrimary dark:text-white">
        <span className="font-semibold">{recruiting.classYear} class</span>
        <span className="text-textSecondary">
          {" "}· as of {recruiting.stage || "the latest capture"}{recruiting.finalized ? "" : ", not final yet"}
          {recruiting.new > 0 && ` · ${recruiting.new} not saved yet`}
          {recruiting.changed > 0 && ` · ${recruiting.changed} changed since you saved them`}
          {recruiting.same > 0 && ` · ${recruiting.same} up to date`}
        </span>
      </p>
      {recruiting.new > 0 && recruiting.top?.length > 0 && <p className="text-xs text-textSecondary">{recruiting.top.join("  ")} …</p>}
      {recruiting.unmatchedSchools?.length > 0 && <Warning>Schools not in your list, skipped: {recruiting.unmatchedSchools.join(", ")}.</Warning>}
    </SectionCard>
  );
}

function DynastyRewiredSyncPage() {
  const { dynastyId, seasonId, year, error: seasonError } = useLatestSeason();
  const [preview, setPreview] = useState(null);
  const [checked, setChecked] = useState({ results: false, boxScores: false, rankings: false, recruiting: false });
  const [loading, setLoading] = useState(false);
  const [importing, setImporting] = useState(false);
  const [error, setError] = useState(null);
  const [savedMessage, setSavedMessage] = useState(null);

  const acceptPreview = (next) => {
    setPreview(next);
    setChecked({
      results: next.results.newGames > 0,
      boxScores: next.boxScores.new.length > 0,
      rankings: next.rankings.some((item) => item.status === "new"),
      recruiting: next.recruiting.new + next.recruiting.changed > 0,
    });
  };

  const check = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      acceptPreview(await fetchDynastyRewiredSync(dynastyId, seasonId));
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [dynastyId, seasonId]);

  useEffect(() => {
    if (dynastyId) check();
  }, [dynastyId, check]);

  const importSelected = async () => {
    const sections = Object.entries({ results: "results", boxScores: "box_scores", rankings: "rankings", recruiting: "recruiting" })
      .filter(([key]) => checked[key])
      .map(([, name]) => name);
    setImporting(true);
    setError(null);
    try {
      const { saved, preview: next } = await runDynastyRewiredSync(dynastyId, seasonId, sections);
      setSavedMessage(
        [
          saved.results != null && `${plural(saved.results, ["game", "games"])} of scores`,
          saved.boxScores != null && plural(saved.boxScores, SECTION_NOUNS.boxScores),
          saved.rankings != null && plural(saved.rankings, SECTION_NOUNS.rankings),
          saved.recruiting != null && plural(saved.recruiting, SECTION_NOUNS.recruiting),
        ]
          .filter(Boolean)
          .join(", "),
      );
      acceptPreview(next);
    } catch (err) {
      setError(err.message);
    } finally {
      setImporting(false);
    }
  };

  const importableRankings = preview?.rankings.filter((item) => item.status === "new").length ?? 0;
  const anyChecked = Object.values(checked).some(Boolean);

  return (
    <div className="mx-auto max-w-4xl space-y-6 px-4">
      <PageHeader
        title="Dynasty Rewired Sync"
        eyebrow="Dynasty Updates"
        actions={
          <div className="flex gap-2">
            <button
              type="button"
              onClick={check}
              disabled={loading || importing || !dynastyId}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 disabled:opacity-60 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              {loading ? "Checking..." : "Check again"}
            </button>
            <Link
              to="/dynasty/updates"
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Back
            </Link>
          </div>
        }
      />

      <p className="text-sm text-textSecondary">
        Reads {year} from Dynasty Rewired{preview?.stage ? ` (currently ${preview.stage})` : ""} and shows what&rsquo;s new before anything is saved.
        Scores and polls you&rsquo;ve already saved are never overwritten.
      </p>

      {(seasonError || error) && <p className="text-sm text-danger">{seasonError || error}</p>}
      {savedMessage && <p className="rounded-md bg-success/10 px-3 py-2 text-sm text-success">Saved {savedMessage}.</p>}
      {loading && !preview && <p className="text-sm text-textSecondary">Checking Dynasty Rewired (about 10 seconds)...</p>}

      {preview && (
        <>
          <ResultsSection results={preview.results} checked={checked.results} onToggle={() => setChecked((c) => ({ ...c, results: !c.results }))} />
          <BoxScoresSection boxScores={preview.boxScores} checked={checked.boxScores} onToggle={() => setChecked((c) => ({ ...c, boxScores: !c.boxScores }))} />
          <RankingsSection
            rankings={preview.rankings}
            importable={importableRankings}
            checked={checked.rankings}
            onToggle={() => setChecked((c) => ({ ...c, rankings: !c.rankings }))}
          />
          <RecruitingSection recruiting={preview.recruiting} checked={checked.recruiting} onToggle={() => setChecked((c) => ({ ...c, recruiting: !c.recruiting }))} />

          <div className="flex justify-end">
            <button
              type="button"
              onClick={importSelected}
              disabled={importing || loading || !anyChecked}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {importing ? "Importing..." : "Import selected"}
            </button>
          </div>
        </>
      )}

      <RostersSection dynastyId={dynastyId} seasonId={seasonId} />
    </div>
  );
}

export default DynastyRewiredSyncPage;
