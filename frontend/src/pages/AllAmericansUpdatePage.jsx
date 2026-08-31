import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, analyzeAllAmericans, commitAllAmericans } from "../lib/apiClient";

const CONFERENCES = [
  "AAC", "ACC", "Big 12", "Big Ten", "Conference USA", "Independent", "MAC", "Mountain West", "Pac 12", "SEC", "Sun Belt",
];

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

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

function PlayerRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
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
        {row.collegeRawName && !row.collegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.collegeRawName}&rdquo;</p>}
      </td>
      <td className="p-2">
        <input
          type="text"
          value={row.classYear || ""}
          onChange={(e) => update({ classYear: e.target.value })}
          className={`${inputClass} w-20`}
        />
      </td>
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function GroupCard({ group, colleges, onChange }) {
  const updateGroup = (patch) => onChange({ ...group, ...patch });
  const updateRow = (index, nextRow) => {
    const rows = nextRow === null ? group.rows.filter((_, i) => i !== index) : group.rows.map((row, i) => (i === index ? nextRow : row));
    updateGroup({ rows });
  };

  const title = group.national ? "National" : group.conference || "Conference";

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div className="flex flex-wrap items-end gap-3">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
            {title} — {group.tier === 1 ? "1st" : "2nd"} Team{group.preseason ? " (Preseason)" : ""}
          </h3>
        </div>
        <div className="flex flex-wrap items-center gap-3 text-sm">
          <label className="flex items-center gap-1">
            <input type="checkbox" checked={group.national} onChange={(e) => updateGroup({ national: e.target.checked, conference: e.target.checked ? null : group.conference })} />
            National
          </label>
          {!group.national && (
            <select value={group.conference || ""} onChange={(e) => updateGroup({ conference: e.target.value })} className={`${inputClass} max-w-[10rem]`}>
              <option value="">— conference —</option>
              {CONFERENCES.map((conference) => (
                <option key={conference} value={conference}>
                  {conference}
                </option>
              ))}
            </select>
          )}
          <select value={group.tier} onChange={(e) => updateGroup({ tier: Number(e.target.value) })} className={`${inputClass} max-w-[8rem]`}>
            <option value={1}>1st Team</option>
            <option value={2}>2nd Team</option>
          </select>
          <label className="flex items-center gap-1">
            <input type="checkbox" checked={group.preseason} onChange={(e) => updateGroup({ preseason: e.target.checked })} />
            Preseason
          </label>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full min-w-[700px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">First</th>
                <th className="p-2">Last</th>
                <th className="p-2">Pos</th>
                <th className="p-2">College</th>
                <th className="p-2">Year</th>
                <th className="p-2"></th>
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

function AllAmericansUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
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
      const result = await analyzeAllAmericans(dynastyId, seasonId, files);
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
      const result = await commitAllAmericans(dynastyId, seasonId, groups);
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
        title="Add All-Americans"
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
            <p className="text-sm font-semibold text-success">Saved! All-American honors have been updated.</p>
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
              Upload as many National/Conference, 1st/2nd Team screenshots as you have — preseason or end-of-season.
              The AI reads each list separately and proposes the tables below for you to review before anything is saved.
            </p>

            <FileDropZone
              title="All-American Screenshots"
              hint="Upload all of them together — National and Conference, 1st and 2nd team, however many you have. Each screenshot's list is detected automatically from its header."
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
        <>
          {groups.length === 0 && (
            <Card>
              <div className="p-5">
                <p className="text-sm text-textSecondary">No All-American lists were detected in these screenshots.</p>
              </div>
            </Card>
          )}
          {groups.map((group, index) => (
            <GroupCard key={index} group={group} colleges={colleges} onChange={(next) => updateGroup(index, next)} />
          ))}

          {commitError && <p className="text-sm text-danger">{commitError}</p>}

          {groups.length > 0 && (
            <div className="flex gap-2 pb-8">
              <button
                type="button"
                onClick={handleCommit}
                disabled={committing}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {committing ? "Saving..." : "Save All-Americans"}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}

export default AllAmericansUpdatePage;
