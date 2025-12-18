import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatPill from "../components/StatPill";
import {
  fetchTeam,
  fetchSquadBoards,
  fetchPlayers,
  createRosterSlot,
  updateRosterSlot,
  updatePositionBoard,
  createPlayer,
  updatePlayer,
} from "../lib/apiClient";

function SquadBoardPage() {
  const { id, squadId } = useParams();
  const [team, setTeam] = useState(null);
  const [boards, setBoards] = useState([]);
  const [error, setError] = useState(null);
  const [players, setPlayers] = useState([]);
  const [busyBoardId, setBusyBoardId] = useState(null);
  const [showFormBoardId, setShowFormBoardId] = useState(null);
  const [newPlayer, setNewPlayer] = useState({ name: "", starRating: "", archetype: "" });
  const [draggingId, setDraggingId] = useState(null);

  useEffect(() => {
    const load = async () => {
      try {
        const [teamData, boardsData, playersData] = await Promise.all([
          fetchTeam(id),
          fetchSquadBoards(id, squadId),
          fetchPlayers(id, { status: "rostered" }),
        ]);
        setTeam(teamData);
        setBoards(boardsData);
        setPlayers(playersData);
      } catch (err) {
        setError(err.message);
      }
    };
    load();
  }, [id, squadId]);

  const squadList = useMemo(() => team?.squads || [], [team]);
  const filteredBoards = useMemo(
    () => boards.filter((b) => String(b.squadId || b.squad_id) === String(squadId)),
    [boards, squadId],
  );

  const sortedBoards = useMemo(
    () =>
      [...filteredBoards].sort(
        (a, b) => (a.sortOrder || a.sort_order || 0) - (b.sortOrder || b.sort_order || 0),
      ),
    [filteredBoards],
  );

  const assignedPlayerIds = useMemo(() => {
    const ids = new Set();
    filteredBoards.forEach((b) =>
      (b.rosterSlots || b.roster_slots || []).forEach((rs) => ids.add(rs.playerId || rs.player_id)),
    );
    return ids;
  }, [filteredBoards]);

  const availablePlayers = useMemo(
    () => players.filter((p) => !assignedPlayerIds.has(p.id)),
    [players, assignedPlayerIds],
  );

  const handleAssign = async (boardId, playerId, slotNumber) => {
    if (!playerId || !slotNumber) return;
    setBusyBoardId(boardId);
    try {
      const existing = filteredBoards
        .find((b) => b.id === boardId)
        ?.rosterSlots?.find((rs) => rs.slotNumber === slotNumber || rs.slot_number === slotNumber);
      if (existing) {
        await updateRosterSlot(boardId, existing.id, { player_id: playerId, slot_number: slotNumber });
      } else {
        await createRosterSlot(boardId, { player_id: playerId, slot_number: slotNumber });
      }
      await updatePlayer(id, playerId, { status: "rostered", position_board_id: boardId });
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
      const playersData = await fetchPlayers(id, { status: "rostered" });
      setPlayers(playersData);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
    }
  };

  const handleCreatePlayer = async (boardId) => {
    if (!newPlayer.name.trim()) return;
    setBusyBoardId(boardId);
    try {
      await createPlayer(id, {
        name: newPlayer.name,
        star_rating: newPlayer.starRating || null,
        archetype: newPlayer.archetype || null,
        status: "recruit",
        position_board_id: boardId,
      });
      setNewPlayer({ name: "", starRating: "", archetype: "" });
      setShowFormBoardId(null);
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
      setPlayers(playersData);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
    }
  };

  const reorderBoards = async (dragId, dropId) => {
    if (!dragId || !dropId || dragId === dropId) return;
    const current = sortedBoards;
    const dragIndex = current.findIndex((b) => b.id === dragId);
    const dropIndex = current.findIndex((b) => b.id === dropId);
    if (dragIndex === -1 || dropIndex === -1) return;
    const next = [...current];
    const [moved] = next.splice(dragIndex, 1);
    next.splice(dropIndex, 0, moved);
    // Optimistic local sort_order update
    const withOrder = next.map((b, idx) => ({ ...b, sortOrder: idx + 1, sort_order: idx + 1 }));
    setBoards((prev) => {
      const others = prev.filter((b) => String(b.squadId || b.squad_id) !== String(squadId));
      return [...others, ...withOrder];
    });
    try {
      setBusyBoardId("reorder");
      await Promise.all(
        withOrder.map((b) => updatePositionBoard(id, b.id, { sort_order: b.sortOrder || b.sort_order })),
      );
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
      setDraggingId(null);
    }
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title={team ? `${team.name}` : "Loading..."}
        eyebrow="Roster Planner"
        actions={
          squadList.length > 0 && (
            <div className="flex flex-wrap gap-2">
              {squadList.map((sq) => (
                <Link
                  key={sq.id}
                  to={`/teams/${id}/squads/${sq.id}`}
                  className={`rounded-md px-3 py-2 text-sm font-semibold transition ${
                    String(sq.id) === String(squadId)
                      ? "bg-burnt text-charcoal shadow-card"
                      : "border border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                  }`}
                >
                  {sq.name}
                </Link>
              ))}
            </div>
          )
        }
      />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading squad...</p>}
      <div className="grid gap-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
        {sortedBoards.map((board) => {
          const rosterSlots = board.rosterSlots || board.roster_slots || [];
          const slotCount = board.slotsCount || board.slots_count || 0;
          const slotsArray = Array.from({ length: slotCount }).map((_, idx) => {
            const slotNum = idx + 1;
            const occupant = rosterSlots.find((rs) => (rs.slotNumber || rs.slot_number) === slotNum);
            return { slotNum, occupant };
          });
          const recruits = players.filter(
            (p) =>
              p.status === "recruit" &&
              String(p.positionBoardId || p.position_board_id || "") === String(board.id),
          );
          return (
          <Card
            key={board.id}
            draggable
            onDragStart={() => setDraggingId(board.id)}
            onDragOver={(e) => e.preventDefault()}
            onDrop={() => reorderBoards(draggingId, board.id)}
            className="cursor-move"
          >
            <div className="p-5 space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs uppercase tracking-[0.14em] text-textSecondary">Position</p>
                  <h3 className="font-varsity text-xl tracking-[0.07em] uppercase">{board.name}</h3>
                </div>
                <StatPill label="Slots" value={board.slotsCount} />
              </div>
              <div className="yard-line rounded-lg border border-border bg-surface/60 p-3 text-sm text-textSecondary dark:border-darkborder dark:bg-darksurface/60 space-y-2">
                <p className="mb-1 font-semibold text-charcoal dark:text-white">Roster Slots</p>
                <ul className="space-y-1">
                  {slotsArray.map(({ slotNum, occupant }) => (
                    <li
                      key={slotNum}
                      className="flex items-center justify-between gap-2 rounded-md border border-border bg-white/80 px-2 py-2 text-sm dark:border-darkborder dark:bg-darksurface/80"
                    >
                      <div className="flex items-center gap-2">
                        <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-burnt/80 text-xs font-bold text-charcoal">
                          {slotNum}
                        </span>
                        {occupant ? (
                          <span className="text-textPrimary dark:text-white">
                            Player #{occupant.playerId || occupant.player_id}
                          </span>
                        ) : (
                          <span className="text-textSecondary">Empty</span>
                        )}
                      </div>
                      {!occupant && availablePlayers.length > 0 && (
                        <select
                          defaultValue=""
                          onChange={(e) => {
                            const pid = e.target.value;
                            if (!pid) return;
                            handleAssign(board.id, pid, slotNum);
                            e.target.value = "";
                          }}
                          className="w-40 rounded-md border border-border bg-white px-2 py-1 text-xs focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                          disabled={busyBoardId === board.id}
                        >
                          <option value="" disabled>
                            Assign player
                          </option>
                          {availablePlayers.map((p) => (
                            <option key={p.id} value={p.id}>
                              {p.name} · OVR {p.overall || "—"}
                            </option>
                          ))}
                        </select>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="rounded-lg border border-border bg-surface/60 p-3 dark:border-darkborder dark:bg-darksurface/60 space-y-2">
                <div className="flex items-center justify-between">
                  <p className="text-sm font-semibold text-textSecondary">Recruits</p>
                  <button
                    type="button"
                    onClick={() => setShowFormBoardId((prev) => (prev === board.id ? null : board.id))}
                    className="text-sm font-semibold text-burnt hover:underline"
                  >
                    {showFormBoardId === board.id ? "Close" : "+ Add"}
                  </button>
                </div>
                {showFormBoardId === board.id && (
                  <div className="grid gap-2 md:grid-cols-3">
                    <input
                      placeholder="Name"
                      value={newPlayer.name}
                      onChange={(e) => setNewPlayer((p) => ({ ...p, name: e.target.value }))}
                      className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                    />
                    <input
                      type="number"
                      min={1}
                      max={5}
                      placeholder="Stars"
                      value={newPlayer.starRating}
                      onChange={(e) => setNewPlayer((p) => ({ ...p, starRating: e.target.value }))}
                      className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                    />
                    <input
                      placeholder="Archetype"
                      value={newPlayer.archetype}
                      onChange={(e) => setNewPlayer((p) => ({ ...p, archetype: e.target.value }))}
                      className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                    />
                    <button
                      type="button"
                      onClick={() => handleCreatePlayer(board.id)}
                      disabled={busyBoardId === board.id || !newPlayer.name.trim()}
                      className="md:col-span-3 rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-charcoal shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-70"
                    >
                      Create Recruit
                    </button>
                  </div>
                )}
                {recruits.length === 0 && <p className="text-xs text-textSecondary">No recruits yet.</p>}
                {recruits.length > 0 && (
                  <ul className="space-y-2">
                    {recruits.map((p) => (
                      <li
                        key={p.id}
                        className="flex items-center justify-between rounded-md border border-border bg-white/80 px-3 py-2 text-sm dark:border-darkborder dark:bg-darksurface/80"
                      >
                        <div>
                          <p className="font-semibold text-charcoal dark:text-white">{p.name}</p>
                          <p className="text-xs text-textSecondary">
                            Stars: {p.starRating || "—"} · Archetype: {p.archetype || "—"}
                          </p>
                        </div>
                        <select
                          defaultValue=""
                          onChange={(e) => {
                            const slot = e.target.value;
                            if (!slot) return;
                            handleAssign(board.id, p.id, Number(slot));
                            e.target.value = "";
                          }}
                          className="w-32 rounded-md border border-border bg-white px-2 py-1 text-xs focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                          disabled={busyBoardId === board.id}
                        >
                          <option value="" disabled>
                            Send to slot
                          </option>
                          {Array.from({ length: slotCount }).map((_, idx) => (
                            <option key={idx + 1} value={idx + 1}>
                              Slot {idx + 1}
                            </option>
                          ))}
                        </select>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </Card>
          );
        })}
      </div>
    </div>
  );
}

export default SquadBoardPage;
