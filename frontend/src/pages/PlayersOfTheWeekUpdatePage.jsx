import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchSeason, analyzePlayersOfTheWeek, commitPlayersOfTheWeek } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const weekLabel = (week) => {
  if (week.name) return week.name;
  if (week.conferenceChampionship) return "Conference Championship";
  if (week.postSeason) return `Post Season (Week ${week.number})`;
  return `Week ${week.number}`;
};

const SIDE_LABEL = { offensive: "Offense", defensive: "Defense" };

function FileDropZone({ files, onFilesChange }) {
  const handleFileInput = (e) => {
    onFilesChange([...files, ...Array.from(e.target.files || [])]);
    e.target.value = "";
  };

  const removeFile = (index) => onFilesChange(files.filter((_, i) => i !== index));

  return (
    <div className="space-y-2 rounded-md border border-border p-3 dark:border-darkborder">
      <div>
        <p className="text-sm font-semibold text-textPrimary dark:text-white">Player of the Week Screenshots</p>
        <p className="text-xs text-textSecondary">
          Upload the National and/or Conference screenshots together — each one&rsquo;s week and scope are
          detected automatically from its header.
        </p>
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

function WeekSelect({ value, onChange, weeks }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} className={`${inputClass} max-w-xs`}>
      <option value="">— pick week —</option>
      {weeks.map((week) => (
        <option key={week.id} value={week.id}>
          {weekLabel(week)}
        </option>
      ))}
    </select>
  );
}

function PlayerRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 text-sm font-semibold text-textPrimary dark:text-white">{SIDE_LABEL[row.side] || row.side}</td>
      <td className="p-2">
        <input type="text" value={row.firstName || ""} onChange={(e) => update({ firstName: e.target.value })} className={inputClass} />
      </td>
      <td className="p-2">
        <input type="text" value={row.lastName || ""} onChange={(e) => update({ lastName: e.target.value })} className={inputClass} />
      </td>
      <td className="p-2">
        <input
          type="text"
          value={row.position || ""}
          onChange={(e) => update({ position: e.target.value })}
          className={`${inputClass} w-16`}
        />
      </td>
      <td className="p-2">
        <CollegeSelect value={row.collegeId} onChange={(collegeId) => update({ collegeId })} colleges={colleges} />
        {row.opponentContext && (
          <p className={`mt-1 text-xs ${row.collegeId ? "text-textSecondary" : "text-danger"}`}>
            {row.opponentContext}
            {!row.collegeId ? " — couldn't auto-match, pick the college manually" : ""}
          </p>
        )}
      </td>
      <td className="p-2">
        <input type="text" value={row.statLine || ""} onChange={(e) => update({ statLine: e.target.value })} className={inputClass} />
      </td>
    </tr>
  );
}

function GroupCard({ group, colleges, weeks, onChange }) {
  const updateGroup = (patch) => onChange({ ...group, ...patch });
  const updateRow = (index, nextRow) => {
    const rows = group.rows.map((row, i) => (i === index ? nextRow : row));
    updateGroup({ rows });
  };

  const title = group.national ? "National" : group.conference || "Conference";

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
          {title} Player of the Week
        </h3>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-xs uppercase tracking-wide text-textSecondary">Week</span>
          <WeekSelect value={group.weekId} onChange={(weekId) => updateGroup({ weekId })} weeks={weeks} />
          {!group.weekId && (
            <p className="text-xs text-danger">
              {group.weekLabel ? `Couldn't match "${group.weekLabel}" to a week` : "Couldn't read the week"} — pick it manually.
            </p>
          )}
        </label>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Side</th>
                <th className="p-2">First</th>
                <th className="p-2">Last</th>
                <th className="p-2">Pos</th>
                <th className="p-2">College</th>
                <th className="p-2">Stat Line</th>
              </tr>
            </thead>
            <tbody>
              {group.rows.map((row, index) => (
                <PlayerRow key={index} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </Card>
  );
}

function PlayersOfTheWeekUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [weeks, setWeeks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [groups, setGroups] = useState(null);
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
      const result = await analyzePlayersOfTheWeek(dynastyId, seasonId, files);
      setGroups(result.groups);
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
      const result = await commitPlayersOfTheWeek(dynastyId, seasonId, groups);
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  const updateGroup = (index, nextGroup) => setGroups(groups.map((group, i) => (i === index ? nextGroup : group)));

  if (loading) {
    return (
      <div className="max-w-5xl mx-auto px-4">
        <p className="text-sm text-textSecondary">Loading...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="max-w-5xl mx-auto px-4">
        <p className="text-sm text-danger">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Add Players of the Week"
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
            <p className="text-sm font-semibold text-success">Saved! Players of the Week have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} player{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.player}: {warning.error}
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
      ) : !groups ? (
        <Card>
          <div className="p-5 space-y-4">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Upload Screenshots</h3>
            <p className="text-sm text-textSecondary">
              Upload the National and/or Conference screenshot(s) — the week is read from the badge in the
              top-right corner, and the player&rsquo;s college is guessed from the opponent and score shown,
              when that game is already saved. You can fix either one below if it&rsquo;s not detected.
            </p>

            <FileDropZone files={files} onFilesChange={setFiles} />

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
        <div className="space-y-4">
          {groups.map((group, index) => (
            <GroupCard key={index} group={group} colleges={colleges} weeks={weeks} onChange={(next) => updateGroup(index, next)} />
          ))}

          <Card>
            <div className="p-5 space-y-3">
              {commitError && <p className="text-sm text-danger">{commitError}</p>}
              <button
                type="button"
                onClick={handleCommit}
                disabled={committing}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {committing ? "Saving..." : "Save Players of the Week"}
              </button>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}

export default PlayersOfTheWeekUpdatePage;
