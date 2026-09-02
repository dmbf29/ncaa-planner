import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import {
  fetchDynasties,
  fetchSeason,
  analyzePortalPreview,
  commitPortalPreview,
  fetchPortalStatuses,
} from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

const STATUS_OPTIONS = [
  { value: "transfer", label: "Transfer" },
  { value: "pro_draft", label: "Pro Draft" },
  { value: "staying", label: "Staying" },
  { value: "graduation", label: "Graduation" },
];

const PERSUASION_OPTIONS = [
  { value: "not_applicable", label: "— (not applicable)" },
  { value: "none", label: "None" },
  { value: "extremely_low", label: "Extremely Low" },
  { value: "very_low", label: "Very Low" },
  { value: "low", label: "Low" },
  { value: "medium", label: "Medium" },
  { value: "high", label: "High" },
  { value: "very_high", label: "Very High" },
  { value: "extremely_high", label: "Extremely High" },
  { value: "guaranteed", label: "Guaranteed" },
];

const MATCH_BADGE_CLASSES = {
  matched: "bg-success/10 text-success",
  ambiguous: "bg-warning/10 text-warning",
  unmatched: "bg-danger/10 text-danger",
};

const MATCH_LABELS = {
  matched: "Matched",
  ambiguous: "Ambiguous",
  unmatched: "Unmatched",
};

function TeamSelect({ value, onChange, teams }) {
  return (
    <select
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className={inputClass}
    >
      <option value="">— select a team —</option>
      {teams.map((team) => (
        <option key={team.collegeId} value={team.collegeId}>
          {team.name}
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

function SelectInput({ value, onChange, options, className = inputClass }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value)} className={className}>
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  );
}

function MatchBadge({ status }) {
  if (!status) return null;

  return (
    <span className={clsx("inline-block rounded-full px-2 py-0.5 text-xs font-semibold", MATCH_BADGE_CLASSES[status])}>
      {MATCH_LABELS[status] || status}
    </span>
  );
}

function PlayerRow({ row, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <TextInput
          value={row.lastName}
          onChange={(lastName) => update({ lastName })}
          className={`${inputClass} w-32`}
          placeholder={row.firstInitial ? `${row.firstInitial}. …` : "Last name"}
        />
      </td>
      <td className="p-2">
        <TextInput value={row.position} onChange={(position) => update({ position })} className={`${inputClass} w-16`} />
      </td>
      <td className="p-2">
        <TextInput value={row.classYear} onChange={(classYear) => update({ classYear })} className={`${inputClass} w-20`} />
      </td>
      <td className="p-2">
        <NumberInput value={row.overall} onChange={(overall) => update({ overall })} />
      </td>
      <td className="p-2">
        <SelectInput value={row.status} onChange={(status) => update({ status })} options={STATUS_OPTIONS} className={`${inputClass} w-32`} />
      </td>
      <td className="p-2">
        {row.status === "transfer" && (
          <TextInput
            value={row.transferReason}
            onChange={(transferReason) => update({ transferReason })}
            className={`${inputClass} w-32`}
            placeholder="Playing Time"
          />
        )}
        {row.status === "pro_draft" && (
          <div className="flex items-center gap-1 text-xs text-textSecondary">
            Round
            <NumberInput value={row.projectedDraftRound} onChange={(projectedDraftRound) => update({ projectedDraftRound })} className={`${inputClass} w-14`} />
          </div>
        )}
      </td>
      <td className="p-2">
        <SelectInput
          value={row.persuasionChance}
          onChange={(persuasionChance) => update({ persuasionChance })}
          options={PERSUASION_OPTIONS}
          className={`${inputClass} w-36`}
        />
      </td>
      <td className="p-2">
        <MatchBadge status={row.matchStatus} />
      </td>
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function toRow(player) {
  return {
    id: player.id ?? null,
    firstInitial: player.firstInitial,
    lastName: player.lastName,
    position: player.position,
    classYear: player.classYear,
    overall: player.overall,
    status: player.status,
    transferReason: player.transferReason,
    projectedDraftRound: player.projectedDraftRound,
    persuasionChance: player.persuasionChance,
    studentSeasonId: player.studentSeasonId,
    matchStatus: player.matchStatus,
  };
}

// Mirrors the backend's upsert identity (student_season_id when present,
// else last name + position + class year) so what the reviewer sees
// merging together on screen matches what will actually happen on save.
function sameIdentity(a, b) {
  if (a.studentSeasonId && b.studentSeasonId) return a.studentSeasonId === b.studentSeasonId;
  if (a.studentSeasonId || b.studentSeasonId) return false;
  return (
    (a.lastName || "").trim().toLowerCase() === (b.lastName || "").trim().toLowerCase() &&
    (a.position || "").trim().toLowerCase() === (b.position || "").trim().toLowerCase() &&
    (a.classYear || "").trim().toLowerCase() === (b.classYear || "").trim().toLowerCase()
  );
}

function mergeRows(existing, incoming) {
  const next = [...existing];
  incoming.forEach((row) => {
    const index = next.findIndex((r) => sameIdentity(r, row));
    if (index >= 0) {
      // Keep the saved row's id (so it's still deletable/updatable in place); everything else refreshes.
      next[index] = { ...next[index], ...row, id: next[index].id };
    } else {
      next.push(row);
    }
  });
  return next;
}

function PortalPreviewUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [teams, setTeams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [collegeId, setCollegeId] = useState(null);
  const [collegeRawName, setCollegeRawName] = useState(null);
  const [rows, setRows] = useState([]);
  const [removedIds, setRemovedIds] = useState([]);
  const [loadingStatuses, setLoadingStatuses] = useState(false);
  const [statusesError, setStatusesError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saveResult, setSaveResult] = useState(null);

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
        setTeams((season.teams || []).map((t) => ({ collegeId: t.college.id, name: t.college.name })));
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

  const loadExistingStatuses = async (id) => {
    setLoadingStatuses(true);
    setStatusesError(null);
    try {
      const result = await fetchPortalStatuses(dynastyId, seasonId, id);
      setRows((result.players || []).map(toRow));
    } catch (err) {
      setStatusesError(err.message);
    } finally {
      setLoadingStatuses(false);
    }
  };

  const handleTeamSelect = (id) => {
    setCollegeId(id);
    setCollegeRawName(null);
    setRemovedIds([]);
    setSaveResult(null);
    setCommitError(null);
    setAnalyzeError(null);
    if (id) {
      loadExistingStatuses(id);
    } else {
      setRows([]);
    }
  };

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    setSaveResult(null);
    try {
      const result = await analyzePortalPreview(dynastyId, seasonId, files);
      const detectedId = result.collegeId ?? null;
      const newRows = (result.players || []).map(toRow);

      if (collegeId && detectedId && detectedId !== collegeId) {
        setAnalyzeError(
          `This screenshot's header reads "${result.collegeRawName}", which looks like a different team than the ` +
            "one you're currently editing above. Switch teams first if that's correct, or double-check you " +
            "uploaded the right screenshot.",
        );
        return;
      }

      if (!collegeId) {
        setCollegeRawName(result.collegeRawName ?? null);
        if (detectedId) {
          setCollegeId(detectedId);
          const existing = await fetchPortalStatuses(dynastyId, seasonId, detectedId);
          setRows(mergeRows((existing.players || []).map(toRow), newRows));
        } else {
          setRows((prev) => mergeRows(prev, newRows));
        }
      } else {
        setRows((prev) => mergeRows(prev, newRows));
      }
      setFiles([]);
    } catch (err) {
      setAnalyzeError(err.message);
    } finally {
      setAnalyzing(false);
    }
  };

  const updateRow = (index, nextRow) => {
    if (nextRow === null) {
      const removed = rows[index];
      if (removed?.id) setRemovedIds((prev) => [...prev, removed.id]);
      setRows(rows.filter((_, i) => i !== index));
      return;
    }
    setRows(rows.map((row, i) => (i === index ? nextRow : row)));
  };

  const handleCommit = async () => {
    setCommitting(true);
    setCommitError(null);
    setSaveResult(null);
    try {
      const result = await commitPortalPreview(dynastyId, seasonId, collegeId, rows, removedIds);
      setSaveResult({ warnings: result.warnings || [] });
      setRemovedIds([]);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  const unmatchedCount = rows.filter((row) => row.matchStatus === "unmatched").length;
  const selectedTeamName = teams.find((t) => t.collegeId === collegeId)?.name;

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
        title="Portal Preview"
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

      <Card>
        <div className="p-5 space-y-4">
          <div>
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Team</h3>
            <p className="text-sm text-textSecondary">
              Pick a team to see and edit its current portal outlook, or upload a screenshot below and the team
              will be picked up automatically from the header.
            </p>
          </div>
          <label className="flex flex-col gap-1 text-sm sm:max-w-xs">
            <TeamSelect value={collegeId} onChange={handleTeamSelect} teams={teams} />
            {collegeRawName && !collegeId && <p className="text-xs text-danger">Unmatched: &ldquo;{collegeRawName}&rdquo;</p>}
          </label>

          <div className="border-t border-border pt-4 dark:border-darkborder">
            <p className="text-sm font-semibold text-charcoal dark:text-white">
              {collegeId ? `Upload More for ${selectedTeamName || "This Team"}` : "Or Upload a Screenshot to Get Started"}
            </p>
            <p className="mt-1 text-xs text-textSecondary">
              A full roster is usually more pages than fit in one sitting — upload as many or as few screens as you
              have right now, and come back and upload more later. This is also how you&rsquo;d record what
              happened after a coach tries to persuade a player: take a new screenshot once the persuasion attempt
              is resolved and upload just that page — it&rsquo;ll update the existing row rather than duplicate it.
            </p>
            <div className="mt-3">
              <FileDropZone title="Players Leaving Screenshots" hint="One team at a time." files={files} onFilesChange={setFiles} />
            </div>
            {analyzeError && <p className="mt-2 text-sm text-danger">{analyzeError}</p>}
            <button
              type="button"
              onClick={handleAnalyze}
              disabled={files.length === 0 || analyzing}
              className="mt-3 rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {analyzing ? "Analyzing... this can take a minute" : `Analyze ${files.length || ""} Photo${files.length === 1 ? "" : "s"}`}
            </button>
          </div>
        </div>
      </Card>

      {collegeId && (
        <Card>
          <div className="p-5 space-y-4">
            <div>
              <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
                {selectedTeamName || "Team"}&rsquo;s Portal Outlook
              </h3>
              <p className="text-sm text-textSecondary">
                Edit anything directly — this is also where you&rsquo;d update a player&rsquo;s status or
                persuasion chance by hand once you know how a persuasion attempt turned out, with no new
                screenshot needed.
              </p>
            </div>

            {loadingStatuses && <p className="text-sm text-textSecondary">Loading current outlook...</p>}
            {statusesError && <p className="text-sm text-danger">{statusesError}</p>}

            {unmatchedCount > 0 && (
              <p className="text-xs text-warning">
                {unmatchedCount} row{unmatchedCount === 1 ? "" : "s"} couldn&rsquo;t be matched to an existing roster
                entry — they&rsquo;re still saved, just without a link to a specific player record.
              </p>
            )}

            {rows.length === 0 && !loadingStatuses ? (
              <p className="text-sm text-textSecondary">No players on file yet for this team — upload a screenshot above to get started.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full min-w-[900px] border-collapse text-left">
                  <thead>
                    <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                      <th className="p-2">Name</th>
                      <th className="p-2">Pos</th>
                      <th className="p-2">Year</th>
                      <th className="p-2">OVR</th>
                      <th className="p-2">Status</th>
                      <th className="p-2">Detail</th>
                      <th className="p-2">Persuasion</th>
                      <th className="p-2">Match</th>
                      <th className="p-2"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((row, index) => (
                      <PlayerRow key={row.id ?? row.studentSeasonId ?? index} row={row} onChange={(next) => updateRow(index, next)} />
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {commitError && <p className="text-sm text-danger">{commitError}</p>}

            {saveResult && (
              <div className="rounded-md border border-success/40 bg-success/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold text-success">Saved!</p>
                {saveResult.warnings.length > 0 && (
                  <>
                    <p className="mt-1 font-semibold">
                      {saveResult.warnings.length} row{saveResult.warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:
                    </p>
                    <ul className="mt-1 list-disc pl-5">
                      {saveResult.warnings.map((warning, index) => (
                        <li key={index}>
                          {warning.player}: {warning.error}
                        </li>
                      ))}
                    </ul>
                  </>
                )}
              </div>
            )}

            <button
              type="button"
              onClick={handleCommit}
              disabled={committing || (rows.length === 0 && removedIds.length === 0)}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {committing ? "Saving..." : "Save Changes"}
            </button>
          </div>
        </Card>
      )}
    </div>
  );
}

export default PortalPreviewUpdatePage;
