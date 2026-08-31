import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import {
  fetchDynasties,
  fetchSeason,
  analyzeRecruitmentTrail,
  commitRecruitmentTrail,
} from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

function weekLabel(week) {
  if (week.name) return week.name;
  return `Week ${week.number}`;
}

function CollegeSelect({ value, onChange, colleges }) {
  return (
    <select
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className={inputClass}
    >
      <option value="">— select —</option>
      {colleges.map((college) => (
        <option key={college.id} value={college.id}>
          {college.name}
        </option>
      ))}
    </select>
  );
}

function TextInput({ value, onChange, className = inputClass, placeholder }) {
  return (
    <input
      type="text"
      value={value ?? ""}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className={className}
    />
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

function RecruitRow({ row, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <TextInput
          value={row.firstName}
          onChange={(firstName) => update({ firstName })}
          className={`${inputClass} w-32`}
          placeholder={row.firstInitial ? `${row.firstInitial}.` : "First name"}
        />
        {!row.firstName && <p className="mt-1 text-xs text-warning">Fill in the full first name</p>}
      </td>
      <td className="p-2">
        <TextInput value={row.lastName} onChange={(lastName) => update({ lastName })} className={`${inputClass} w-36`} />
      </td>
      <td className="p-2">
        <TextInput value={row.position} onChange={(position) => update({ position })} className={`${inputClass} w-20`} />
      </td>
      <td className="p-2">
        <NumberInput value={row.starRating} onChange={(starRating) => update({ starRating })} />
      </td>
      <td className="p-2">
        <NumberInput value={row.nilAmount} onChange={(nilAmount) => update({ nilAmount })} />
      </td>
      <td className="p-2">
        <NumberInput value={row.nationalRank} onChange={(nationalRank) => update({ nationalRank })} />
      </td>
      <td className="p-2">
        <NumberInput value={row.positionRank} onChange={(positionRank) => update({ positionRank })} />
      </td>
      <td className="p-2">
        <NumberInput value={row.stateRank} onChange={(stateRank) => update({ stateRank })} />
      </td>
      <td className="p-2">
        <TextInput value={row.state} onChange={(state) => update({ state })} className={`${inputClass} w-16`} />
      </td>
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function RecruitmentTrailReview({
  collegeId,
  collegeRawName,
  colleges,
  onCollegeChange,
  weekName,
  rows,
  onChange,
  onBack,
  onCommit,
  committing,
  error,
}) {
  const updateRow = (index, nextRow) => {
    const next =
      nextRow === null ? rows.filter((_, i) => i !== index) : rows.map((row, i) => (i === index ? nextRow : row));
    onChange(next);
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
              Review Signed Recruits
            </h3>
            <p className="text-sm text-textSecondary">
              Confirm the team (read from the screenshot header — fix it if it&rsquo;s wrong), type each
              recruit&rsquo;s full first name, fix anything else the AI misread, then save.
            </p>
          </div>
          <button
            type="button"
            onClick={onBack}
            className="shrink-0 rounded-md border border-border px-3 py-1.5 text-xs text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Start over
          </button>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-xs uppercase tracking-wide text-textSecondary">Team</span>
            <CollegeSelect value={collegeId} onChange={onCollegeChange} colleges={colleges} />
            {collegeRawName && !collegeId && (
              <p className="text-xs text-danger">Unmatched: &ldquo;{collegeRawName}&rdquo;</p>
            )}
          </label>
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-xs uppercase tracking-wide text-textSecondary">Week signed</span>
            <input value={weekName} disabled className={`${inputClass} opacity-70`} />
          </label>
        </div>

        {rows.length === 0 ? (
          <p className="text-sm text-textSecondary">No recruits left to save.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] border-collapse text-left">
              <thead>
                <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                  <th className="p-2">First Name</th>
                  <th className="p-2">Last Name</th>
                  <th className="p-2">Pos</th>
                  <th className="p-2">★</th>
                  <th className="p-2">NIL</th>
                  <th className="p-2">Nat</th>
                  <th className="p-2">Pos#</th>
                  <th className="p-2">St#</th>
                  <th className="p-2">State</th>
                  <th className="p-2"></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row, index) => (
                  <RecruitRow key={index} row={row} onChange={(next) => updateRow(index, next)} />
                ))}
              </tbody>
            </table>
          </div>
        )}

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onCommit}
          disabled={committing || rows.length === 0 || !collegeId}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : "Save Recruits"}
        </button>
      </div>
    </Card>
  );
}

function RecruitmentTrailUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [weeks, setWeeks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [weekNumber, setWeekNumber] = useState("");
  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [rows, setRows] = useState(null);
  const [colleges, setColleges] = useState([]);
  const [collegeId, setCollegeId] = useState(null);
  const [collegeRawName, setCollegeRawName] = useState(null);
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
        if (season.currentWeekNumber != null) setWeekNumber(String(season.currentWeekNumber));
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

  const weekName = useMemo(() => {
    const week = weeks.find((w) => String(w.number) === String(weekNumber));
    return week ? weekLabel(week) : "";
  }, [weeks, weekNumber]);

  const resetToUpload = () => {
    setRows(null);
    setFiles([]);
    setColleges([]);
    setCollegeId(null);
    setCollegeRawName(null);
    setAnalyzeError(null);
  };

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeRecruitmentTrail(dynastyId, seasonId, files);
      setColleges(result.colleges || []);
      setCollegeId(result.collegeId ?? null);
      setCollegeRawName(result.collegeRawName ?? null);
      setRows(result.recruits || []);
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
      const result = await commitRecruitmentTrail(dynastyId, seasonId, collegeId, Number(weekNumber), rows);
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  const savedTeamName = colleges.find((c) => c.id === collegeId)?.name ?? "The team";

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
        title="Recruitment Trail"
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
            <p className="text-sm font-semibold text-success">
              Saved! {savedTeamName}&rsquo;s recruits for {weekName} have been recorded.
            </p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">
                  {warnings.length} recruit{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:
                </p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.recruit}: {warning.error}
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
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
              Upload Recruiting Screen
            </h3>
            <p className="text-sm text-textSecondary">
              Pick the week you signed them, then upload that team&rsquo;s recruiting-class screenshot(s). The
              team is read from the screenshot header. The AI reads each recruit&rsquo;s name, position, star
              rating, NIL offer, and national/position/state ranks and proposes the table below for you to
              review before anything is saved.
            </p>

            <label className="flex flex-col gap-1 text-sm sm:max-w-xs">
              <span className="text-xs uppercase tracking-wide text-textSecondary">Week signed</span>
              <select value={weekNumber} onChange={(e) => setWeekNumber(e.target.value)} className={inputClass}>
                <option value="">— select —</option>
                {weeks.map((week) => (
                  <option key={week.number} value={week.number}>
                    {weekLabel(week)}
                  </option>
                ))}
              </select>
            </label>

            <FileDropZone
              title="Recruiting Class Screenshots"
              hint="Upload as many screenshots as it takes to cover the whole class for this team."
              files={files}
              onFilesChange={setFiles}
            />

            {analyzeError && <p className="text-sm text-danger">{analyzeError}</p>}

            <button
              type="button"
              onClick={handleAnalyze}
              disabled={!weekNumber || files.length === 0 || analyzing}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {analyzing
                ? "Analyzing... this can take a minute"
                : `Analyze ${files.length || ""} Photo${files.length === 1 ? "" : "s"}`}
            </button>
          </div>
        </Card>
      ) : (
        <RecruitmentTrailReview
          collegeId={collegeId}
          collegeRawName={collegeRawName}
          colleges={colleges}
          onCollegeChange={setCollegeId}
          weekName={weekName}
          rows={rows}
          onChange={setRows}
          onBack={resetToUpload}
          onCommit={handleCommit}
          committing={committing}
          error={commitError}
        />
      )}
    </div>
  );
}

export default RecruitmentTrailUpdatePage;
