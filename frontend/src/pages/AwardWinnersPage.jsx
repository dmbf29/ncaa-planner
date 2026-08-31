import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchAwardWinners, fetchRoster, commitAwardWinners } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const NEW_COACH = "__new__";

function playerLabel(player) {
  const bits = [player.position, player.overall ? `${player.overall} OVR` : null].filter(Boolean);
  return bits.length ? `${player.name} — ${bits.join(" · ")}` : player.name;
}

function PlayerPicker({ teams, roster, selection, onTeamChange, onPlayerChange }) {
  const { collegeSeasonId, studentSeasonId } = selection;
  const players = collegeSeasonId ? roster.players : null;

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      <select
        value={collegeSeasonId ?? ""}
        onChange={(e) => onTeamChange(e.target.value ? Number(e.target.value) : null)}
        className={inputClass}
      >
        <option value="">— pick a team —</option>
        {teams.map((team) => (
          <option key={team.collegeSeasonId} value={team.collegeSeasonId}>
            {team.coached ? "★ " : ""}
            {team.name}
          </option>
        ))}
      </select>

      <select
        value={studentSeasonId ?? ""}
        onChange={(e) => onPlayerChange(e.target.value ? Number(e.target.value) : null)}
        className={inputClass}
        disabled={!collegeSeasonId || roster.loading}
      >
        <option value="">
          {!collegeSeasonId ? "— team first —" : roster.loading ? "Loading roster…" : "— no winner —"}
        </option>
        {(players || []).map((player) => (
          <option key={player.id} value={player.id}>
            {playerLabel(player)}
          </option>
        ))}
      </select>
    </div>
  );
}

function CoachPicker({ coaches, selection, onCoachChange, onNewNameChange }) {
  const { coachId, coachName, addingNew } = selection;

  return (
    <div className="grid gap-2 sm:grid-cols-2">
      <select
        value={addingNew ? NEW_COACH : (coachId ?? "")}
        onChange={(e) => onCoachChange(e.target.value)}
        className={inputClass}
      >
        <option value="">— no winner —</option>
        {coaches.map((coach) => (
          <option key={coach.id} value={coach.id}>
            {coach.name}
          </option>
        ))}
        <option value={NEW_COACH}>＋ Add a new coach…</option>
      </select>

      {addingNew && (
        <input
          type="text"
          value={coachName ?? ""}
          onChange={(e) => onNewNameChange(e.target.value)}
          placeholder="New coach name"
          className={inputClass}
        />
      )}
    </div>
  );
}

function AwardRow({ award, teams, coaches, roster, selection, onChange, onLoadRoster }) {
  const isCoach = award.recipientType === "coach";

  const handleTeamChange = (collegeSeasonId) => {
    onChange({ collegeSeasonId, studentSeasonId: null });
    if (collegeSeasonId) onLoadRoster(collegeSeasonId);
  };

  const handleCoachChange = (value) => {
    if (value === NEW_COACH) {
      onChange({ coachId: null, coachName: "", addingNew: true });
    } else {
      onChange({ coachId: value ? Number(value) : null, coachName: "", addingNew: false });
    }
  };

  return (
    <Card>
      <div className="space-y-2 p-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-varsity text-base uppercase tracking-[0.05em] text-charcoal dark:text-white">{award.name}</h3>
            <p className="text-xs text-textSecondary">{award.description}</p>
          </div>
          {isCoach && (
            <span className="shrink-0 rounded-full bg-burnt/10 px-2 py-0.5 text-xs font-semibold text-burnt">Coach</span>
          )}
        </div>

        {isCoach ? (
          <CoachPicker
            coaches={coaches}
            selection={selection}
            onCoachChange={handleCoachChange}
            onNewNameChange={(coachName) => onChange({ coachName })}
          />
        ) : (
          <PlayerPicker
            teams={teams}
            roster={roster}
            selection={selection}
            onTeamChange={handleTeamChange}
            onPlayerChange={(studentSeasonId) => onChange({ studentSeasonId })}
          />
        )}
      </div>
    </Card>
  );
}

function initialSelection(award) {
  const winner = award.winner;
  if (award.recipientType === "coach") {
    return { coachId: winner?.coachId ?? null, coachName: "", addingNew: false };
  }
  return {
    collegeSeasonId: winner?.collegeSeasonId ?? null,
    studentSeasonId: winner?.studentSeasonId ?? null,
  };
}

function buildRow(award, selection) {
  if (award.recipientType === "coach") {
    if (selection.addingNew && selection.coachName?.trim()) {
      return { awardId: award.id, coachName: selection.coachName.trim() };
    }
    if (selection.coachId) return { awardId: award.id, coachId: selection.coachId };
    return { awardId: award.id };
  }
  if (selection.studentSeasonId) return { awardId: award.id, studentSeasonId: selection.studentSeasonId };
  return { awardId: award.id };
}

function AwardWinnersPage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [seasonId, setSeasonId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [awards, setAwards] = useState([]);
  const [teams, setTeams] = useState([]);
  const [coaches, setCoaches] = useState([]);
  const [selections, setSelections] = useState({});
  const [rosters, setRosters] = useState({});

  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [warnings, setWarnings] = useState([]);
  const [savedAt, setSavedAt] = useState(null);

  const applyAwardWinners = useCallback((data) => {
    setAwards(data.awards || []);
    setTeams(data.teams || []);
    setCoaches(data.coaches || []);
    setSelections(Object.fromEntries((data.awards || []).map((award) => [award.id, initialSelection(award)])));
  }, []);

  const loadRoster = useCallback(
    async (collegeSeasonId) => {
      if (!collegeSeasonId || rosters[collegeSeasonId]) return;
      setRosters((prev) => ({ ...prev, [collegeSeasonId]: { loading: true, players: [] } }));
      try {
        const data = await fetchRoster(dynastyId, seasonId, collegeSeasonId);
        const players = (data.positionGroups || [])
          .flatMap((group) => group.players || [])
          .sort((a, b) => (b.overall ?? 0) - (a.overall ?? 0));
        setRosters((prev) => ({ ...prev, [collegeSeasonId]: { loading: false, players } }));
      } catch {
        setRosters((prev) => ({ ...prev, [collegeSeasonId]: { loading: false, players: [] } }));
      }
    },
    [dynastyId, seasonId, rosters],
  );

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
        const data = await fetchAwardWinners(dynasty.id, latestSeason.id);
        applyAwardWinners(data);
      } catch (err) {
        setLoadError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) navigate("/auth/login");
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate, applyAwardWinners]);

  // Preload rosters for teams that already have a recorded player winner, so
  // their player dropdown shows the current pick instead of an empty list.
  useEffect(() => {
    if (!dynastyId || !seasonId) return;
    const needed = new Set(
      Object.values(selections)
        .map((selection) => selection.collegeSeasonId)
        .filter(Boolean),
    );
    needed.forEach((collegeSeasonId) => loadRoster(collegeSeasonId));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dynastyId, seasonId, awards]);

  const updateSelection = (awardId, patch) => {
    setSelections((prev) => ({ ...prev, [awardId]: { ...prev[awardId], ...patch } }));
  };

  const handleCommit = async () => {
    setCommitting(true);
    setCommitError(null);
    try {
      const rows = awards.map((award) => buildRow(award, selections[award.id] || {}));
      const result = await commitAwardWinners(dynastyId, seasonId, rows);
      setWarnings(result.warnings || []);
      const refreshed = await fetchAwardWinners(dynastyId, seasonId);
      applyAwardWinners(refreshed);
      setSavedAt(Date.now());
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
  };

  const recordedCount = useMemo(() => awards.filter((award) => award.winner).length, [awards]);

  if (loading) {
    return (
      <div className="mx-auto max-w-5xl px-4">
        <p className="text-sm text-textSecondary">Loading…</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="mx-auto max-w-5xl px-4">
        <p className="text-sm text-danger">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-5xl space-y-6 px-4 pb-10">
      <PageHeader
        title="Award Winners"
        eyebrow="Postseason"
        actions={
          <Link
            to="/dynasty/updates"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Updates
          </Link>
        }
      />

      <p className="text-sm text-textSecondary">
        Pick this season&rsquo;s winner for each award — a team then a player, or a coach. {recordedCount} of {awards.length}{" "}
        recorded. Leave any award blank to skip it.
      </p>

      <div className="sticky top-2 z-10 flex items-center gap-3 rounded-lg border border-border bg-surface/90 p-3 backdrop-blur dark:border-darkborder dark:bg-darksurface/90">
        <button
          type="button"
          onClick={handleCommit}
          disabled={committing}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving…" : "Save Award Winners"}
        </button>
        {commitError && <p className="text-sm text-danger">{commitError}</p>}
        {!commitError && savedAt && <p className="text-sm font-semibold text-success">Saved!</p>}
      </div>

      {warnings.length > 0 && (
        <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
          <p className="font-semibold">
            {warnings.length} award{warnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:
          </p>
          <ul className="mt-1 list-disc pl-5">
            {warnings.map((warning, index) => (
              <li key={index}>
                {warning.award ? `${warning.award}: ` : ""}
                {warning.error}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-2">
        {awards.map((award) => {
          const selection = selections[award.id] || {};
          const roster = rosters[selection.collegeSeasonId] || { loading: false, players: [] };
          return (
            <AwardRow
              key={award.id}
              award={award}
              teams={teams}
              coaches={coaches}
              roster={roster}
              selection={selection}
              onChange={(patch) => updateSelection(award.id, patch)}
              onLoadRoster={loadRoster}
            />
          );
        })}
      </div>
    </div>
  );
}

export default AwardWinnersPage;
