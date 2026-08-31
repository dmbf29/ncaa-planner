import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchTeam, analyzeRosterUpdate, commitRosterUpdate } from "../lib/apiClient";

const CLASS_YEARS = ["FR", "FR(RS)", "SO", "SO(RS)", "JR", "JR(RS)", "SR", "SR(RS)"];

const ATTRIBUTES = [
  { key: "speed", label: "SPD" },
  { key: "acceleration", label: "ACC" },
  { key: "agility", label: "AGI" },
  { key: "changeOfDirection", label: "COD" },
  { key: "strength", label: "STR" },
  { key: "awareness", label: "AWR" },
];

const MISSING_ACTIONS = [
  { value: "keep", label: "Keep" },
  { value: "graduated", label: "Graduated" },
  { value: "departed", label: "Departed" },
];

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-16`;

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

function PlayerSelect({ value, onChange, existingPlayers }) {
  return (
    <select
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className={inputClass}
    >
      <option value="">— New Player —</option>
      {existingPlayers.map((player) => (
        <option key={player.id} value={player.id}>
          {player.name}
        </option>
      ))}
    </select>
  );
}

function BoardSelect({ value, onChange, boards }) {
  return (
    <select
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)}
      className={inputClass}
    >
      <option value="">— pick a board —</option>
      {boards.map((board) => (
        <option key={board.id} value={board.id}>
          {board.squadName} • {board.name}
        </option>
      ))}
    </select>
  );
}

function RosterRow({ row, existingPlayers, boards, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });
  const updateAttribute = (key, value) => update({ attributeValues: { ...row.attributeValues, [key]: value } });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 min-w-[180px]">
        <PlayerSelect value={row.playerId} onChange={(playerId) => {
          const matched = existingPlayers.find((p) => p.id === playerId);
          update({ playerId, name: matched ? matched.name : row.name });
        }} existingPlayers={existingPlayers} />
        {!row.playerId && (
          <>
            <input
              value={row.name || ""}
              onChange={(e) => update({ name: e.target.value })}
              className={`${inputClass} mt-1`}
              placeholder="Full name"
            />
            <p className="mt-1 text-xs text-danger">
              Unmatched: &ldquo;{row.displayName}&rdquo; — will create new player
            </p>
          </>
        )}
      </td>
      <td className="p-2 min-w-[160px]">
        <BoardSelect value={row.positionBoardId} onChange={(positionBoardId) => update({ positionBoardId })} boards={boards} />
        {!row.positionBoardId && row.positionRaw && (
          <p className="mt-1 text-xs text-danger">Couldn&rsquo;t match position &ldquo;{row.positionRaw}&rdquo;</p>
        )}
      </td>
      <td className="p-2">
        <select value={row.classYear ?? ""} onChange={(e) => update({ classYear: e.target.value || null })} className={inputClass}>
          <option value="">—</option>
          {CLASS_YEARS.map((year) => (
            <option key={year} value={year}>
              {year}
            </option>
          ))}
        </select>
      </td>
      <td className="p-2">
        <NumberInput value={row.overall} onChange={(overall) => update({ overall })} />
      </td>
      <td className="p-2">
        <NumberInput value={row.nilAmount} onChange={(nilAmount) => update({ nilAmount })} />
      </td>
      {ATTRIBUTES.map((attr) => (
        <td key={attr.key} className="p-2">
          <NumberInput value={row.attributeValues?.[attr.key]} onChange={(value) => updateAttribute(attr.key, value)} />
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

function MissingPlayerRow({ player, action, onChange }) {
  const likelyGraduated = player.classYear === "SR" || player.classYear === "SR(RS)";
  return (
    <div className="flex items-center justify-between gap-3 border-b border-border py-2 last:border-0 dark:border-darkborder">
      <div>
        <p className="text-sm font-semibold text-textPrimary dark:text-white">{player.name}</p>
        <p className="text-xs text-textSecondary">
          {player.classYear || "—"} · {player.overall ?? "—"} OVR · {player.positionBoardName || "no board"}
        </p>
        {likelyGraduated && action === "keep" && (
          <p className="text-xs text-warning">Was {player.classYear} — likely graduated</p>
        )}
      </div>
      <select value={action} onChange={(e) => onChange(e.target.value)} className={`${inputClass} w-36`}>
        {MISSING_ACTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </div>
  );
}

function RosterUpdateReview({ rows, boards, existingPlayers, onChangeRows, missingPlayers, missingActions, onChangeMissingAction, onCommit, committing, error }) {
  const updateRow = (index, nextRow) => {
    const next = nextRow === null ? rows.filter((_, i) => i !== index) : rows.map((row, i) => (i === index ? nextRow : row));
    onChangeRows(next);
  };

  return (
    <div className="space-y-4">
      <Card>
        <div className="p-5 space-y-4">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review Roster Update</h3>
          <p className="text-sm text-textSecondary">Fix any unmatched players or positions below, then save.</p>
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1400px] border-collapse text-left">
              <thead>
                <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                  <th className="p-2">Player</th>
                  <th className="p-2">Position</th>
                  <th className="p-2">Year</th>
                  <th className="p-2">OVR</th>
                  <th className="p-2">NIL</th>
                  {ATTRIBUTES.map((attr) => (
                    <th key={attr.key} className="p-2">
                      {attr.label}
                    </th>
                  ))}
                  <th className="p-2"></th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row, index) => (
                  <RosterRow
                    key={index}
                    row={row}
                    existingPlayers={existingPlayers}
                    boards={boards}
                    onChange={(next) => updateRow(index, next)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </Card>

      {missingPlayers.length > 0 && (
        <Card>
          <div className="p-5 space-y-1">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Not Found On Screenshot</h3>
            <p className="text-sm text-textSecondary">
              These active players weren&rsquo;t matched to any row above. Nothing happens to them unless you change
              their action.
            </p>
            <div className="pt-2">
              {missingPlayers.map((player) => (
                <MissingPlayerRow
                  key={player.id}
                  player={player}
                  action={missingActions[player.id] || "keep"}
                  onChange={(action) => onChangeMissingAction(player.id, action)}
                />
              ))}
            </div>
          </div>
        </Card>
      )}

      <Card>
        <div className="p-5 space-y-3">
          {error && <p className="text-sm text-danger">{error}</p>}
          <button
            type="button"
            onClick={onCommit}
            disabled={committing}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {committing ? "Saving..." : "Save Roster Update"}
          </button>
        </div>
      </Card>
    </div>
  );
}

function RosterBatchUpdatePage() {
  const { id } = useParams();
  const [team, setTeam] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [rows, setRows] = useState(null);
  const [boards, setBoards] = useState([]);
  const [existingPlayers, setExistingPlayers] = useState([]);
  const [missingActions, setMissingActions] = useState({});

  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [warnings, setWarnings] = useState([]);

  useEffect(() => {
    fetchTeam(id).then(setTeam).catch(() => {});
  }, [id]);

  const offenseSquadId = team?.squads?.find((s) => s.name?.toLowerCase()?.includes("off"))?.id;

  const matchedPlayerIds = useMemo(() => new Set((rows || []).map((r) => r.playerId).filter(Boolean)), [rows]);
  const missingPlayers = useMemo(
    () => existingPlayers.filter((p) => !matchedPlayerIds.has(p.id)),
    [existingPlayers, matchedPlayerIds],
  );

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeRosterUpdate(id, files);
      setRows(result.rows);
      setBoards(result.boards);
      setExistingPlayers(result.existingPlayers);
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
      const missingPlayerActions = missingPlayers.map((player) => ({
        playerId: player.id,
        action: missingActions[player.id] || "keep",
      }));
      const result = await commitRosterUpdate(id, { rows, missingPlayerActions });
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  return (
    <div className="max-w-6xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Batch Update Roster"
        eyebrow={team ? team.name : "Loading..."}
        actions={
          offenseSquadId && (
            <Link
              to={`/teams/${id}/squads/${offenseSquadId}`}
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Back to Roster
            </Link>
          )
        }
      />

      {saved ? (
        <Card>
          <div className="p-5 space-y-2">
            <p className="text-sm font-semibold text-success">Saved! The roster has been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">
                  {warnings.length} row{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:
                </p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.player}: {warning.error}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {offenseSquadId && (
              <Link to={`/teams/${id}/squads/${offenseSquadId}`} className="text-sm text-burnt hover:underline">
                Back to Roster
              </Link>
            )}
          </div>
        </Card>
      ) : !rows ? (
        <Card>
          <div className="p-5 space-y-4">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Upload Screenshots</h3>
            <p className="text-sm text-textSecondary">
              Upload the in-game roster screenshot(s). The AI reads every row — name, year, position, overall,
              NIL, and attributes — and proposes updates below for you to review before anything is saved.
            </p>

            <FileDropZone
              title="Roster Screenshots"
              hint="Upload as many screenshots as it takes to cover the whole roster."
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
        <RosterUpdateReview
          rows={rows}
          boards={boards}
          existingPlayers={existingPlayers}
          onChangeRows={setRows}
          missingPlayers={missingPlayers}
          missingActions={missingActions}
          onChangeMissingAction={(playerId, action) => setMissingActions((prev) => ({ ...prev, [playerId]: action }))}
          onCommit={handleCommit}
          committing={committing}
          error={commitError}
        />
      )}
    </div>
  );
}

export default RosterBatchUpdatePage;
