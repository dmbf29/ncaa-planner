import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import GameSummary from "../components/GameSummary";
import ScreenshotLightbox from "../components/ScreenshotLightbox";
import { analyzeGameNarrative, analyzeGameStats, reanalyzeGameStats, commitGameStats, fetchGame, API_BASE_URL } from "../lib/apiClient";
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

const EMPTY_PENDING_FILES = { boxScore: [], home: [], away: [] };
const EMPTY_SECTION_STATUS = { boxScore: {}, home: {}, away: {} };

const PLAYER_CATEGORY_ORDER = ["passing", "rushing", "receiving", "defense"];
const PLAYER_CATEGORY_LABELS = { passing: "Passing", rushing: "Rushing", receiving: "Receiving", defense: "Defense" };

// Roster dropdowns list players by last name, since that's how a coach
// scans for a name mid-review — "Bullard" not "Latrell".
const lastNameOf = (name) => (name || "").trim().split(/\s+/).pop() || "";
const sortRosterByLastName = (roster) => [...roster].sort((a, b) => lastNameOf(a.name).localeCompare(lastNameOf(b.name)));

const inputClass =
  "w-full rounded-md bg-white pe-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

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

// A screenshot re-analyzed to catch a player the first pass missed (or
// just re-uploaded by habit) re-extracts everyone else in it too, and the
// AI re-matches them against the roster independently each time — so the
// same real player comes back with the same studentSeasonId in both
// passes. Merge fresh values onto their existing row instead of appending
// a duplicate. Unmatched rows (no studentSeasonId) always get appended:
// there's no reliable way to tell a re-scan of the same unrecognized
// player from an actually-different one.
const mergePlayerStats = (existingRows, freshRows) => {
  const merged = [...existingRows];
  freshRows.forEach((freshRow) => {
    const matchIndex = freshRow.studentSeasonId
      ? merged.findIndex(
          (row) =>
            row.studentSeasonId === freshRow.studentSeasonId && row.team === freshRow.team && row.category === freshRow.category,
        )
      : -1;
    if (matchIndex === -1) {
      merged.push(freshRow);
      return;
    }
    const mergedFields = { ...merged[matchIndex].fields };
    Object.entries(freshRow.fields || {}).forEach(([key, value]) => {
      if (value != null) mergedFields[key] = value;
    });
    merged[matchIndex] = { ...merged[matchIndex], fields: mergedFields };
  });
  return merged;
};

// Each of Box Score / Home / Away is analyzed independently (its own
// request, its own loading state) so one section processing doesn't block
// another. Every merge below uses the functional setState form, so two
// analyze calls that resolve out of order (e.g. Away finishes before Home)
// both land correctly regardless of which one completes first.
const mergeAnalysis = (existing, fresh, awayCollege, homeCollege) => ({
  ...existing,
  boxScoreScreenshotSignedIds: [...(existing.boxScoreScreenshotSignedIds || []), ...(fresh.boxScoreScreenshotSignedIds || [])],
  homeScreenshotSignedIds: [...(existing.homeScreenshotSignedIds || []), ...(fresh.homeScreenshotSignedIds || [])],
  awayScreenshotSignedIds: [...(existing.awayScreenshotSignedIds || []), ...(fresh.awayScreenshotSignedIds || [])],
  collegeStats: mergeCollegeStats(existing.collegeStats, normalizeCollegeStats(fresh.collegeStats, awayCollege, homeCollege)),
  playerStats: mergePlayerStats(existing.playerStats, withUnmatchedDefaults(fresh.playerStats || [])),
  homeRoster: existing.homeRoster?.length ? existing.homeRoster : fresh.homeRoster,
  awayRoster: existing.awayRoster?.length ? existing.awayRoster : fresh.awayRoster,
});

// Blank fields are otherwise invisible in this borderless layout — a gap
// the AI missed (e.g. a final score) looked identical to blank space, which
// is exactly how one slipped past review and into a narrative write-up.
// A visible outline on anything still empty makes gaps impossible to miss.
function NumberField({ label, value, onChange }) {
  const isMissing = value === null || value === undefined;
  return (
    <label className="flex flex-col gap-1 text-xs text-textSecondary text-nowrap truncate">
      <span>{label}</span>
      <input
        type="number"
        step="any"
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
        className={isMissing ? `${inputClass} border border-warning bg-warning/10` : inputClass}
      />
    </label>
  );
}

function AccordionSection({ title, subtitle, expanded, onToggle, children }) {
  return (
    <Card>
      <button type="button" onClick={onToggle} className="flex w-full items-center justify-between gap-3 px-5 py-4 text-left">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h3>
          {subtitle && <p className="mt-0.5 text-xs text-textSecondary">{subtitle}</p>}
        </div>
        <span className="shrink-0 text-sm text-textSecondary">{expanded ? "Collapse" : "Expand"}</span>
      </button>
      {expanded && <div className="space-y-2 border-t border-border px-5 py-4 dark:border-darkborder">{children}</div>}
    </Card>
  );
}

// Small thumbnail strip + scoped upload/analyze control for one bucket
// (box score, home stats, or away stats). Existing (already-saved)
// screenshots and newly-staged local files render side by side — only the
// local ones can be removed before they're analyzed. Clicking any
// thumbnail opens the shared lightbox.
function ScreenshotUploadRow({
  hint,
  existingScreenshots,
  pendingFiles,
  onPendingFilesChange,
  onAnalyze,
  analyzing,
  error,
  onOpenLightbox,
  onReanalyze,
}) {
  const handleFileInput = (e) => {
    onPendingFilesChange([...pendingFiles, ...Array.from(e.target.files || [])]);
    e.target.value = "";
  };

  const handlePaste = (e) => {
    const imageFiles = Array.from(e.clipboardData?.items || [])
      .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter(Boolean);
    if (imageFiles.length === 0) return;
    e.preventDefault();
    onPendingFilesChange([...pendingFiles, ...imageFiles]);
  };

  const removePending = (index) => onPendingFilesChange(pendingFiles.filter((_, i) => i !== index));

  const combined = [
    ...existingScreenshots.map((s) => ({ src: `${API_BASE_URL}${s.url}`, alt: s.filename, pending: false })),
    ...pendingFiles.map((f, i) => ({ src: URL.createObjectURL(f), alt: f.name, pending: true, pendingIndex: i })),
  ];

  return (
    <div
      className="space-y-3 rounded-md border border-border p-3 focus:outline-none focus-visible:ring-2 focus-visible:ring-burnt dark:border-darkborder"
      tabIndex={0}
      onPaste={handlePaste}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-textSecondary">Screenshots</p>
          {hint && <p className="text-xs text-textSecondary">{hint}</p>}
          <p className="text-xs text-textSecondary">Click here, then paste (⌘V / Ctrl+V) a copied screenshot.</p>
        </div>
        <input
          type="file"
          accept="image/*"
          multiple
          onChange={handleFileInput}
          className="block text-xs text-textSecondary file:mr-2 file:rounded-md file:border-0 file:bg-burnt file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
        />
      </div>

      {combined.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {combined.map((img, i) => (
            <div key={i} className="relative">
              <button
                type="button"
                onClick={() => onOpenLightbox(combined, i)}
                className="h-12 w-12 overflow-hidden rounded-md border border-border dark:border-darkborder"
              >
                <img src={img.src} alt={img.alt} className="h-full w-full object-cover" />
              </button>
              {img.pending && (
                <button
                  type="button"
                  onClick={() => removePending(img.pendingIndex)}
                  className="absolute -right-1 -top-1 flex h-4 w-4 items-center justify-center rounded-full bg-danger text-[10px] text-white"
                >
                  ✕
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {error && <p className="text-sm text-danger">{error}</p>}

      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={onAnalyze}
          disabled={pendingFiles.length === 0 || analyzing}
          className="rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {analyzing ? "Analyzing..." : `Analyze ${pendingFiles.length || ""} Photo${pendingFiles.length === 1 ? "" : "s"}`}
        </button>
        {existingScreenshots.length > 0 && (
          <button
            type="button"
            onClick={onReanalyze}
            disabled={analyzing}
            title="Re-run AI extraction on the screenshots already uploaded above, without re-selecting files"
            className="rounded-md border border-burnt px-3 py-1.5 text-xs font-semibold text-burnt transition hover:bg-burnt/10 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {analyzing ? "Analyzing..." : "Re-analyze Existing"}
          </button>
        )}
      </div>
    </div>
  );
}

function NarrativeBody({ narrative, onChange, roster, onRunAnalysis, running, error }) {
  const update = (key, value) => onChange({ ...narrative, [key]: value });
  const hasContent = Boolean(narrative.narrativeSummary || narrative.offensePlayerOfGameId || narrative.defensePlayerOfGameId);

  return (
    <>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-textSecondary">
          Optional AI pass that writes a narrative summary and picks offense/defense players of the game from the
          stats below. Skip it for games you don&rsquo;t need a recap for.
        </p>
        <button
          type="button"
          onClick={onRunAnalysis}
          disabled={running}
          className="rounded-md border border-burnt px-3 py-1.5 text-xs font-semibold text-burnt transition hover:bg-burnt/10 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {running ? "Running..." : hasContent ? "Re-run Game Analysis" : "Run Game Analysis"}
        </button>
      </div>
      {error && <p className="text-sm text-danger">{error}</p>}
      <label className="flex flex-col gap-1 text-sm border p-3 rounded">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Narrative Summary</span>
        <textarea
          rows={7}
          value={narrative.narrativeSummary || ""}
          onChange={(e) => update("narrativeSummary", e.target.value)}
          className={inputClass}
        />
      </label>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-2 border p-3 rounded">
          <p className="text-xs uppercase tracking-wide text-textSecondary">Offense Player of the Game</p>
          <select
            value={narrative.offensePlayerOfGameId || ""}
            onChange={(e) => update("offensePlayerOfGameId", e.target.value ? Number(e.target.value) : null)}
            className={inputClass}
          >
            <option value="">— none —</option>
            {sortRosterByLastName(roster).map((p) => (
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
        <div className="space-y-2 border p-3 rounded">
          <p className="text-xs uppercase tracking-wide text-textSecondary">Defense Player of the Game</p>
          <select
            value={narrative.defensePlayerOfGameId || ""}
            onChange={(e) => update("defensePlayerOfGameId", e.target.value ? Number(e.target.value) : null)}
            className={inputClass}
          >
            <option value="">— none —</option>
            {sortRosterByLastName(roster).map((p) => (
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
    </>
  );
}

function TeamStatsBody({ collegeStats, onChange, awayCollege, homeCollege }) {
  const findEntry = (name) => collegeStats.find((row) => row.team === name);

  const updateField = (team, key, value) => {
    onChange(collegeStats.map((row) => (row.team === team ? { ...row, fields: { ...row.fields, [key]: value } } : row)));
  };

  return (
    <>
      <div className="grid gap-3 sm:grid-cols-2">
        {[awayCollege, homeCollege].map((college) => (
          <p key={college.id} className="text-sm font-semibold text-textPrimary dark:text-white">
            {college.name}
          </p>
        ))}
      </div>
      {TEAM_STAT_GROUPS.map((group) => (
        <div key={group.label} className="space-y-0">
          <p className="text-xs uppercase tracking-wide text-textSecondary">{group.label}</p>
          <div className="grid gap-3 sm:grid-cols-2">
            {[awayCollege, homeCollege].map((college) => {
              const entry = findEntry(college.name);
              return (
                <div key={college.id} className="grid grid-cols-2 gap-2 rounded-md p-3 dark:border-darkborder sm:grid-cols-6">
                  {group.fields.map((field) => (
                    <NumberField
                      key={field}
                      label={FIELD_LABELS[field]}
                      value={entry?.fields?.[field]}
                      onChange={(value) => updateField(college.name, field, value)}
                    />
                  ))}
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}

function PlayerStatRowEditor({ row, index, roster, updateRow, updateField, removeRow }) {
  return (
    <div className="rounded-md py-1 px-3 dark:border-darkborder">
      <div className="flex flex-wrap items-center gap-2">
        <input
          type="text"
          value={row.displayName || ""}
          onChange={(e) => updateRow(index, { displayName: e.target.value })}
          className="w-40 rounded-md border border-border bg-white px-2 py-1.5 text-xs font-semibold text-textPrimary dark:border-darkborder dark:bg-darksurface dark:text-white"
        />
        <select
          value={row.studentSeasonId || ""}
          onChange={(e) => updateRow(index, { studentSeasonId: e.target.value ? Number(e.target.value) : null })}
          className="rounded-md border border-border bg-white px-2 py-1.5 text-xs dark:border-darkborder dark:bg-darksurface"
        >
          <option value="">New player (will be created)</option>
          {sortRosterByLastName(roster).map((p) => (
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
      <div className="mt-1 grid grid-cols-3 gap-2 sm:grid-cols-9">
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
  );
}

// Renders one team's player rows out of the shared `playerStats` array,
// grouped into Passing/Rushing/Receiving/Defense. Row mutations still write
// back through the row's index in the full (unfiltered) array.
function TeamPlayerStatsBody({ team, playerStats, onChange, roster }) {
  const updateRow = (index, patch) => onChange(playerStats.map((row, i) => (i === index ? { ...row, ...patch } : row)));
  const updateField = (index, key, value) =>
    onChange(playerStats.map((row, i) => (i === index ? { ...row, fields: { ...row.fields, [key]: value } } : row)));
  const removeRow = (index) => onChange(playerStats.filter((_, i) => i !== index));
  const addRow = (category) =>
    onChange([
      ...playerStats,
      {
        team,
        category,
        displayName: "",
        studentSeasonId: null,
        position: DEFAULT_POSITION_BY_CATEGORY[category] || POSITIONS[0],
        classYear: "FR",
        fields: {},
      },
    ]);

  const teamRows = playerStats.map((row, index) => ({ row, index })).filter(({ row }) => row.team === team);

  return (
    <>
      {PLAYER_CATEGORY_ORDER.map((category) => {
        const categoryRows = teamRows.filter(({ row }) => row.category === category);

        return (
          <div key={category} className="space-y-2">
            <div className="flex items-center justify-between gap-2">
              <p className="text-xs uppercase tracking-wide text-burnt">{PLAYER_CATEGORY_LABELS[category]}</p>
              <button type="button" onClick={() => addRow(category)} className="text-xs font-semibold text-burnt hover:underline">
                + Add Player
              </button>
            </div>
            {categoryRows.length === 0 ? (
              <p className="text-sm text-textSecondary">No {PLAYER_CATEGORY_LABELS[category].toLowerCase()} rows yet.</p>
            ) : (
              <div className="space-y-0">
                {categoryRows.map(({ row, index }) => (
                  <PlayerStatRowEditor
                    key={index}
                    row={row}
                    index={index}
                    roster={roster}
                    updateRow={updateRow}
                    updateField={updateField}
                    removeRow={removeRow}
                  />
                ))}
              </div>
            )}
          </div>
        );
      })}
    </>
  );
}

function GameUpdatePage() {
  const { gameId } = useParams();
  const authed = Boolean(localStorage.getItem("jwt"));

  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [openSections, setOpenSections] = useState({ recap: true, boxScore: true, home: true, away: true });
  const toggleSection = (key) => setOpenSections((prev) => ({ ...prev, [key]: !prev[key] }));

  const [pendingFiles, setPendingFiles] = useState(EMPTY_PENDING_FILES);
  const [sectionStatus, setSectionStatus] = useState(EMPTY_SECTION_STATUS);

  const [lightbox, setLightbox] = useState(null);
  const openLightbox = (images, index) => setLightbox({ images, index });

  const [analysis, setAnalysis] = useState(null);
  const [narrativeRunning, setNarrativeRunning] = useState(false);
  const [narrativeError, setNarrativeError] = useState(null);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);

  // Any edit to the review data means the last save is now stale — used
  // instead of raw setAnalysis wherever the user (or a fresh AI pass)
  // changes something, so the "Saved" indicator only shows right after an
  // actual successful commit, not indefinitely after it.
  const updateAnalysis = (updater) => {
    setSaved(false);
    setAnalysis(updater);
  };

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
            boxScoreScreenshotSignedIds: [],
            homeScreenshotSignedIds: [],
            awayScreenshotSignedIds: [],
          });
          // This is exactly what's in the DB — nothing to save until the
          // user edits something, so the button shouldn't open in "unsaved" state.
          setSaved(true);
        }
      } catch (err) {
        setLoadError(err.message);
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [gameId, authed]);

  const handleAnalyzeSection = async (sectionKey) => {
    const files = pendingFiles[sectionKey];
    if (files.length === 0) return;

    setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: true, error: null } }));
    try {
      const buckets = { boxScore: [], home: [], away: [], [sectionKey]: files };
      const result = await analyzeGameStats(gameId, buckets);
      updateAnalysis((prev) =>
        prev
          ? mergeAnalysis(prev, result, game.awayCollege, game.homeCollege)
          : {
              ...result,
              narrative: EMPTY_NARRATIVE,
              collegeStats: normalizeCollegeStats(result.collegeStats, game.awayCollege, game.homeCollege),
              playerStats: withUnmatchedDefaults(result.playerStats),
            },
      );
      setPendingFiles((prev) => ({ ...prev, [sectionKey]: [] }));
      setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: false, error: null } }));
    } catch (err) {
      setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: false, error: err.message } }));
    }
  };

  // Re-runs extraction on screenshots already attached to the game — for
  // when the first pass missed a field and re-selecting the same files from
  // disk would just be busywork. The re-extracted signed ids are stripped
  // before merging since these screenshots are already attached; re-sending
  // them at commit would attach a second, duplicate copy.
  const handleReanalyzeSection = async (sectionKey) => {
    setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: true, error: null } }));
    try {
      const result = await reanalyzeGameStats(gameId, sectionKey);
      const freshStats = { ...result, boxScoreScreenshotSignedIds: [], homeScreenshotSignedIds: [], awayScreenshotSignedIds: [] };
      updateAnalysis((prev) =>
        prev
          ? mergeAnalysis(prev, freshStats, game.awayCollege, game.homeCollege)
          : {
              ...freshStats,
              narrative: EMPTY_NARRATIVE,
              collegeStats: normalizeCollegeStats(freshStats.collegeStats, game.awayCollege, game.homeCollege),
              playerStats: withUnmatchedDefaults(freshStats.playerStats),
            },
      );
      setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: false, error: null } }));
    } catch (err) {
      setSectionStatus((prev) => ({ ...prev, [sectionKey]: { analyzing: false, error: err.message } }));
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
      updateAnalysis((prev) => ({ ...prev, narrative: result.narrative }));
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
      const updated = await commitGameStats(gameId, analysis);
      setGame(updated);
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
      ) : (
        <>
          {game.played && (
            <p className="text-sm text-textSecondary">
              This game already has recorded stats — edit the fields below and save to update them.
            </p>
          )}

          <AccordionSection title="Game Recap" expanded={openSections.recap} onToggle={() => toggleSection("recap")}>
            {analysis ? (
              <NarrativeBody
                narrative={analysis.narrative}
                onChange={(narrative) => updateAnalysis({ ...analysis, narrative })}
                roster={[...analysis.homeRoster, ...analysis.awayRoster]}
                onRunAnalysis={handleRunNarrative}
                running={narrativeRunning}
                error={narrativeError}
              />
            ) : (
              <p className="text-sm text-textSecondary">
                Upload and analyze the box score or player stats below first, then come back here to write a recap.
              </p>
            )}
          </AccordionSection>

          <AccordionSection title="Box Score" expanded={openSections.boxScore} onToggle={() => toggleSection("boxScore")}>
            <ScreenshotUploadRow
              hint="1-2 shots covering both teams"
              existingScreenshots={game.boxScoreScreenshots}
              pendingFiles={pendingFiles.boxScore}
              onPendingFilesChange={(files) => setPendingFiles((prev) => ({ ...prev, boxScore: files }))}
              onAnalyze={() => handleAnalyzeSection("boxScore")}
              onReanalyze={() => handleReanalyzeSection("boxScore")}
              analyzing={Boolean(sectionStatus.boxScore.analyzing)}
              error={sectionStatus.boxScore.error}
              onOpenLightbox={openLightbox}
            />
            {analysis && (
              <TeamStatsBody
                collegeStats={analysis.collegeStats}
                onChange={(collegeStats) => updateAnalysis({ ...analysis, collegeStats })}
                awayCollege={game.awayCollege}
                homeCollege={game.homeCollege}
              />
            )}
          </AccordionSection>

          <AccordionSection
            title={`${game.homeCollege.name} Player Stats (Home)`}
            expanded={openSections.home}
            onToggle={() => toggleSection("home")}
          >
            <ScreenshotUploadRow
              hint="Passing/rushing/receiving/defense, up to 4 shots"
              existingScreenshots={game.homeScreenshots}
              pendingFiles={pendingFiles.home}
              onPendingFilesChange={(files) => setPendingFiles((prev) => ({ ...prev, home: files }))}
              onAnalyze={() => handleAnalyzeSection("home")}
              onReanalyze={() => handleReanalyzeSection("home")}
              analyzing={Boolean(sectionStatus.home.analyzing)}
              error={sectionStatus.home.error}
              onOpenLightbox={openLightbox}
            />
            {analysis && (
              <TeamPlayerStatsBody
                team={game.homeCollege.name}
                playerStats={analysis.playerStats}
                onChange={(playerStats) => updateAnalysis({ ...analysis, playerStats })}
                roster={analysis.homeRoster}
              />
            )}
          </AccordionSection>

          <AccordionSection
            title={`${game.awayCollege.name} Player Stats (Away)`}
            expanded={openSections.away}
            onToggle={() => toggleSection("away")}
          >
            <ScreenshotUploadRow
              hint="Passing/rushing/receiving/defense, up to 4 shots"
              existingScreenshots={game.awayScreenshots}
              pendingFiles={pendingFiles.away}
              onPendingFilesChange={(files) => setPendingFiles((prev) => ({ ...prev, away: files }))}
              onAnalyze={() => handleAnalyzeSection("away")}
              onReanalyze={() => handleReanalyzeSection("away")}
              analyzing={Boolean(sectionStatus.away.analyzing)}
              error={sectionStatus.away.error}
              onOpenLightbox={openLightbox}
            />
            {analysis && (
              <TeamPlayerStatsBody
                team={game.awayCollege.name}
                playerStats={analysis.playerStats}
                onChange={(playerStats) => updateAnalysis({ ...analysis, playerStats })}
                roster={analysis.awayRoster}
              />
            )}
          </AccordionSection>

          {analysis && <div className="h-20" aria-hidden="true" />}
        </>
      )}

      {authed && analysis && (
        <div className="sticky bottom-4 z-20">
          <Card className="shadow-lg">
            <div className="flex flex-wrap items-center gap-3 p-4">
              <button
                type="button"
                onClick={handleCommit}
                disabled={committing}
                className={
                  saved
                    ? "rounded-md border border-border bg-transparent px-4 py-2 text-sm font-semibold text-textSecondary transition hover:bg-border/20 disabled:cursor-not-allowed disabled:opacity-60 dark:border-darkborder dark:hover:bg-white/10"
                    : "rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
                }
              >
                {committing ? "Saving..." : saved ? "✓ Saved" : "Save Game Stats — unsaved changes"}
              </button>
              <button
                type="button"
                onClick={() => setAnalysis(null)}
                className="rounded-md border border-border px-4 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Clear Review
              </button>
              {commitError && <p className="w-full text-sm text-danger">{commitError}</p>}
            </div>
          </Card>
        </div>
      )}

      {lightbox && (
        <ScreenshotLightbox
          images={lightbox.images}
          index={lightbox.index}
          onIndexChange={(index) => setLightbox((prev) => ({ ...prev, index }))}
          onClose={() => setLightbox(null)}
        />
      )}
    </div>
  );
}

export default GameUpdatePage;
