import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { fetchTeams, fetchSquadBoards, createPlayer } from "../lib/apiClient";
import { weekLabel } from "./LeagueGameRow";

const inputClass =
  "w-full rounded-md border border-border bg-white px-3 py-2 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

// Loose position-code -> board-name hints, only used to float a likely
// board to the top of the picker and tag it. Board names vary wildly
// between users (full words like "Wide Receiver", bare codes like "WR"),
// so each entry lists both. A miss just means no hint is shown.
const POSITION_ALIASES = {
  QB: ["qb", "quarterback"],
  HB: ["hb", "rb", "running back", "halfback", "tailback"],
  FB: ["fb", "fullback", "running back"],
  WR: ["wr", "wide receiver", "receiver"],
  TE: ["te", "tight end"],
  LT: ["lt", "ot", "left tackle", "offensive line", "tackle"],
  LG: ["lg", "og", "left guard", "offensive line", "guard"],
  C: ["c", "center", "offensive line"],
  RG: ["rg", "og", "right guard", "offensive line", "guard"],
  RT: ["rt", "ot", "right tackle", "offensive line", "tackle"],
  LE: ["le", "de", "edge", "defensive end", "defensive line"],
  RE: ["re", "de", "edge", "defensive end", "defensive line"],
  LEDG: ["le", "re", "de", "edge", "defensive end", "defensive line"],
  REDG: ["re", "le", "de", "edge", "defensive end", "defensive line"],
  DT: ["dt", "defensive tackle", "defensive line", "interior", "nose"],
  LOLB: ["lolb", "olb", "sam", "will", "edge", "linebacker"],
  ROLB: ["rolb", "olb", "sam", "will", "edge", "linebacker"],
  MLB: ["mlb", "mike", "ilb", "linebacker"],
  MIKE: ["mike", "mlb", "ilb", "linebacker"],
  SAM: ["sam", "olb", "linebacker"],
  WILL: ["will", "olb", "linebacker"],
  CB: ["cb", "cornerback", "defensive back", "secondary"],
  FS: ["fs", "free safety", "safety", "defensive back", "secondary"],
  SS: ["ss", "strong safety", "safety", "defensive back", "secondary"],
  K: ["k", "kicker", "special teams"],
  P: ["p", "punter", "special teams"],
};

function boardMatchesPosition(board, position) {
  if (!position) return false;
  const name = board.name.toLowerCase().trim();
  const aliases = POSITION_ALIASES[position.toUpperCase()] || [position.toLowerCase()];
  // Exact code match first (board names are often just "WR"/"LE"), then a
  // looser word match for full-word board names.
  return aliases.some((alias) => name === alias) || aliases.some((alias) => alias.length > 2 && name.includes(alias));
}

function importNote(recruit) {
  const parts = [`Signed by ${recruit.collegeName}`];
  if (recruit.transfer) parts.push("portal transfer");
  if (recruit.classYear) parts.push(recruit.classYear);
  if (recruit.state) parts.push(recruit.state);
  if (recruit.nationalRank) parts.push(`#${recruit.nationalRank} national`);
  parts.push(weekLabel(recruit.week));
  return parts.join(" · ");
}

function ImportRecruitModal({ recruit, onClose, onImported }) {
  const [teams, setTeams] = useState(null);
  const [loadError, setLoadError] = useState(null);

  const [teamId, setTeamId] = useState("");
  const [boardsByTeam, setBoardsByTeam] = useState({});
  const [boardId, setBoardId] = useState("");
  const [loadingBoards, setLoadingBoards] = useState(false);

  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState(null);
  const [done, setDone] = useState(null); // { teamName, boardName, squadId }

  useEffect(() => {
    let cancelled = false;
    fetchTeams()
      .then((data) => !cancelled && setTeams(data))
      .catch((err) => !cancelled && setLoadError(err.message));
    return () => {
      cancelled = true;
    };
  }, []);

  const team = useMemo(() => (teams || []).find((t) => String(t.id) === String(teamId)) || null, [teams, teamId]);
  const boards = boardsByTeam[teamId] || null;

  const handleTeamChange = async (nextTeamId) => {
    setTeamId(nextTeamId);
    setBoardId("");
    setSubmitError(null);
    if (!nextTeamId || boardsByTeam[nextTeamId]) return;

    setLoadingBoards(true);
    try {
      const data = await fetchSquadBoards(nextTeamId);
      setBoardsByTeam((prev) => ({ ...prev, [nextTeamId]: data }));
    } catch (err) {
      setSubmitError(err.message);
    } finally {
      setLoadingBoards(false);
    }
  };

  // Squads (in the team's own order) paired with their boards; a board that
  // looks like it fits the recruit's position sorts first and gets tagged.
  const squadGroups = useMemo(() => {
    if (!team || !boards) return [];
    return (team.squads || [])
      .map((squad) => ({
        squad,
        boards: boards
          .filter((board) => String(board.squadId ?? board.squad_id) === String(squad.id))
          .map((board) => ({ ...board, fits: boardMatchesPosition(board, recruit.position) }))
          .sort((a, b) => Number(b.fits) - Number(a.fits) || (a.sortOrder ?? 0) - (b.sortOrder ?? 0)),
      }))
      .filter((group) => group.boards.length > 0);
  }, [team, boards, recruit.position]);

  const selectedBoard = useMemo(
    () => (boards || []).find((board) => String(board.id) === String(boardId)) || null,
    [boards, boardId],
  );

  const handleImport = async () => {
    if (!teamId || !boardId) return;
    setSubmitting(true);
    setSubmitError(null);
    try {
      await createPlayer(teamId, {
        name: recruit.name,
        starRating: recruit.starRating || null,
        nilAmount: recruit.nilAmount ?? null,
        classYear: recruit.classYear || null,
        status: "recruit",
        recruitStatus: "normal",
        positionBoardId: Number(boardId),
        notes: importNote(recruit),
      });
      const squadId = selectedBoard?.squadId ?? selectedBoard?.squad_id ?? null;
      setDone({ teamName: team?.name, boardName: selectedBoard?.name, squadId });
      onImported?.(recruit);
    } catch (err) {
      setSubmitError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="w-full max-w-md rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-3">
          <div>
            <h3 className="font-varsity text-xl uppercase tracking-[0.06em] text-charcoal dark:text-white">
              {done ? "Recruit Imported" : "Import Recruit"}
            </h3>
            <p className="mt-1 text-sm text-textSecondary">
              {recruit.starRating ? `${recruit.starRating}★ ` : ""}
              {recruit.position} · {recruit.name}
              {recruit.transfer ? " · portal transfer" : ""}
            </p>
            <p className="text-xs text-textSecondary">
              Signed by {recruit.collegeName} · {weekLabel(recruit.week)}
            </p>
          </div>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>

        {done ? (
          <div className="mt-5 space-y-4">
            <p className="text-sm text-textPrimary dark:text-white">
              Added <span className="font-semibold">{recruit.name}</span> to {done.teamName}
              {done.boardName ? ` › ${done.boardName}` : ""} as a recruit.
            </p>
            <div className="flex justify-end gap-2">
              {done.squadId && (
                <Link
                  to={`/teams/${teamId}/squads/${done.squadId}`}
                  className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5"
                >
                  Open squad board
                </Link>
              )}
              <button
                onClick={onClose}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Done
              </button>
            </div>
          </div>
        ) : loadError ? (
          <p className="mt-5 text-sm text-danger">{loadError}</p>
        ) : teams && teams.length === 0 ? (
          <div className="mt-5 space-y-3">
            <p className="text-sm text-textSecondary">
              You don&rsquo;t have any planner teams yet. Create one to import recruits into a squad board.
            </p>
            <Link to="/teams/new" className="text-sm font-semibold text-burnt hover:underline">
              Create a team →
            </Link>
          </div>
        ) : (
          <div className="mt-5 space-y-4">
            <label className="flex flex-col gap-1 text-sm">
              <span className="text-xs uppercase tracking-wide text-textSecondary">Team</span>
              <select
                value={teamId}
                onChange={(e) => handleTeamChange(e.target.value)}
                className={inputClass}
                disabled={!teams}
              >
                <option value="">{teams ? "— choose a team —" : "Loading…"}</option>
                {(teams || []).map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </label>

            <label className="flex flex-col gap-1 text-sm">
              <span className="text-xs uppercase tracking-wide text-textSecondary">Position board</span>
              <select
                value={boardId}
                onChange={(e) => setBoardId(e.target.value)}
                className={inputClass}
                disabled={!teamId || loadingBoards}
              >
                <option value="">
                  {!teamId ? "— team first —" : loadingBoards ? "Loading…" : "— choose a position board —"}
                </option>
                {squadGroups.map(({ squad, boards: squadBoards }) => (
                  <optgroup key={squad.id} label={squad.name}>
                    {squadBoards.map((board) => (
                      <option key={board.id} value={board.id}>
                        {board.name}
                        {board.fits ? "  · fits position" : ""}
                      </option>
                    ))}
                  </optgroup>
                ))}
              </select>
            </label>

            {submitError && <p className="text-sm text-danger">{submitError}</p>}

            <div className="flex justify-end gap-2">
              <button
                onClick={onClose}
                className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Cancel
              </button>
              <button
                onClick={handleImport}
                disabled={!teamId || !boardId || submitting}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {submitting ? "Importing…" : "Import"}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default ImportRecruitModal;
