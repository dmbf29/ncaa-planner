import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import { fetchDynasties, fetchSeason, analyzeTeamSchedule, commitTeamSchedule } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const smallInputClass = `${inputClass} w-20`;

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

function NumberInput({ value, onChange, className = smallInputClass, step }) {
  return (
    <input
      type="number"
      step={step}
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
      className={className}
    />
  );
}

function TeamStatsFields({ teamStats, onChange, colleges, collegeId, collegeRawName, onCollegeChange }) {
  const update = (patch) => onChange({ ...teamStats, ...patch });

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      <label className="col-span-2 flex flex-col gap-1 text-sm sm:col-span-3">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Team</span>
        <CollegeSelect value={collegeId} onChange={onCollegeChange} colleges={colleges} />
        {collegeRawName && !collegeId && <p className="text-xs text-danger">Unmatched: &ldquo;{collegeRawName}&rdquo;</p>}
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Wins</span>
        <NumberInput value={teamStats.wins} onChange={(wins) => update({ wins })} className={inputClass} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Losses</span>
        <NumberInput value={teamStats.losses} onChange={(losses) => update({ losses })} className={inputClass} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Prestige (stars)</span>
        <NumberInput value={teamStats.prestige} onChange={(prestige) => update({ prestige })} className={inputClass} step="0.5" />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Overall</span>
        <NumberInput value={teamStats.overall} onChange={(overall) => update({ overall })} className={inputClass} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Offense</span>
        <NumberInput value={teamStats.offense} onChange={(offense) => update({ offense })} className={inputClass} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Defense</span>
        <NumberInput value={teamStats.defense} onChange={(defense) => update({ defense })} className={inputClass} />
      </label>
    </div>
  );
}

function ScheduleRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  if (row.isBye) {
    return (
      <tr className="border-b border-border align-top dark:border-darkborder">
        <td className="p-2 text-sm font-semibold text-textPrimary dark:text-white">{row.weekLabel}</td>
        <td className="p-2 text-sm text-textSecondary" colSpan={6}>
          Bye
        </td>
      </tr>
    );
  }

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 text-sm font-semibold text-textPrimary dark:text-white">{row.weekLabel}</td>
      <td className="p-2">
        <CollegeSelect value={row.opponentCollegeId} onChange={(opponentCollegeId) => update({ opponentCollegeId })} colleges={colleges} />
        {row.opponentRawName && !row.opponentCollegeId && (
          <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.opponentRawName}&rdquo;</p>
        )}
      </td>
      <td className="p-2">
        <label className="flex items-center gap-1 text-xs text-textSecondary">
          <input type="checkbox" checked={Boolean(row.isAway)} onChange={(e) => update({ isAway: e.target.checked })} />
          Away
        </label>
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
          <NumberInput value={row.teamScore} onChange={(teamScore) => update({ teamScore })} />
          <span className="text-textSecondary">-</span>
          <NumberInput value={row.opponentScore} onChange={(opponentScore) => update({ opponentScore })} />
        </div>
      </td>
    </tr>
  );
}

function ScheduleReview({
  teamStats,
  onTeamStatsChange,
  collegeId,
  collegeRawName,
  onCollegeChange,
  rows,
  colleges,
  onChange,
  onCommit,
  committing,
  error,
}) {
  const updateRow = (index, nextRow) => onChange(rows.map((row, i) => (i === index ? nextRow : row)));

  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Review Team Schedule</h3>
        <p className="text-sm text-textSecondary">
          Confirm the team below (it&rsquo;s read from the header, fix it if it&rsquo;s wrong), fix the team stats
          and any unmatched opponents, then save.
        </p>

        <TeamStatsFields
          teamStats={teamStats}
          onChange={onTeamStatsChange}
          colleges={colleges}
          collegeId={collegeId}
          collegeRawName={collegeRawName}
          onCollegeChange={onCollegeChange}
        />

        <div className="overflow-x-auto">
          <table className="w-full min-w-[820px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Week</th>
                <th className="p-2">Opponent</th>
                <th className="p-2">Away?</th>
                <th className="p-2">Date (M/D)</th>
                <th className="p-2">Time</th>
                <th className="p-2">Score (Us-Them)</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, index) => (
                <ScheduleRow key={row.weekId ?? index} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
              ))}
            </tbody>
          </table>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onCommit}
          disabled={committing || !collegeId}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : "Save Team Schedule"}
        </button>
      </div>
    </Card>
  );
}

function opponentLastResultLine(lastResult) {
  if (!lastResult) return "Season opener";
  if (lastResult.status === "bye") return `Bye (Week ${lastResult.week.number})`;
  if (lastResult.status === "missing") return `Not yet uploaded (Week ${lastResult.week.number})`;

  const { result, opponent, week } = lastResult;
  const outcome = result.won ? "W" : "L";
  const where = opponent.home ? "vs" : "@";
  return `${outcome} ${result.teamScore}-${result.opponentScore} ${where} ${opponent.name} (Week ${week.number})`;
}

function NextOpponentsCard({ teams }) {
  const withNextGame = teams.filter((team) => team.nextGame);
  if (withNextGame.length === 0) return null;

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Next Opponents</h3>
      </div>
      <div className="divide-y divide-border dark:divide-darkborder">
        {withNextGame.map((team) => {
          const { nextGame } = team;
          const record = nextGame.opponentRecord;
          const recordLabel = record && record.wins != null && record.losses != null ? `${record.wins}-${record.losses}` : "—";
          return (
            <div key={team.id} className="px-4 py-3 text-sm">
              <p className="font-semibold text-textPrimary dark:text-white">{team.college.name}</p>
              <p className="text-textSecondary">
                Week {nextGame.week.number} — {nextGame.opponent.home ? "vs" : "@"} {nextGame.opponent.name} ({recordLabel})
              </p>
              <p className="text-xs text-textSecondary">Last: {opponentLastResultLine(nextGame.opponentLastResult)}</p>
            </div>
          );
        })}
      </div>
    </Card>
  );
}

function TeamScheduleUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [teams, setTeams] = useState([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);

  const [teamStats, setTeamStats] = useState(null);
  const [collegeId, setCollegeId] = useState(null);
  const [collegeRawName, setCollegeRawName] = useState(null);
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
        setTeams(season.teams || []);
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
      const result = await analyzeTeamSchedule(dynastyId, seasonId, files);
      setTeamStats({
        wins: result.wins,
        losses: result.losses,
        prestige: result.prestige,
        overall: result.overall,
        offense: result.offense,
        defense: result.defense,
      });
      setCollegeId(result.collegeId);
      setCollegeRawName(result.collegeRawName);
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
      const result = await commitTeamSchedule(dynastyId, seasonId, collegeId, teamStats, rows);
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
        title="Update Team Schedule"
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
            <p className="text-sm font-semibold text-success">Saved! Team schedule and stats have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} week{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.weekLabel}: {warning.error}
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
        <div className="space-y-4">
          <Card>
            <div className="p-5 space-y-4">
              <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Upload Screenshots</h3>
              <p className="text-sm text-textSecondary">
                Upload as many screenshots as it takes to cover the whole season for any team &mdash; yours or an
                upcoming opponent you&rsquo;re scouting. The team is read from the header, and the AI proposes the
                table below for you to review before anything is saved.
              </p>

              <FileDropZone
                title="Team Schedule Screenshots"
                hint="Upload as many screenshots as it takes to cover every week of the season."
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
          <NextOpponentsCard teams={teams} />
        </div>
      ) : (
        <ScheduleReview
          teamStats={teamStats}
          onTeamStatsChange={setTeamStats}
          collegeId={collegeId}
          collegeRawName={collegeRawName}
          onCollegeChange={setCollegeId}
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

export default TeamScheduleUpdatePage;
