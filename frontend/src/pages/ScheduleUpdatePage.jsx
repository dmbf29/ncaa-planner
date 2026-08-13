import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, fetchSeason, analyzeSchedule, commitSchedule } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

const weekLabel = (week) => {
  if (week.name) return week.name;
  if (week.conferenceChampionship) return "Conference Championship";
  if (week.postSeason) return `Post Season (Week ${week.number})`;
  return `Week ${week.number}`;
};

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

function NumberInput({ value, onChange, className = smallInputClass }) {
  return (
    <input
      type="number"
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
      className={className}
    />
  );
}

function GameRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <CollegeSelect value={row.awayCollegeId} onChange={(awayCollegeId) => update({ awayCollegeId })} colleges={colleges} />
        {row.awayRawName && !row.awayCollegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.awayRawName}&rdquo;</p>}
      </td>
      <td className="p-2 text-center text-textSecondary">@</td>
      <td className="p-2">
        <CollegeSelect value={row.homeCollegeId} onChange={(homeCollegeId) => update({ homeCollegeId })} colleges={colleges} />
        {row.homeRawName && !row.homeCollegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.homeRawName}&rdquo;</p>}
      </td>
      <td className="p-2">
        <div className="flex items-center gap-1">
          <NumberInput value={row.month} onChange={(month) => update({ month })} />
          <span className="text-textSecondary">/</span>
          <NumberInput value={row.day} onChange={(day) => update({ day })} />
        </div>
      </td>
      <td className="p-2">
        <input
          type="text"
          placeholder="e.g. 4:00 PM"
          value={row.timeOfDay || ""}
          onChange={(e) => update({ timeOfDay: e.target.value || null })}
          className={`${inputClass} w-28`}
        />
      </td>
      <td className="p-2">
        <div className="flex items-center gap-1">
          <NumberInput value={row.awayScore} onChange={(awayScore) => update({ awayScore })} />
          <span className="text-textSecondary">-</span>
          <NumberInput value={row.homeScore} onChange={(homeScore) => update({ homeScore })} />
        </div>
      </td>
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function ScheduleReview({ weekNumber, weeks, selectedWeekId, onWeekChange, rows, colleges, onChange, onCommit, committing, error }) {
  const updateRow = (index, nextRow) => {
    if (nextRow === null) {
      onChange(rows.filter((_, i) => i !== index));
      return;
    }
    onChange(rows.map((row, i) => (i === index ? nextRow : row)));
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review Schedule</h3>
        <p className="text-sm text-textSecondary">
          Detected <strong>Week {weekNumber ?? "?"}</strong> from the screenshots — confirm it below, fix any unmatched
          colleges, then save.
        </p>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-xs uppercase tracking-wide text-textSecondary">Week</span>
          <select value={selectedWeekId} onChange={(e) => onWeekChange(Number(e.target.value))} className={`${inputClass} max-w-xs`}>
            {weeks.map((week) => (
              <option key={week.id} value={week.id}>
                {weekLabel(week)}
              </option>
            ))}
          </select>
        </label>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[800px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Away</th>
                <th className="p-2"></th>
                <th className="p-2">Home</th>
                <th className="p-2">Date (M/D)</th>
                <th className="p-2">Time</th>
                <th className="p-2">Score (A-H)</th>
                <th className="p-2"></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <GameRow key={index} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
              ))}
            </tbody>
          </table>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onCommit}
          disabled={committing || !selectedWeekId}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : "Save Schedule"}
        </button>
      </div>
    </Card>
  );
}

function ScheduleUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [weeks, setWeeks] = useState([]);
  const [lastPlayedWeekNumber, setLastPlayedWeekNumber] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [weekNumber, setWeekNumber] = useState(null);
  const [selectedWeekId, setSelectedWeekId] = useState("");
  const [rows, setRows] = useState(null);
  const [colleges, setColleges] = useState([]);
  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [warnings, setWarnings] = useState([]);

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
        const season = await fetchSeason(dynasty.id, latestSeason.id);
        setWeeks(season.teams?.[0]?.weeks || []);
        setLastPlayedWeekNumber(season.lastPlayedWeekNumber ?? null);
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

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeSchedule(dynastyId, seasonId, files);
      setWeekNumber(result.weekNumber);
      setRows(result.rows);
      setColleges(result.colleges);
      const matched = weeks.find((week) => week.number === result.weekNumber);
      const fallback = lastPlayedWeekNumber == null ? weeks[0] : weeks.find((week) => week.number === lastPlayedWeekNumber + 1);
      setSelectedWeekId(matched?.id || fallback?.id || "");
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
      const result = await commitSchedule(dynastyId, seasonId, selectedWeekId, rows);
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

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
        title="Add Games/Results"
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

      {saved ? (
        <Card>
          <div className="p-5 space-y-2">
            <p className="text-sm font-semibold text-success">Saved! Games and results have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} game{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.matchup}: {warning.error}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <Link to="/dynasty/updates" className="text-sm text-burnt hover:underline">
              Back to Dynasty Updates
            </Link>
          </div>
        </Card>
      ) : !rows ? (
        <Card>
          <div className="p-5 space-y-4">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Upload Screenshots</h3>
            <p className="text-sm text-textSecondary">
              {lastPlayedWeekNumber != null
                ? `Results are entered through Week ${lastPlayedWeekNumber}. `
                : "No results entered yet this season. "}
              Upload the weekly schedule screenshot(s). The week number is read directly from the screenshot — you&rsquo;ll
              get a chance to confirm it, along with every matchup, before anything is saved.
            </p>

            <FileDropZone
              title="Schedule Screenshots"
              hint="Upload as many screenshots as it takes to cover the whole week."
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
        </Card>
      ) : (
        <ScheduleReview
          weekNumber={weekNumber}
          weeks={weeks}
          selectedWeekId={selectedWeekId}
          onWeekChange={setSelectedWeekId}
          rows={rows}
          colleges={colleges}
          onChange={setRows}
          onCommit={handleCommit}
          committing={committing}
          error={commitError}
        />
      )}
    </div>
  );
}

export default ScheduleUpdatePage;
