import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatPill from "../components/StatPill";
import OverallPill from "../components/OverallPill";
import {
  fetchTeam,
  fetchSquadBoards,
  fetchPlayers,
  createRosterSlot,
  updateRosterSlot,
  updatePositionBoard,
  createPlayer,
  updatePlayer,
  deletePlayer,
  deleteRosterSlot,
} from "../lib/apiClient";

const archetypeGroups = {
  Quarterback: {
    "Backfield Creator": "BC",
    "Dual Threat": "DT",
    "Pocket Passer": "PP",
    "Pure Runner": "PR",
  },
  Halfback: {
    "Backfield Threat": "BT",
    "Contact Seeker": "CS",
    "East/West Playmaker": "EWP",
    "Elusive Bruiser": "EB",
    "North/South Blocker": "NSB",
    "North/South Receiver": "NSR",
  },
  Fullback: {
    Blocking: "B",
    Utility: "U",
  },
  "Wide Receiver / Tight End": {
    "Contested Specialist": "CS",
    "Elusive Route Runner": "ERR",
    Gadget: "G",
    "Gritty Possession": "GP",
    Possession: "P",
    "Physical Route Runner": "PRR",
    "Pure Blocker": "PB",
    "Route Artist": "RA",
    Speedster: "S",
    "Vertical Threat": "VT",
  },
  "Offensive Line": {
    Agile: "A",
    "Pass Protector": "PP",
    "Raw Strength": "RS",
    "Well Rounded": "WR",
  },
  "Defensive Line": {
    "Edge Setter": "ES",
    "Gap Specialist": "GS",
    "Power Rusher": "PR",
    "Pure Power": "PP",
    "Speed Rusher": "SR",
  },
  Linebacker: {
    Lurker: "L",
    "Signal Caller": "SC",
    Thumper: "T",
  },
  Cornerback: {
    "Boundary Corner": "BC",
    "Bump and Run": "BR",
    Field: "F",
    Zone: "Z",
  },
  Safety: {
    "Box Specialist": "BS",
    "Coverage Specialist": "CS",
    Hybrid: "H",
  },
  "Kicker / Punter": {
    Accurate: "A",
    Power: "P",
  },
};

const archetypeShort = (longLabel) => {
  for (const group of Object.values(archetypeGroups)) {
    for (const [label, code] of Object.entries(group)) {
      if (label === longLabel) return code;
      if (code === longLabel) return code;
    }
  }
  return longLabel || "";
};

const classYears = ["FR", "FR(RS)", "SO", "SO(RS)", "JR", "JR(RS)", "SR", "SR(RS)", "Rec", "✍️"];

const devTraitOptions = [
  { value: "normal", label: "Normal" },
  { value: "impact", label: "Impact" },
  { value: "star", label: "Star" },
  { value: "elite", label: "Elite" },
];

const devTraitMeta = {
  normal: { icon: "fa-lemon", color: "text-textSecondary/40", label: "Normal" },
  impact: { icon: "fa-dumbbell", color: "text-textSecondary/50", label: "Impact" },
  star: { icon: "fa-star", color: "text-textSecondary/70", label: "Star" },
  elite: { icon: "fa-crown", color: "text-textSecondary/80", label: "Elite" },
};

const statusButtonOptions = [
  { value: "graduated", label: "Graduated" },
  { value: "departed", label: "Departed" },
];

function DevTraitButtons({ value, onChange }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      {devTraitOptions.map((option) => {
        const selected = value === option.value;
        const meta = devTraitMeta[option.value] || devTraitMeta.normal;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(selected ? "" : option.value)}
            className={`rounded-md border px-3 py-2 text-xs transition ${
              selected
                ? "bg-success text-white border-success shadow-card"
                : "border-border text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            }`}
          >
            <span className="inline-flex items-center gap-2">
              <i
                className={`fa-solid ${meta.icon} ${
                  selected ? "text-white" : meta.color
                }`}
              />
              <span>{option.label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}

function StatusButtons({ value, onChange }) {
  return (
    <div className="grid grid-cols-2 gap-2">
      {statusButtonOptions.map((option) => {
        const selected = value === option.value;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(selected ? "" : option.value)}
            className={`rounded-md border px-3 py-2 text-sm font-normal transition ${
              selected
                ? "bg-success text-white border-success shadow-card"
                : "border-border text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            }`}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

function SquadBoardPage() {
  const { id, squadId } = useParams();
  const [team, setTeam] = useState(null);
  const [boards, setBoards] = useState([]);
  const [error, setError] = useState(null);
  const [players, setPlayers] = useState([]);
  const [busyBoardId, setBusyBoardId] = useState(null);
  const [showFormBoardId, setShowFormBoardId] = useState(null);
  const [newPlayer, setNewPlayer] = useState({
    name: "",
    starRating: 3,
    archetype: "",
    overall: "",
    classYear: "",
    devTrait: "",
  });
  const [draggingCardId, setDraggingCardId] = useState(null);
  const [draggingPlayer, setDraggingPlayer] = useState(null);
  const [editing, setEditing] = useState(null);
  const [dragOverSlot, setDragOverSlot] = useState(null); // { boardId, slotNum }
  const [dragOverRecruitBoard, setDragOverRecruitBoard] = useState(null); // boardId
  const cardRefs = useRef({});

  useEffect(() => {
    const load = async () => {
      try {
        const [teamData, boardsData, playersData] = await Promise.all([
          fetchTeam(id),
          fetchSquadBoards(id, squadId),
          fetchPlayers(id, { status: ["recruit", "rostered"] }),
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

  const renderTrait = (trait) => {
    const meta = devTraitMeta[trait] || devTraitMeta.normal;
    return (
      <span className="inline-flex items-center gap-1 text-xs">
        <i className={`fa-solid ${meta.color} ${meta.icon}`} />
      </span>
    );
  };

  const classColor = (cls) => {
    const map = {
      FR: "text-[#4C7A4F]",
      "FR(RS)": "text-[#5C6F4E]",
      SO: "text-[#7595ba]",
      "SO(RS)": "text-[#7595ba]",
      JR: "text-[#bf8167]",
      "JR(RS)": "text-[#bf8167]",
      SR: "text-[#991B1B]",
      "SR(RS)": "text-[#991B1B]",
    };
    return map[cls] || "text-textSecondary";
  };

  const PlayerSummary = ({ player }) => {
    if (!player) return null;
    const star = player.starRating ?? player.star_rating;
    const classYear = player.classYear ?? player.class_year;
    const archetype = archetypeShort(player.archetype);
    const overall = player.overall;
    const trait = player.devTrait ?? player.dev_trait;

    const AttributeCell = ({ value }) => (
      <div className="flex flex-col">
        <span className="text-xs text-textSecondary font-medium min-h-[1.1rem] flex items-center">
          {value ?? <span className="text-border">—</span>}
        </span>
      </div>
    );

    return (
      <div className="flex flex-col w-full gap-1">
        <div className="flex items-center justify-between gap-2 px-2 pt-2">
          <span className="text-textPrimary dark:text-white font-semibold">
            {player.name || player.id}
          </span>
          {overall ? <OverallPill value={overall} /> : null}
        </div>
        <div className="grid grid-cols-4 gap-1 px-2 bg-textSecondary/5 py-1">
          <AttributeCell
            value={classYear ? <span className={classColor(classYear)}>{classYear}</span> : null}
          />
          <AttributeCell
            value={
              star ? (
                <span className="flex items-center gap-0">
                  <span className="text-textSecondary/80 dark:text-white">{star}</span>
                  <span className="text-textSecondary/50">★</span>
                </span>
              ) : null
            }
          />
          <AttributeCell value={trait ? renderTrait(trait) : null} />
          <AttributeCell value={archetype ? archetype : null} />
        </div>
      </div>
    );
  };

  const handleAssign = async (boardId, playerId, slotNumber) => {
    if (!playerId || !slotNumber) return;
    setBusyBoardId(boardId);
    try {
      const allBoards = boards || [];
      const existingForPlayer = allBoards
        .map((b) => ({
          boardId: b.id,
          slot: (b.rosterSlots || b.roster_slots || []).find(
            (rs) => (rs.playerId || rs.player_id) === playerId,
          ),
        }))
        .find((entry) => entry.slot);

      if (existingForPlayer?.slot) {
        if (existingForPlayer.boardId === boardId) {
          // Same board: just move slot number
          await updateRosterSlot(boardId, existingForPlayer.slot.id, { player_id: playerId, slot_number: slotNumber });
        } else {
          // Different board: remove from old, add to new
          await deleteRosterSlot(existingForPlayer.boardId, existingForPlayer.slot.id);
          await createRosterSlot(boardId, { player_id: playerId, slot_number: slotNumber });
        }
      } else {
        await createRosterSlot(boardId, { player_id: playerId, slot_number: slotNumber });
      }

      await updatePlayer(id, playerId, { status: "rostered", position_board_id: boardId });
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
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
        overall: newPlayer.overall || null,
        class_year: newPlayer.classYear || null,
        dev_trait: newPlayer.devTrait || null,
        status: "recruit",
        position_board_id: boardId,
      });
      setNewPlayer({ name: "", starRating: "", archetype: "", overall: "", classYear: "", devTrait: "" });
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
    }
  };

  const onPlayerDragStart = (playerId, fromBoardId) => {
    setDraggingPlayer({ playerId, fromBoardId });
  };

  const onPlayerDragEnd = () => {
    setDraggingPlayer(null);
  };

  const onSlotDrop = (boardId, slotNum) => {
    if (draggingPlayer?.playerId) {
      handleAssign(boardId, draggingPlayer.playerId, slotNum);
      setDraggingPlayer(null);
    }
    setDragOverSlot(null);
  };

  const handleBoardDragStart = (e, boardId) => {
    if (!e?.dataTransfer) return;
    setDraggingCardId(boardId);
    const cardEl = cardRefs.current[boardId];
    if (cardEl) {
      const rect = cardEl.getBoundingClientRect();
      e.dataTransfer.setDragImage(cardEl, rect.width / 2, rect.height / 6);
    }
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", String(boardId));
  };

  const moveToRecruit = async (boardId, playerId) => {
    if (!playerId) return;
    setBusyBoardId(boardId);
    try {
      // find existing slot for this player on any board
      const existing = boards
        .map((b) => ({
          boardId: b.id,
          slot: (b.rosterSlots || b.roster_slots || []).find(
            (rs) => (rs.playerId || rs.player_id) === playerId,
          ),
        }))
        .find((entry) => entry.slot);
      if (existing?.slot) {
        await deleteRosterSlot(existing.boardId, existing.slot.id);
      }
      await updatePlayer(id, playerId, { status: "recruit", position_board_id: boardId });
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
      setPlayers(playersData);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
      setDraggingPlayer(null);
      setDragOverRecruitBoard(null);
    }
  };

  const openEdit = (player, boardId, slotNum) => {
    setEditing({
      id: player.id,
      boardId,
      slotNum,
      name: player.name || "",
      classYear: player.classYear || "",
      devTrait: player.devTrait || "",
      archetype: player.archetype || "",
      overall: player.overall || "",
      starRating: player.starRating || 3,
      status: player.status || "recruit",
    });
  };

  const closeEdit = () => setEditing(null);

  const saveEdit = async (draft = null) => {
    const payload = draft || editing;
    if (!payload) return;
    setBusyBoardId("edit");
    try {
      const isAlumni = payload.status === "graduated" || payload.status === "departed";

      if (isAlumni) {
        const board = sortedBoards.find((b) => b.id === payload.boardId);
        const slot = board?.rosterSlots?.find((rs) => (rs.playerId || rs.player_id) === payload.id);
        if (slot) {
          await deleteRosterSlot(payload.boardId, slot.id);
        }
      }

      await updatePlayer(id, payload.id, {
        name: payload.name,
        class_year: payload.classYear,
        dev_trait: payload.devTrait,
        archetype: payload.archetype,
        overall: payload.overall,
        star_rating: payload.starRating,
        status: payload.status,
        position_board_id: isAlumni ? null : payload.boardId || null,
      });
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
      setPlayers(playersData);
      closeEdit();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
    }
  };

  const deleteEditPlayer = async () => {
    if (!editing) return;
    setBusyBoardId("edit");
    try {
      const board = sortedBoards.find((b) => b.id === editing.boardId);
      const slot = board?.rosterSlots?.find((rs) => (rs.playerId || rs.player_id) === editing.id);
      if (slot) {
        await deleteRosterSlot(editing.boardId, slot.id);
      }
      await deletePlayer(id, editing.id);
      const boardsData = await fetchSquadBoards(id, squadId);
      setBoards(boardsData);
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
      setPlayers(playersData);
      closeEdit();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
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
                  className={`rounded-md px-3 py-2 text-sm transition ${
                    String(sq.id) === String(squadId)
                      ? "border bg-burnt/5 border-burnt font-semibold text-burnt shadow-card"
                      : "border border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                  }`}
                >
                  {sq.name}
                </Link>
              ))}
              <Link
                to={`/teams/${id}/graduates`}
                className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Alumni
              </Link>
            </div>
          )
        }
      />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading squad...</p>}
      <div className="grid gap-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
        {sortedBoards.map((board) => {
          const rosterSlots = board.rosterSlots || board.roster_slots || [];
          const assignedIds = new Set(
            rosterSlots.map((rs) => rs.playerId || rs.player_id).filter(Boolean),
          );
          const slotCount = board.slotsCount || board.slots_count || 0;
          const slotsArray = Array.from({ length: slotCount }).map((_, idx) => {
            const slotNum = idx + 1;
            const occupant = rosterSlots.find((rs) => (rs.slotNumber || rs.slot_number) === slotNum);
            return { slotNum, occupant };
          });
          const recruits = players.filter(
            (p) =>
              (p.status === "recruit" || p.status === "rostered") &&
              String(p.positionBoardId || p.position_board_id || "") === String(board.id) &&
              !assignedIds.has(p.id),
          );
          return (
          <Card
            key={board.id}
            ref={(el) => {
              if (el) {
                cardRefs.current[board.id] = el;
              } else {
                delete cardRefs.current[board.id];
              }
            }}
            onDragOver={(e) => {
              if (draggingCardId) e.preventDefault();
            }}
            onDrop={() => {
              if (draggingCardId) reorderBoards(draggingCardId, board.id);
            }}
            className={`relative ${draggingCardId === board.id ? "opacity-70" : ""}`}
          >
            <div className="p-5 space-y-3 flex flex-col justify-between h-full">
              <div>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-xs uppercase tracking-[0.14em] text-textSecondary">Position</p>
                    <div className="flex">
                      <button
                        type="button"
                        draggable
                        onDragStart={(e) => handleBoardDragStart(e, board.id)}
                        onDragEnd={() => setDraggingCardId(null)}
                        className="cursor-grab text-textSecondary hover:text-charcoal dark:text-white/60 dark:hover:text-white"
                        title="Drag to reorder"
                      >
                        ⠇
                      </button>
                    <h3 className="font-varsity text-xl tracking-[0.07em] uppercase">{board.name}</h3>
                    </div>
                  </div>
                  <StatPill label="Needs" value={board.slotsCount} />
                </div>
                <div className="rounded-lg bg-surface/60 text-sm text-textSecondary dark:border-darkborder dark:bg-darksurface/60 space-y-2 mt-2">
                  <ul className="space-y-1">
                    {slotsArray.map(({ slotNum, occupant }) => (
                      <li
                        key={slotNum}
                        className={`flex items-center justify-between gap-2 rounded-md border text-sm dark:border-darkborder dark:bg-darksurface/80 transition ${
                          dragOverSlot?.boardId === board.id && dragOverSlot?.slotNum === slotNum
                            ? "border-burnt bg-burnt/10 scale-[1.02]"
                            : "border-border bg-white/80"
                        } ${occupant ? "cursor-grab active:cursor-grabbing" : ""}`}
                        draggable={Boolean(occupant)}
                        onDragStart={() =>
                          occupant && onPlayerDragStart(occupant.playerId || occupant.player_id, board.id)
                        }
                        onDragEnd={onPlayerDragEnd}
                        onDragOver={(e) => {
                          e.preventDefault();
                          setDragOverSlot({ boardId: board.id, slotNum });
                        }}
                        onDragEnter={(e) => {
                          e.preventDefault();
                          setDragOverSlot({ boardId: board.id, slotNum });
                        }}
                        onDragLeave={() => setDragOverSlot(null)}
                        onDrop={(e) => {
                          e.preventDefault();
                          onSlotDrop(board.id, slotNum);
                        }}
                      >
                        <div className="flex items-center gap-2 w-full">
                          {occupant ? (
                            <div
                              className="flex flex-col cursor-pointer w-full"
                              onClick={() => openEdit(occupant.player || {}, board.id, slotNum)}
                            >
                              <PlayerSummary
                                player={occupant.player || { id: occupant.playerId || occupant.player_id }}
                              />
                            </div>
                          ) : (
                            <span className="text-textSecondary px-2 py-2">-</span>
                          )}
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
                <div
                  className={`rounded-lg border p-3 space-y-2 transition dark:bg-darksurface/60 ${
                    dragOverRecruitBoard === board.id
                      ? "border-burnt bg-burnt/10 scale-[1.01]"
                      : "border-border bg-surface/60 dark:border-darkborder"
                  }`}
                  onDragOver={(e) => {
                    e.preventDefault();
                    setDragOverRecruitBoard(board.id);
                  }}
                  onDragEnter={(e) => {
                    e.preventDefault();
                    setDragOverRecruitBoard(board.id);
                  }}
                  onDragLeave={() => setDragOverRecruitBoard(null)}
                  onDrop={(e) => {
                    e.preventDefault();
                    draggingPlayer && moveToRecruit(board.id, draggingPlayer.playerId);
                  }}
                >
                <div className="flex items-center justify-between">
                   <p className="text-sm font-semibold text-textSecondary">Board</p>
                  <button
                    type="button"
                    onClick={() => setShowFormBoardId((prev) => (prev === board.id ? null : board.id))}
                    className="text-sm font-semibold text-burnt hover:underline"
                  >
                    {showFormBoardId === board.id ? "Close" : "+ Add"}
                  </button>
                </div>
                {showFormBoardId === board.id && (
                <div className="flex flex-col gap-2">
                  <input
                    placeholder="Name"
                    value={newPlayer.name}
                    onChange={(e) => setNewPlayer((p) => ({ ...p, name: e.target.value }))}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  />
                  <div className="flex items-center gap-1 text-burnt">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <button
                        key={star}
                        type="button"
                        aria-label={`${star} star${star > 1 ? "s" : ""}`}
                        onClick={() => setNewPlayer((p) => ({ ...p, starRating: star }))}
                        className="focus:outline-none"
                      >
                        <span
                          className={`text-lg ${
                            ((newPlayer.starRating ?? 3)) >= star ? "text-burnt" : "text-border opacity-60"
                          }`}
                        >
                          ★
                        </span>
                      </button>
                    ))}
                  </div>
                  <select
                    value={newPlayer.archetype}
                    onChange={(e) => setNewPlayer((p) => ({ ...p, archetype: e.target.value }))}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  >
                    <option value="">Archetype</option>
                    {Object.entries(archetypeGroups).map(([group, items]) => (
                      <optgroup key={group} label={group}>
                        {Object.entries(items).map(([label, code]) => (
                          <option key={label} value={label}>{`${label} - ${code}`}</option>
                        ))}
                      </optgroup>
                    ))}
                  </select>
                  <input
                    type="number"
                    placeholder="Overall"
                    value={newPlayer.overall}
                    onChange={(e) => setNewPlayer((p) => ({ ...p, overall: e.target.value }))}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  />
                  <select
                    value={newPlayer.classYear}
                    onChange={(e) => setNewPlayer((p) => ({ ...p, classYear: e.target.value }))}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  >
                    <option value="">Class</option>
                    {classYears.map((c) => (
                      <option key={c || "blank"} value={c}>
                        {c || "—"}
                      </option>
                    ))}
                  </select>
                  <div className="space-y-1">
                    <span className="text-sm font-medium text-textSecondary dark:text-white/80">Dev Trait</span>
                    <DevTraitButtons
                      value={newPlayer.devTrait}
                      onChange={(val) => setNewPlayer((p) => ({ ...p, devTrait: val }))}
                    />
                  </div>
                  <button
                    type="button"
                    onClick={() => handleCreatePlayer(board.id)}
                    disabled={busyBoardId === board.id || !newPlayer.name.trim()}
                    className="md:col-span-3 rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-70"
                  >
                    Add
                  </button>
                </div>
                )}
                {recruits.length > 0 && (
                  <ul className="space-y-2">
                    {recruits.map((p) => (
                      <li
                        key={p.id}
                        className="flex items-center justify-between rounded-md border border-border bg-white/80 text-sm dark:border-darkborder dark:bg-darksurface/80 cursor-grab active:cursor-grabbing"
                        draggable
                        onDragStart={() => onPlayerDragStart(p.id, board.id)}
                        onDragEnd={onPlayerDragEnd}
                        onClick={() => openEdit(p, board.id, null)}
                      >
                        <PlayerSummary player={p} />
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
      <PlayerEditModal
        editing={editing}
        onClose={closeEdit}
        onSaveDraft={(draft) => setEditing(draft)}
        onSave={() => saveEdit()}
        onDelete={deleteEditPlayer}
        busy={busyBoardId === "edit"}
      />
    </div>
  );
}

export default SquadBoardPage;

// Modal for editing a player
function PlayerEditModal({ editing, onClose, onSaveDraft, onSave, onDelete, busy }) {
  if (!editing) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-lg rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <h3 className="font-varsity text-xl uppercase tracking-[0.06em]">Edit Player</h3>
            <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
              <div className="flex items-center gap-1 text-burnt">
                {[1, 2, 3, 4, 5].map((star) => (
                  <button
                    key={star}
                    type="button"
                    aria-label={`${star} star${star > 1 ? "s" : ""}`}
                    onClick={() => onSaveDraft({ ...editing, starRating: star })}
                    className="focus:outline-none"
                  >
                    <span
                      className={`text-lg ${
                        (+editing.starRating || 3) >= star ? "text-burnt" : "text-border opacity-60"
                      }`}
                    >
                      ★
                    </span>
                  </button>
                ))}
              </div>
            </label>
          </div>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>
        <div className="mt-4 space-y-3">
          <div className="grid gap-3 md:grid-cols-2">
            <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
              <span>Name</span>
              <input
                value={editing.name}
                onChange={(e) => onSaveDraft({ ...editing, name: e.target.value })}
                placeholder="Name"
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              />
            </label>
            <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
              <span>Class</span>
              <select
                value={editing.classYear}
                onChange={(e) => onSaveDraft({ ...editing, classYear: e.target.value })}
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              >
                <option value="">-</option>
                {classYears.map((c) => (
                  <option key={c || "blank"} value={c}>
                    {c || "—"}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
              <span>Overall</span>
              <input
                type="number"
                value={editing.overall}
                onChange={(e) => onSaveDraft({ ...editing, overall: e.target.value })}
                placeholder="OVR"
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              />
            </label>
            <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
              <span>Archetype</span>
              <select
                value={editing.archetype}
                onChange={(e) => onSaveDraft({ ...editing, archetype: e.target.value })}
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              >
                <option value="">—</option>
                {Object.entries(archetypeGroups).map(([group, items]) => (
                  <optgroup key={group} label={group}>
                    {Object.entries(items).map(([label, code]) => (
                      <option key={label} value={label}>{`${label} - ${code}`}</option>
                    ))}
                  </optgroup>
                ))}
              </select>
            </label>
          </div>
          <div className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Dev Trait</span>
            <DevTraitButtons
              value={editing.devTrait}
              onChange={(val) => onSaveDraft({ ...editing, devTrait: val })}
            />
          </div>
        </div>
        <div className="mt-4 flex justify-between items-end">
          <div className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80 w-full">
            <span>Remove from board</span>
            <StatusButtons
              value={editing.status}
              onChange={(val) => onSaveDraft({ ...editing, status: val })}
            />
          </div>
        </div>
        <div className="mt-4 flex justify-end items-end">
          <div className="flex gap-1">
            <button
              onClick={() => {
                if (busy) return;
                const message = "Delete this player completely? This action cannot be undone. If you want to save his name, mark the player as graduated or departed. instead";
                if (window.confirm(message)) onDelete();
              }}
              disabled={busy}
              data-confirm="Delete this player completely? This action cannot be undone. If you want to save his name, mark the player as graduated or departed instead."
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-danger/10 disabled:opacity-60"
            >
              <i className="fa-solid fa-trash-can"></i>
            </button>
            <button
              onClick={onClose}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              onClick={() => onSave(editing, false)}
              disabled={busy}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
