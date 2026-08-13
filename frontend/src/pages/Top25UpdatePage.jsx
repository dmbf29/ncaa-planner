import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, fetchSeason, analyzeTop25Rankings, commitTop25Rankings } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-20`;

const weekLabel = (week) => {
  if (week.name) return week.name;
  if (week.conferenceChampionship) return "Conference Championship";
  if (week.postSeason) return `Post Season (Week ${week.number})`;
  return `Week ${week.number}`;
};

function CollegeSelect({ value, onChange, colleges, allowNone = true }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} className={inputClass}>
      {allowNone && <option value="">— none —</option>}
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

function RankingRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });
  const updateThisWeek = (patch) => onChange({ ...row, thisWeek: { ...row.thisWeek, ...patch } });
  const updateLastWeek = (patch) => onChange({ ...row, lastWeek: { ...row.lastWeek, ...patch } });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 text-sm font-semibold text-textPrimary dark:text-white">{row.rank}</td>
      <td className="p-2">
        <CollegeSelect value={row.collegeId} onChange={(collegeId) => update({ collegeId })} colleges={colleges} />
        {row.collegeName && !row.collegeId && (
          <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.collegeName}&rdquo;</p>
        )}
      </td>
      <td className="p-2">
        <NumberInput value={row.lwRanking} onChange={(lwRanking) => update({ lwRanking })} />
      </td>
      <td className="p-2">
        <div className="flex items-center gap-1">
          <NumberInput value={row.wins} onChange={(wins) => update({ wins })} />
          <span className="text-textSecondary">-</span>
          <NumberInput value={row.losses} onChange={(losses) => update({ losses })} />
        </div>
      </td>
      <td className="p-2">
        <div className="space-y-1">
          <CollegeSelect
            value={row.thisWeek?.opponentCollegeId}
            onChange={(opponentCollegeId) => updateThisWeek({ opponentCollegeId })}
            colleges={colleges}
          />
          {row.thisWeek?.opponentName && !row.thisWeek?.opponentCollegeId && (
            <p className="text-xs text-danger">Unmatched: &ldquo;{row.thisWeek.opponentName}&rdquo;</p>
          )}
          <label className="flex items-center gap-1 text-xs text-textSecondary">
            <input
              type="checkbox"
              checked={Boolean(row.thisWeek?.isAway)}
              onChange={(e) => updateThisWeek({ isAway: e.target.checked })}
            />
            Away game
          </label>
        </div>
      </td>
      <td className="p-2">
        <div className="space-y-1">
          <CollegeSelect
            value={row.lastWeek?.opponentCollegeId}
            onChange={(opponentCollegeId) => updateLastWeek({ opponentCollegeId })}
            colleges={colleges}
          />
          {row.lastWeek?.opponentName && !row.lastWeek?.opponentCollegeId && (
            <p className="text-xs text-danger">Unmatched: &ldquo;{row.lastWeek.opponentName}&rdquo;</p>
          )}
          <label className="flex items-center gap-1 text-xs text-textSecondary">
            <input
              type="checkbox"
              checked={Boolean(row.lastWeek?.isAway)}
              onChange={(e) => updateLastWeek({ isAway: e.target.checked })}
            />
            Away game
          </label>
          <select
            value={row.lastWeek?.result ?? ""}
            onChange={(e) => updateLastWeek({ result: e.target.value || null })}
            className={inputClass}
          >
            <option value="">— result —</option>
            <option value="win">Win</option>
            <option value="loss">Loss</option>
          </select>
          <div className="flex items-center gap-1">
            <NumberInput value={row.lastWeek?.teamScore} onChange={(teamScore) => updateLastWeek({ teamScore })} />
            <span className="text-textSecondary">-</span>
            <NumberInput value={row.lastWeek?.opponentScore} onChange={(opponentScore) => updateLastWeek({ opponentScore })} />
          </div>
        </div>
      </td>
    </tr>
  );
}

function RankingsReview({ rows, colleges, onChange, onCommit, committing, error }) {
  const updateRow = (index, nextRow) => onChange(rows.map((row, i) => (i === index ? nextRow : row)));

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review Rankings</h3>
        <p className="text-sm text-textSecondary">
          Fix any unmatched colleges below, then save. Leave a college dropdown on &ldquo;— none —&rdquo; to skip that row.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Rank</th>
                <th className="p-2">College</th>
                <th className="p-2">LW</th>
                <th className="p-2">W-L</th>
                <th className="p-2">This Week</th>
                <th className="p-2">Last Week</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <RankingRow key={row.rank} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
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
          {committing ? "Saving..." : "Save Rankings"}
        </button>
      </div>
    </Card>
  );
}

function Top25UpdatePage() {
  const navigate = useNavigate();

  const [weeks, setWeeks] = useState([]);
  const [selectedWeekId, setSelectedWeekId] = useState("");
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

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
        const season = await fetchSeason(dynasty.id, latestSeason.id);
        const seasonWeeks = season.teams?.[0]?.weeks || [];
        setWeeks(seasonWeeks);
        if (seasonWeeks.length > 0) setSelectedWeekId(seasonWeeks[0].id);
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
      const result = await analyzeTop25Rankings(selectedWeekId, files);
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
      const result = await commitTop25Rankings(selectedWeekId, rows);
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
        title="Update Top 25"
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
            <p className="text-sm font-semibold text-success">Saved! Rankings, records, and games have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} row{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning) => (
                    <li key={warning.rank}>
                      Rank {warning.rank}: {warning.error}
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
              Pick the week these rankings belong to (it isn&rsquo;t visible on screen), then upload the poll
              screenshots. The AI reads them and proposes the table below for you to review before anything is saved.
            </p>
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-xs uppercase tracking-wide text-textSecondary">Week</span>
              <select
                value={selectedWeekId}
                onChange={(e) => setSelectedWeekId(Number(e.target.value))}
                className={inputClass}
              >
                {weeks.map((week) => (
                  <option key={week.id} value={week.id}>
                    {weekLabel(week)}
                  </option>
                ))}
              </select>
            </label>

            <FileDropZone
              title="Top 25 Screenshots"
              hint="Upload as many screenshots as it takes to cover all 25 teams."
              files={files}
              onFilesChange={setFiles}
            />

            {analyzeError && <p className="text-sm text-danger">{analyzeError}</p>}

            <button
              type="button"
              onClick={handleAnalyze}
              disabled={files.length === 0 || !selectedWeekId || analyzing}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {analyzing ? "Analyzing... this can take a minute" : `Analyze ${files.length || ""} Photo${files.length === 1 ? "" : "s"}`}
            </button>
          </div>
        </Card>
      ) : (
        <RankingsReview
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

export default Top25UpdatePage;
