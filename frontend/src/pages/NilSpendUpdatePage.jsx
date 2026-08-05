import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, analyzeNilSpend, commitNilSpend } from "../lib/apiClient";

const POSITIONS = [
  { key: "QB", label: "QB" },
  { key: "RB", label: "RB" },
  { key: "WR", label: "WR" },
  { key: "TE", label: "TE" },
  { key: "OL", label: "OL" },
  { key: "DL", label: "DL" },
  { key: "LB", label: "LB" },
  { key: "DB", label: "DB" },
  { key: "K/P", label: "K/P" },
];

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

function FileDropZone({ files, onFilesChange }) {
  const handleFileInput = (e) => {
    onFilesChange([...files, ...Array.from(e.target.files || [])]);
    e.target.value = "";
  };

  const removeFile = (index) => onFilesChange(files.filter((_, i) => i !== index));

  return (
    <div className="space-y-2 rounded-md border border-border p-3 dark:border-darkborder">
      <div>
        <p className="text-sm font-semibold text-textPrimary dark:text-white">NIL Spend Screenshots</p>
        <p className="text-xs text-textSecondary">Upload as many screenshots as it takes to cover the whole conference.</p>
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

function TeamRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  // Wire format is an array of {position, amount} rather than a {"QB": amount} object — a keyed object would
  // have its literal position labels (e.g. "QB") mangled by the camelCase/snake_case conversion apiClient
  // does on every request, since that conversion treats every object key as a JS-style identifier.
  const amountFor = (key) => row.byPosition?.find((entry) => entry.position === key)?.amount;
  const updatePosition = (key, amount) => {
    const existing = row.byPosition || [];
    const byPosition = existing.some((entry) => entry.position === key)
      ? existing.map((entry) => (entry.position === key ? { ...entry, amount } : entry))
      : [...existing, { position: key, amount }];
    onChange({ ...row, byPosition });
  };

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <CollegeSelect value={row.collegeId} onChange={(collegeId) => update({ collegeId })} colleges={colleges} />
        {row.collegeRawName && !row.collegeId && <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.collegeRawName}&rdquo;</p>}
      </td>
      <td className="p-2">
        <NumberInput value={row.nilTotal} onChange={(nilTotal) => update({ nilTotal })} />
      </td>
      {POSITIONS.map((position) => (
        <td key={position.key} className="p-2">
          <NumberInput value={amountFor(position.key)} onChange={(value) => updatePosition(position.key, value)} />
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

function NilSpendReview({ rows, colleges, onChange, onCommit, committing, error }) {
  const updateRow = (index, nextRow) => {
    const next = nextRow === null ? rows.filter((_, i) => i !== index) : rows.map((row, i) => (i === index ? nextRow : row));
    onChange(next);
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review NIL Spend</h3>
        <p className="text-sm text-textSecondary">Fix any unmatched colleges below, then save.</p>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[1100px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Team</th>
                <th className="p-2">NIL</th>
                {POSITIONS.map((position) => (
                  <th key={position.key} className="p-2">
                    {position.label}
                  </th>
                ))}
                <th className="p-2"></th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <TeamRow key={index} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
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
          {committing ? "Saving..." : "Save NIL Spend"}
        </button>
      </div>
    </Card>
  );
}

function NilSpendUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
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
      const result = await analyzeNilSpend(dynastyId, seasonId, files);
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
      const result = await commitNilSpend(dynastyId, seasonId, rows);
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
        title="Update NIL Spend"
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
            <p className="text-sm font-semibold text-success">Saved! NIL spend has been updated.</p>
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
              Upload the conference NIL spend screenshot(s). This applies to your current season — the AI reads
              every team&rsquo;s total and position breakdown and proposes the table below for you to review
              before anything is saved.
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
        <NilSpendReview
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

export default NilSpendUpdatePage;
