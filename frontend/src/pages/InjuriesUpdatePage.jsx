import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, analyzeInjuries, commitInjuries } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

function InjuryRow({ row, team, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <input type="checkbox" checked={row.include} onChange={(e) => update({ include: e.target.checked })} />
      </td>
      <td className="p-2 text-sm">{team?.collegeName || row.collegeRawName || "Unknown team"}</td>
      <td className="p-2">
        <select
          value={row.studentSeasonId ?? ""}
          onChange={(e) => update({ studentSeasonId: e.target.value ? Number(e.target.value) : null })}
          className={inputClass}
        >
          <option value="">— pick player —</option>
          {(team?.players || []).map((player) => (
            <option key={player.studentSeasonId} value={player.studentSeasonId}>
              {player.name} ({player.position})
            </option>
          ))}
        </select>
        <p className="mt-1 text-xs text-textSecondary">
          Screen: {row.rawName} · {row.position}
        </p>
        {!row.studentSeasonId && <p className="text-xs text-danger">No roster match.</p>}
        {row.duplicate && <p className="text-xs text-warning">Already registered.</p>}
      </td>
      <td className="p-2">
        <input value={row.description ?? ""} onChange={(e) => update({ description: e.target.value })} className={inputClass} />
      </td>
      <td className="p-2">
        <input
          type="number"
          value={row.weeksOut ?? ""}
          onChange={(e) => update({ weeksOut: e.target.value === "" ? null : Number(e.target.value) })}
          className={`${inputClass} w-20`}
        />
      </td>
      <td className="p-2">
        <select
          value={row.gameId ?? ""}
          onChange={(e) => update({ gameId: e.target.value ? Number(e.target.value) : null })}
          className={inputClass}
        >
          <option value="">— pick game —</option>
          {(team?.games || []).map((game) => (
            <option key={game.id} value={game.id}>
              Week {game.weekNumber} {game.home ? "vs" : "@"} {game.opponent}
            </option>
          ))}
        </select>
      </td>
    </tr>
  );
}

function InjuriesReview({ rows, teams, onChange, onCommit, committing, error }) {
  const teamFor = (row) => teams.find((team) => team.collegeId === row.collegeId);
  const updateRow = (index, next) => onChange(rows.map((row, i) => (i === index ? next : row)));
  const ready = (row) => row.include && row.studentSeasonId && row.gameId && row.description?.trim() && row.weeksOut > 0;
  const count = rows.filter(ready).length;

  return (
    <Card>
      <div className="space-y-4 p-5">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review Injuries</h3>
        <p className="text-sm text-textSecondary">
          New injuries start at each team&rsquo;s most recently played game. Players already registered with the same
          injury are unchecked. Fix any unmatched players, then save.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[900px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2"></th>
                <th className="p-2">Team</th>
                <th className="p-2">Player</th>
                <th className="p-2">Injury</th>
                <th className="p-2">Weeks</th>
                <th className="p-2">Starting game</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <InjuryRow key={index} row={row} team={teamFor(row)} onChange={(next) => updateRow(index, next)} />
              ))}
            </tbody>
          </table>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onCommit}
          disabled={committing || count === 0}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : `Save ${count} Injur${count === 1 ? "y" : "ies"}`}
        </button>
      </div>
    </Card>
  );
}

function InjuriesUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [rows, setRows] = useState(null);
  const [teams, setTeams] = useState([]);
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
      const result = await analyzeInjuries(dynastyId, seasonId, files);
      setRows(result.rows.map((row) => ({ ...row, include: !row.duplicate && !!row.studentSeasonId })));
      setTeams(result.teams);
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
      const toSave = rows.filter((row) => row.include && row.studentSeasonId && row.gameId && row.description?.trim() && row.weeksOut > 0);
      const result = await commitInjuries(dynastyId, seasonId, toSave);
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
        title="Register Injuries"
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
          <div className="space-y-2 p-5">
            <p className="text-sm font-semibold text-success">Saved! Injuries have been registered.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} injur{warnings.length === 1 ? "y" : "ies"} couldn&rsquo;t be saved:</p>
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
      ) : !rows ? (
        <Card>
          <div className="space-y-4 p-5">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Upload Screenshots</h3>
            <p className="text-sm text-textSecondary">
              Upload the injury report screenshot(s) for any teams. The team is read from the top-left of each screen, and
              each player is matched to their roster. New injuries start at that team&rsquo;s most recently played game.
            </p>

            <FileDropZone
              title="Injury Report Screenshots"
              hint="One or more screenshots, from any number of teams."
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
        <InjuriesReview rows={rows} teams={teams} onChange={setRows} onCommit={handleCommit} committing={committing} error={commitError} />
      )}
    </div>
  );
}

export default InjuriesUpdatePage;
