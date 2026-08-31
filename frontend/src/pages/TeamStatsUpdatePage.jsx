import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, analyzeTeamStats, commitTeamStats } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

const OFFENSE_FIELDS = [
  { key: "pointsScored", label: "PTS" },
  { key: "totalOffensiveYards", label: "Total Yds" },
  { key: "yardsPerPlay", label: "YPP" },
  { key: "passingYards", label: "Pass Yds" },
  { key: "passingTouchdowns", label: "Pass TD" },
  { key: "rushingYards", label: "Rush Yds" },
  { key: "rushingTouchdowns", label: "Rush TD" },
  { key: "firstDowns", label: "1st Downs" },
];

const DEFENSE_FIELDS = [
  { key: "pointsAllowed", label: "PTS Allowed" },
  { key: "totalYardsAllowed", label: "Total Yds Allowed" },
  { key: "passingYardsAllowed", label: "Pass Yds Allowed" },
  { key: "rushingYardsAllowed", label: "Rush Yds Allowed" },
  { key: "defensiveSacks", label: "Sacks" },
  { key: "fumbleRecoveries", label: "Fum Rec" },
  { key: "defensiveInterceptions", label: "INT" },
];

function CollegeSelect({ value, onChange, colleges }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} className={inputClass}>
      <option value="">— none —</option>
      {colleges.map((college) => (
        <option key={college.id} value={college.id}>
          {college.name}
        </option>
      ))}
    </select>
  );
}

function NumberInput({ value, onChange }) {
  return (
    <input
      type="number"
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
      className={smallInputClass}
    />
  );
}

function TeamStatsRow({ row, colleges, fields, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <CollegeSelect value={row.collegeId} onChange={(collegeId) => update({ collegeId })} colleges={colleges} />
        {row.collegeRawName && !row.collegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.collegeRawName}&rdquo;</p>}
      </td>
      {fields.map((field) => (
        <td key={field.key} className="p-2">
          <NumberInput value={row[field.key]} onChange={(value) => update({ [field.key]: value })} />
        </td>
      ))}
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function TeamStatsReview({ rows, colleges, fields, onChange, onCommit, committing, error }) {
  const updateRow = (index, nextRow) => {
    const next = nextRow === null ? rows.filter((_, i) => i !== index) : rows.map((row, i) => (i === index ? nextRow : row));
    onChange(next);
  };

  return (
    <div className="space-y-4">
      <div className="overflow-x-auto">
        <table className="w-full min-w-[900px] border-collapse text-left">
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="p-2">Team</th>
              {fields.map((field) => (
                <th key={field.key} className="p-2">
                  {field.label}
                </th>
              ))}
              <th className="p-2"></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <TeamStatsRow key={index} row={row} colleges={colleges} fields={fields} onChange={(next) => updateRow(index, next)} />
            ))}
          </tbody>
        </table>
      </div>

      {error && <p className="text-sm text-danger">{error}</p>}

      <button
        type="button"
        onClick={onCommit}
        disabled={committing}
        className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {committing ? "Saving..." : "Save"}
      </button>
    </div>
  );
}

function TeamStatsSection({ title, hint, statType, fields, dynastyId, seasonId }) {
  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [rows, setRows] = useState(null);
  const [colleges, setColleges] = useState([]);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [warnings, setWarnings] = useState([]);

  const reset = () => {
    setFiles([]);
    setRows(null);
    setColleges([]);
    setSaved(false);
    setWarnings([]);
    setAnalyzeError(null);
    setCommitError(null);
  };

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeTeamStats(dynastyId, seasonId, files, statType);
      setRows(result.rows);
      setColleges(result.colleges);
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
      const result = await commitTeamStats(dynastyId, seasonId, rows, statType);
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h3>

        {saved ? (
          <div className="space-y-2">
            <p className="text-sm font-semibold text-success">Saved! {title} stats have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} team{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.team}: {warning.error}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <button type="button" onClick={reset} className="text-sm text-burnt hover:underline">
              Upload another {title.toLowerCase()} screenshot
            </button>
          </div>
        ) : !rows ? (
          <div className="space-y-4">
            <p className="text-sm text-textSecondary">{hint}</p>

            <FileDropZone
              title={`${title} Screenshots`}
              hint="Upload as many screenshots as it takes to cover the whole conference."
              files={files}
              onFilesChange={setFiles}
            />

            {analyzeError && <p className="text-sm text-danger">{analyzeError}</p>}

            <button
              type="button"
              onClick={handleAnalyze}
              disabled={files.length === 0 || analyzing}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {analyzing ? "Analyzing... this can take a minute" : `Analyze ${files.length || ""} Photo${files.length === 1 ? "" : "s"}`}
            </button>
          </div>
        ) : (
          <TeamStatsReview
            rows={rows}
            colleges={colleges}
            fields={fields}
            onChange={setRows}
            onCommit={handleCommit}
            committing={committing}
            error={commitError}
          />
        )}
      </div>
    </Card>
  );
}

function TeamStatsUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setLoadError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setLoadError("This dynasty doesn't have a season yet.");
          return;
        }
        setDynastyId(dynasty.id);
        setSeasonId(latestSeason.id);
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
  }, [navigate]);

  if (loading) {
    return (
      <div className="max-w-6xl mx-auto px-4">
        <p className="text-sm text-textSecondary">Loading...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="max-w-6xl mx-auto px-4">
        <p className="text-sm text-danger">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Update Team Stats"
        eyebrow="Dynasty Updates"
        actions={
          <Link
            to="/dynasty/updates"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Updates
          </Link>
        }
      />

      <p className="text-sm text-textSecondary">
        Upload the league-wide offense and defense stats screenshots for your current season. Each applies
        independently, so you can update one without the other.
      </p>

      <div className="space-y-6">
        <TeamStatsSection
          title="Offense"
          hint="Upload the team offense stats screenshot(s). The AI reads every team's points scored, total offensive yards, and passing/rushing splits."
          statType="offense"
          fields={OFFENSE_FIELDS}
          dynastyId={dynastyId}
          seasonId={seasonId}
        />
        <TeamStatsSection
          title="Defense"
          hint="Upload the team defense stats screenshot(s). The AI reads every team's points/yards allowed and sacks/fumbles/interceptions forced."
          statType="defense"
          fields={DEFENSE_FIELDS}
          dynastyId={dynastyId}
          seasonId={seasonId}
        />
      </div>
    </div>
  );
}

export default TeamStatsUpdatePage;
