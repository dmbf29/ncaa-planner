import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { analyzeGameStats, commitGameStats, fetchGame } from "../lib/apiClient";

const TEAM_STAT_GROUPS = [
  { label: "Scoring", fields: ["finalScore", "pointsInQuarter1", "pointsInQuarter2", "pointsInQuarter3", "pointsInQuarter4"] },
  { label: "Offense", fields: ["firstDowns", "totalOffense", "totalPlays", "yardsPerPlay", "totalYards"] },
  { label: "Rushing", fields: ["rushes", "rushingYards", "rushingTds", "yardsPerRush"] },
  { label: "Passing", fields: ["passingCompletions", "passingAttempts", "passingTds", "passingYards", "yardsPerPass"] },
  {
    label: "Downs & 2-PT",
    fields: [
      "thirdDownConversions", "thirdDownAttempts", "fourthDownConversions", "fourthDownAttempts",
      "twoPointConversions", "twoPointAttempts",
    ],
  },
  { label: "Red Zone", fields: ["redZoneTds", "redZoneFieldGoals", "redZoneSuccessPercentage"] },
  { label: "Ball Security", fields: ["turnovers", "fumblesLost", "interceptionsThrown"] },
  { label: "Special Teams", fields: ["puntReturnYards", "kickReturnYards", "punts"] },
  { label: "Penalties & Time", fields: ["penalties", "penaltyYards", "timeOfPossession"] },
];

const FIELD_LABELS = {
  finalScore: "Final Score", pointsInQuarter1: "Q1", pointsInQuarter2: "Q2", pointsInQuarter3: "Q3", pointsInQuarter4: "Q4",
  firstDowns: "First Downs", totalOffense: "Total Offense", totalPlays: "Total Plays", yardsPerPlay: "Yards/Play",
  totalYards: "Total Yards", rushes: "Rushes", rushingYards: "Rush Yards", rushingTds: "Rush TDs",
  yardsPerRush: "Yards/Rush", passingCompletions: "Comp", passingAttempts: "Att", passingTds: "Pass TDs",
  passingYards: "Pass Yards", yardsPerPass: "Yards/Pass", thirdDownConversions: "3rd Down Made",
  thirdDownAttempts: "3rd Down Att", fourthDownConversions: "4th Down Made", fourthDownAttempts: "4th Down Att",
  twoPointConversions: "2-PT Made", twoPointAttempts: "2-PT Att", redZoneTds: "RZ TDs", redZoneFieldGoals: "RZ FGs",
  redZoneSuccessPercentage: "RZ %", turnovers: "Turnovers", fumblesLost: "Fumbles Lost",
  interceptionsThrown: "INTs Thrown", puntReturnYards: "PR Yards", kickReturnYards: "KR Yards", punts: "Punts",
  penalties: "Penalties", penaltyYards: "Penalty Yards", timeOfPossession: "TOP (sec)",
};

const CATEGORY_FIELDS = {
  passing: ["passingCompletions", "passingAttempts", "passingYards", "passingTds", "passingInterceptions", "passingRating", "passingLongest", "passingSacksTaken", "passingAvg"],
  rushing: ["rushingCarries", "rushingYards", "rushingAvg", "rushingTds", "rushingFumbles", "rushingYac", "rushingLongest"],
  receiving: ["receivingReceptions", "receivingYards", "receivingAvg", "receivingTds", "receivingRac", "receivingLongest", "receivingDrop"],
  defense: ["defenseSoloTackles", "defenseAssistTackles", "defenseTackles", "defenseTfl", "defenseSacks", "defenseInterceptions", "defenseInterceptionsLongest"],
};

const PLAYER_FIELD_LABELS = {
  passingRating: "Rating", passingCompletions: "Comp", passingAttempts: "Att", passingYards: "Yards",
  passingTds: "TD", passingInterceptions: "INT", passingLongest: "Long", passingSacksTaken: "Sacks Taken",
  passingAvg: "Comp %", rushingCarries: "Car", rushingYards: "Yards", rushingAvg: "Avg", rushingTds: "TD",
  rushingFumbles: "Fumb", rushingYac: "YAC", rushingLongest: "Long", receivingReceptions: "Rec",
  receivingYards: "Yards", receivingAvg: "Avg", receivingTds: "TD", receivingRac: "RAC", receivingLongest: "Long",
  receivingDrop: "Drops", defenseSoloTackles: "Solo", defenseAssistTackles: "Assist", defenseTackles: "Tak",
  defenseTfl: "TFL", defenseSacks: "Sack", defenseInterceptions: "INT", defenseInterceptionsLongest: "INT Long",
};

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const normalizeCollegeStats = (rows, awayCollege, homeCollege) => {
  const byTeam = Object.fromEntries((rows || []).map((row) => [row.team, row]));
  return [awayCollege, homeCollege].map((college) => byTeam[college.name] || { team: college.name, fields: {} });
};

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

function UploadStep({ buckets, onBucketsChange, onAnalyze, analyzing, error, homeCollege, awayCollege }) {
  const totalFiles = buckets.boxScore.length + buckets.home.length + buckets.away.length;

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
            Upload Screenshots
          </h3>
          <p className="mt-1 text-sm text-textSecondary">
            Upload the box score separately from each team&rsquo;s player stat screens (passing/rushing/receiving/
            defense). The AI reads them and proposes stats below for you to review before anything is saved.
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

function NarrativeSection({ narrative, onChange, roster }) {
  const update = (key, value) => onChange({ ...narrative, [key]: value });

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Game Recap</h3>
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
                  <option value="">Unmatched — won&rsquo;t be saved</option>
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
  const navigate = useNavigate();

  const [game, setGame] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [buckets, setBuckets] = useState({ boxScore: [], home: [], away: [] });
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [analysis, setAnalysis] = useState(null);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const data = await fetchGame(gameId);
        setGame(data);
      } catch (err) {
        setLoadError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [gameId, navigate]);

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeGameStats(gameId, buckets);
      setAnalysis({
        ...result,
        collegeStats: normalizeCollegeStats(result.collegeStats, game.awayCollege, game.homeCollege),
      });
    } catch (err) {
      setAnalyzeError(err.message);
    } finally {
      setAnalyzing(false);
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

      {saved ? (
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
      ) : !analysis ? (
        <UploadStep
          buckets={buckets}
          onBucketsChange={setBuckets}
          onAnalyze={handleAnalyze}
          analyzing={analyzing}
          error={analyzeError}
          homeCollege={game.homeCollege}
          awayCollege={game.awayCollege}
        />
      ) : (
        <>
          <ReferencePhotos buckets={buckets} homeCollege={game.homeCollege} awayCollege={game.awayCollege} />
          <NarrativeSection
            narrative={analysis.narrative}
            onChange={(narrative) => setAnalysis({ ...analysis, narrative })}
            roster={[...analysis.homeRoster, ...analysis.awayRoster]}
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
              Start Over
            </button>
          </div>
        </>
      )}
    </div>
  );
}

export default GameUpdatePage;
