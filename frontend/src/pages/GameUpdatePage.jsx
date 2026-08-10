import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import ExistingScreenshotsGallery from "../components/ExistingScreenshotsGallery";
import GameSummary from "../components/GameSummary";
import { analyzeGameNarrative, analyzeGameStats, commitGameStats, fetchGame } from "../lib/apiClient";
import {
  TEAM_STAT_GROUPS,
  FIELD_LABELS,
  CATEGORY_FIELDS,
  PLAYER_FIELD_LABELS,
  POSITIONS,
  CLASS_YEARS,
  DEFAULT_POSITION_BY_CATEGORY,
  normalizeCollegeStats,
} from "../lib/gameStatFields";

const EMPTY_NARRATIVE = {
  narrativeSummary: "",
  offensePlayerOfGameId: null,
  offensePlayerStatLine: "",
  defensePlayerOfGameId: null,
  defensePlayerStatLine: "",
};

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

// When screenshots get analyzed on top of an already-reviewed game (e.g.
// a game that already has a final score from a schedule upload but no box
// score yet), merge the freshly extracted values in rather than replacing
// the review wholesale — a field the new screenshots didn't cover keeps
// whatever was already there instead of getting blanked out.
const mergeCollegeStats = (existingRows, freshRows) =>
  existingRows.map((existingRow) => {
    const freshRow = freshRows.find((row) => row.team === existingRow.team);
    if (!freshRow) return existingRow;

    const mergedFields = { ...existingRow.fields };
    Object.entries(freshRow.fields || {}).forEach(([key, value]) => {
      if (value != null) mergedFields[key] = value;
    });
    return { ...existingRow, fields: mergedFields };
  });

// A row the AI couldn't confidently match to the roster now gets a new
// Student/StudentSeason created on save instead of being silently
// dropped — pre-fill a reasonable starting position/class year so the
// review form isn't blank, since both are required fields on save.
const withUnmatchedDefaults = (playerStats) =>
  (playerStats || []).map((row) =>
    row.studentSeasonId
      ? row
      : {
          ...row,
          position: row.position || DEFAULT_POSITION_BY_CATEGORY[row.category] || POSITIONS[0],
          classYear: row.classYear || "FR",
        },
  );

const mergeAnalysis = (existing, fresh, awayCollege, homeCollege) => ({
  ...existing,
  screenshotSignedIds: [...(existing.screenshotSignedIds || []), ...(fresh.screenshotSignedIds || [])],
  collegeStats: mergeCollegeStats(existing.collegeStats, normalizeCollegeStats(fresh.collegeStats, awayCollege, homeCollege)),
  playerStats: [...existing.playerStats, ...withUnmatchedDefaults(fresh.playerStats)],
  homeRoster: existing.homeRoster?.length ? existing.homeRoster : fresh.homeRoster,
  awayRoster: existing.awayRoster?.length ? existing.awayRoster : fresh.awayRoster,
});

function NumberField({ label, value, onChange }) {
  return (
    <label className="flex flex-col gap-1 text-xs text-textSecondary">
      <span>{label}</span>
      <input
        type="number"
        step="any"
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
        className={inputClass}
      />
    </label>
  );
}

function FileDropZone({ label, hint, files, onFilesChange }) {
  const handleFileInput = (e) => {
    onFilesChange([...files, ...Array.from(e.target.files || [])]);
    e.target.value = "";
  };

  const removeFile = (index) => onFilesChange(files.filter((_, i) => i !== index));

  return (
    <div className="space-y-2 rounded-md border border-border p-3 dark:border-darkborder">
      <div>
        <p className="text-sm font-semibold text-textPrimary dark:text-white">{label}</p>
        {hint && <p className="text-xs text-textSecondary">{hint}</p>}
      </div>
      <input
        type="file"
        accept="image/*"
        multiple
        onChange={handleFileInput}
        className="block w-full text-xs text-textSecondary file:mr-3 file:rounded-md file:border-0 file:bg-burnt file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
      />
      {files.length > 0 && (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
          {files.map((file, index) => (
            <div key={`${file.name}-${index}`} className="relative">
              <img
                src={URL.createObjectURL(file)}
                alt={file.name}
                className="h-16 w-full rounded-md border border-border object-cover dark:border-darkborder"
              />
              <button
                type="button"
                onClick={() => removeFile(index)}
                className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-danger text-xs text-white"
              >
                ✕
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function UploadStep({ buckets, onBucketsChange, onAnalyze, analyzing, error, homeCollege, awayCollege, addingMore }) {
  const totalFiles = buckets.boxScore.length + buckets.home.length + buckets.away.length;

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
            {addingMore ? "Upload More Screenshots" : "Upload Screenshots"}
          </h3>
          <p className="mt-1 text-sm text-textSecondary">
            {addingMore
              ? "Add screenshots to fill in anything still missing — new values merge into the review below without touching what's already there."
              : "Upload the box score separately from each team’s player stat screens (passing/rushing/receiving/defense). The AI reads them and proposes stats below for you to review before anything is saved."}
          </p>
        </div>

        <FileDropZone
          label="Box Score"
          hint="1-2 shots covering both teams"
          files={buckets.boxScore}
          onFilesChange={(files) => onBucketsChange({ ...buckets, boxScore: files })}
        />
        <FileDropZone
          label={`${homeCollege.name} (Home) Player Stats`}
          hint="Passing/rushing/receiving/defense, up to 4 shots"
          files={buckets.home}
          onFilesChange={(files) => onBucketsChange({ ...buckets, home: files })}
        />
        <FileDropZone
          label={`${awayCollege.name} (Away) Player Stats`}
          hint="Passing/rushing/receiving/defense, up to 4 shots"
          files={buckets.away}
          onFilesChange={(files) => onBucketsChange({ ...buckets, away: files })}
        />

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onAnalyze}
          disabled={totalFiles === 0 || analyzing}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {analyzing ? "Analyzing... this can take a minute" : `Analyze ${totalFiles || ""} Photo${totalFiles === 1 ? "" : "s"}`}
        </button>
      </div>
    </Card>
  );
}

function ReferencePhotos({ buckets, homeCollege, awayCollege }) {
  const sections = [
    { label: "Box Score", files: buckets.boxScore },
    { label: `${homeCollege.name} (Home)`, files: buckets.home },
    { label: `${awayCollege.name} (Away)`, files: buckets.away },
  ].filter((section) => section.files.length > 0);

  if (sections.length === 0) return null;

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
          Uploaded Screenshots
        </h3>
        <p className="text-sm text-textSecondary">Reference these while reviewing the fields below. Click one to open it full-size.</p>
        {sections.map((section) => (
          <div key={section.label} className="space-y-2">
            <p className="text-xs uppercase tracking-wide text-textSecondary">{section.label}</p>
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-5">
              {section.files.map((file, index) => (
                <a key={`${file.name}-${index}`} href={URL.createObjectURL(file)} target="_blank" rel="noreferrer">
                  <img
                    src={URL.createObjectURL(file)}
                    alt={file.name}
                    className="h-24 w-full rounded-md border border-border object-cover transition hover:opacity-80 dark:border-darkborder"
                  />
                </a>
              ))}
            </div>
          </div>
        ))}
      </div>
    </Card>
  );
}

function NarrativeSection({ narrative, onChange, roster, onRunAnalysis, running, error }) {
  const update = (key, value) => onChange({ ...narrative, [key]: value });
  const hasContent = Boolean(narrative.narrativeSummary || narrative.offensePlayerOfGameId || narrative.defensePlayerOfGameId);

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Game Recap</h3>
          <button
            type="button"
            onClick={onRunAnalysis}
            disabled={running}
            className="rounded-md border border-burnt px-3 py-1.5 text-xs font-semibold text-burnt transition hover:bg-burnt/10 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {running ? "Running..." : hasContent ? "Re-run Game Analysis" : "Run Game Analysis"}
          </button>
        </div>
        <p className="text-xs text-textSecondary">
          Optional AI pass that writes a narrative summary and picks offense/defense players of the game from the
          stats above. Skip it for games you don&rsquo;t need a recap for.
        </p>
        {error && <p className="text-sm text-danger">{error}</p>}
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-xs uppercase tracking-wide text-textSecondary">Narrative Summary</span>
          <textarea
            rows={3}
            value={narrative.narrativeSummary || ""}
            onChange={(e) => update("narrativeSummary", e.target.value)}
            className={inputClass}
          />
        </label>

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <p className="text-xs uppercase tracking-wide text-textSecondary">Offense Player of the Game</p>
            <select
              value={narrative.offensePlayerOfGameId || ""}
              onChange={(e) => update("offensePlayerOfGameId", e.target.value ? Number(e.target.value) : null)}
              className={inputClass}
            >
              <option value="">— none —</option>
              {roster.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} ({p.position})
                </option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Stat line"
              value={narrative.offensePlayerStatLine || ""}
              onChange={(e) => update("offensePlayerStatLine", e.target.value)}
              className={inputClass}
            />
          </div>
          <div className="space-y-2">
            <p className="text-xs uppercase tracking-wide text-textSecondary">Defense Player of the Game</p>
            <select
              value={narrative.defensePlayerOfGameId || ""}
              onChange={(e) => update("defensePlayerOfGameId", e.target.value ? Number(e.target.value) : null)}
              className={inputClass}
            >
              <option value="">— none —</option>
              {roster.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} ({p.position})
                </option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Stat line"
              value={narrative.defensePlayerStatLine || ""}
              onChange={(e) => update("defensePlayerStatLine", e.target.value)}
              className={inputClass}
            />
          </div>
        </div>
      </div>
    </Card>
  );
}

function TeamStatsSection({ collegeStats, onChange, awayCollege, homeCollege }) {
  const findEntry = (name) => collegeStats.find((row) => row.team === name);

  const updateField = (team, key, value) => {
    onChange(collegeStats.map((row) => (row.team === team ? { ...row, fields: { ...row.fields, [key]: value } } : row)));
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Team Stats</h3>
        {TEAM_STAT_GROUPS.map((group) => (
          <div key={group.label} className="space-y-2">
            <p className="text-xs uppercase tracking-wide text-textSecondary">{group.label}</p>
            <div className="grid gap-3 sm:grid-cols-2">
              {[awayCollege, homeCollege].map((college) => {
                const entry = findEntry(college.name);
                return (
                  <div key={college.id} className="space-y-2 rounded-md border border-border p-3 dark:border-darkborder">
                    <p className="text-xs font-semibold text-textPrimary dark:text-white">{college.name}</p>
                    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
                      {group.fields.map((field) => (
                        <NumberField
                          key={field}
                          label={FIELD_LABELS[field]}
                          value={entry?.fields?.[field]}
                          onChange={(value) => updateField(college.name, field, value)}
                        />
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>
    </Card>
  );
}

function PlayerStatsSection({ playerStats, onChange, awayRoster, homeRoster, homeCollege }) {
  const rosterFor = (team) => (team === homeCollege.name ? homeRoster : awayRoster);

  const updateRow = (index, patch) => onChange(playerStats.map((row, i) => (i === index ? { ...row, ...patch } : row)));
  const updateField = (index, key, value) =>
    onChange(playerStats.map((row, i) => (i === index ? { ...row, fields: { ...row.fields, [key]: value } } : row)));
  const removeRow = (index) => onChange(playerStats.filter((_, i) => i !== index));

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Player Stats</h3>
        {playerStats.length === 0 && (
          <p className="text-sm text-textSecondary">No player stat rows extracted from these screenshots.</p>
        )}
        <div className="space-y-3">
          {playerStats.map((row, index) => (
            <div key={index} className="rounded-md border border-border p-3 dark:border-darkborder">
              <div className="flex flex-wrap items-center gap-2">
                <input
                  type="text"
                  value={row.displayName || ""}
                  onChange={(e) => updateRow(index, { displayName: e.target.value })}
                  className="w-40 rounded-md border border-border bg-white px-2 py-1.5 text-sm font-semibold text-textPrimary dark:border-darkborder dark:bg-darksurface dark:text-white"
                />
                <span
                  className={clsx(
                    "rounded-full px-2 py-1 text-xs uppercase",
                    row.team === homeCollege.name ? "bg-charcoal/5 dark:bg-white/10" : "bg-charcoal/10 dark:bg-white/20",
                  )}
                >
                  {row.team}
                </span>
                <span className="rounded-full bg-burnt/10 px-2 py-1 text-xs uppercase text-burnt">{row.category}</span>
                <select
                  value={row.studentSeasonId || ""}
                  onChange={(e) => updateRow(index, { studentSeasonId: e.target.value ? Number(e.target.value) : null })}
                  className="rounded-md border border-border bg-white px-2 py-1.5 text-xs dark:border-darkborder dark:bg-darksurface"
                >
                  <option value="">New player (will be created)</option>
                  {rosterFor(row.team).map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name} ({p.position})
                    </option>
                  ))}
                </select>
                <button type="button" onClick={() => removeRow(index)} className="ml-auto text-xs text-danger hover:underline">
                  Remove
                </button>
              </div>
              {!row.studentSeasonId && (
                <div className="mt-2 flex flex-wrap items-center gap-2 rounded-md bg-burnt/5 p-2 text-xs">
                  <span className="text-textSecondary">Not on the roster yet — will be created as:</span>
                  <select
                    value={row.position || ""}
                    onChange={(e) => updateRow(index, { position: e.target.value })}
                    className="rounded-md border border-border bg-white px-2 py-1 text-xs dark:border-darkborder dark:bg-darksurface"
                  >
                    {POSITIONS.map((position) => (
                      <option key={position} value={position}>
                        {position}
                      </option>
                    ))}
                  </select>
                  <select
                    value={row.classYear || ""}
                    onChange={(e) => updateRow(index, { classYear: e.target.value })}
                    className="rounded-md border border-border bg-white px-2 py-1 text-xs dark:border-darkborder dark:bg-darksurface"
                  >
                    {CLASS_YEARS.map((classYear) => (
                      <option key={classYear} value={classYear}>
                        {classYear}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-5">
                {(CATEGORY_FIELDS[row.category] || []).map((field) => (
                  <NumberField
                    key={field}
                    label={PLAYER_FIELD_LABELS[field]}
                    value={row.fields?.[field]}
                    onChange={(value) => updateField(index, field, value)}
                  />
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </Card>
  );
}

function GameUpdatePage() {
  const { gameId } = useParams();
  const authed = Boolean(localStorage.getItem("jwt"));

  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [buckets, setBuckets] = useState({ boxScore: [], home: [], away: [] });
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [analysis, setAnalysis] = useState(null);
  const [narrativeRunning, setNarrativeRunning] = useState(false);
  const [narrativeError, setNarrativeError] = useState(null);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const data = await fetchGame(gameId);
        setGame(data);
        if (authed && data.existingAnalysis) {
          setAnalysis({
            ...data.existingAnalysis,
            collegeStats: normalizeCollegeStats(data.existingAnalysis.collegeStats, data.awayCollege, data.homeCollege),
            screenshotSignedIds: [],
          });
        }
      } catch (err) {
        setLoadError(err.message);
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [gameId, authed]);

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeGameStats(gameId, buckets);
      setAnalysis((prev) =>
        prev
          ? mergeAnalysis(prev, result, game.awayCollege, game.homeCollege)
          : {
              ...result,
              narrative: EMPTY_NARRATIVE,
              collegeStats: normalizeCollegeStats(result.collegeStats, game.awayCollege, game.homeCollege),
              playerStats: withUnmatchedDefaults(result.playerStats),
            },
      );
    } catch (err) {
      setAnalyzeError(err.message);
    } finally {
      setAnalyzing(false);
    }
  };

  const handleRunNarrative = async () => {
    setNarrativeRunning(true);
    setNarrativeError(null);
    try {
      const result = await analyzeGameNarrative(gameId, {
        collegeStats: analysis.collegeStats,
        playerStats: analysis.playerStats,
      });
      setAnalysis((prev) => ({ ...prev, narrative: result.narrative }));
    } catch (err) {
      setNarrativeError(err.message);
    } finally {
      setNarrativeRunning(false);
    }
  };

  const handleCommit = async () => {
    setCommitting(true);
    setCommitError(null);
    try {
      await commitGameStats(gameId, analysis);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  if (loading) {
    return (
      <div className="max-w-5xl mx-auto px-4">
        <p className="text-sm text-textSecondary">Loading game...</p>
      </div>
    );
  }

  if (loadError || !game) {
    return (
      <div className="max-w-5xl mx-auto px-4">
        <p className="text-sm text-danger">{loadError || "Game not found."}</p>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto px-4 space-y-6">
      <PageHeader
        title={`${game.awayCollege.name} @ ${game.homeCollege.name}`}
        eyebrow={`Week ${game.week.number}`}
        actions={
          <Link
            to="/dynasty"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dashboard
          </Link>
        }
      />

      {!authed ? (
        <GameSummary game={game} />
      ) : saved ? (
        <Card>
          <div className="p-5 space-y-2">
            <p className="text-sm font-semibold text-success">
              Saved! Stats and screenshots have been recorded for this game.
            </p>
            <Link to="/dynasty" className="text-sm text-burnt hover:underline">
              Back to Dashboard
            </Link>
          </div>
        </Card>
      ) : (
        <>
          <UploadStep
            buckets={buckets}
            onBucketsChange={setBuckets}
            onAnalyze={handleAnalyze}
            analyzing={analyzing}
            error={analyzeError}
            homeCollege={game.homeCollege}
            awayCollege={game.awayCollege}
            addingMore={Boolean(analysis)}
          />

          {analysis && (
            <>
              {game.played && (
                <p className="text-sm text-textSecondary">
                  This game already has recorded stats — edit the fields below and save to update them.
                </p>
              )}
              <ExistingScreenshotsGallery screenshots={game.statScreenshots} />
              <ReferencePhotos buckets={buckets} homeCollege={game.homeCollege} awayCollege={game.awayCollege} />
              <NarrativeSection
                narrative={analysis.narrative}
                onChange={(narrative) => setAnalysis({ ...analysis, narrative })}
                roster={[...analysis.homeRoster, ...analysis.awayRoster]}
                onRunAnalysis={handleRunNarrative}
                running={narrativeRunning}
                error={narrativeError}
              />
              <TeamStatsSection
                collegeStats={analysis.collegeStats}
                onChange={(collegeStats) => setAnalysis({ ...analysis, collegeStats })}
                awayCollege={game.awayCollege}
                homeCollege={game.homeCollege}
              />
              <PlayerStatsSection
                playerStats={analysis.playerStats}
                onChange={(playerStats) => setAnalysis({ ...analysis, playerStats })}
                awayRoster={analysis.awayRoster}
                homeRoster={analysis.homeRoster}
                homeCollege={game.homeCollege}
              />

              {commitError && <p className="text-sm text-danger">{commitError}</p>}

              <div className="flex gap-2 pb-8">
                <button
                  type="button"
                  onClick={handleCommit}
                  disabled={committing}
                  className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  {committing ? "Saving..." : "Save Game Stats"}
                </button>
                <button
                  type="button"
                  onClick={() => setAnalysis(null)}
                  className="rounded-md border border-border px-4 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Clear Review
                </button>
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}

export default GameUpdatePage;
