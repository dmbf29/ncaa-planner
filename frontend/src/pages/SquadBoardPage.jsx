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
  createNeed,
  updateNeed,
  deleteNeed,
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

const defaultAttributeOptions = [
  "speed",
  "strength",
  "awareness",
  "agility",
  "acceleration",
  "catching",
  "route_running",
  "release",
  "throw_power",
  "throw_accuracy",
  "carrying",
  "blocking",
  "pass_block",
  "run_block",
  "tackle",
  "pursuit",
  "play_recognition",
  "man_coverage",
  "zone_coverage",
  "press",
  "kick_power",
  "kick_accuracy",
];

const normalizeAttrKey = (attr = "") =>
  attr
    .trim()
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[\s-]+/g, "_")
    .toLowerCase();
const toCamelFromSnake = (str = "") => str.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());
const humanizeAttr = (attr = "") =>
  attr
    .replace(/_/g, " ")
    .replace(/\b\w/g, (c) => c.toUpperCase());

const getAttrValueFromMap = (map = {}, key = "") => {
  const normalized = normalizeAttrKey(key);
  const camel = toCamelFromSnake(normalized);
  return map?.[normalized] ?? map?.[camel] ?? map?.[key];
};

const sanitizeAttributeMap = (map = {}) => {
  const cleaned = {};
  Object.entries(map || {}).forEach(([k, v]) => {
    const key = normalizeAttrKey(k);
    if (!key) return;
    cleaned[key] = v;
  });
  return cleaned;
};

const buildAttributePayload = (map = {}) => {
  const payload = {};
  Object.entries(map || {}).forEach(([k, v]) => {
    const key = normalizeAttrKey(k);
    if (!key) return;
    const value = typeof v === "string" ? v.trim() : v;
    if (value === "" || value === null || value === undefined) return;
    const numeric = Number(value);
    payload[key] = Number.isNaN(numeric) ? value : numeric;
  });
  return payload;
};

const getBoardHighlightedAttributes = (board) =>
  board?.highlightedAttributes || board?.highlighted_attributes || [];

const recruitStatusOptions = [
  { value: "gem", label: "Gem", tone: "success" },
  { value: "bust", label: "Bust", tone: "danger" },
];

const getRecruitStatus = (player) => player?.recruitStatus ?? player?.recruit_status ?? "normal";

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
            className={`flex items-center gap-2 overflow-hidden text-ellipsis whitespace-nowrap rounded-md border px-1 sm:px-3 py-1 sm:py-2 text-xs transition ${
              selected
                ? "bg-success text-white border-success shadow-card"
                : "border-border text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            }`}
          >
            <i
              className={`fa-solid ${meta.icon} ${
                selected ? "text-white" : meta.color
              }`}
            />
            <span className="min-w-0 truncate">{option.label}</span>
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
            onClick={() => onChange(option.value)}
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

function RecruitStatusBadge({ status, showLabel = false }) {
  if (status !== "gem" && status !== "bust") return null;
  const isGem = status === "gem";
  const toneClass = isGem ? "text-success" : "text-danger";
  return (
    <span className={`inline-flex items-center gap-1 ${toneClass}`} title={isGem ? "Gem" : "Bust"}>
      <span className="relative inline-flex h-5 w-5 items-center justify-center">
        <i className={`fa-solid fa-gem ${isGem ? "text-success" : "text-danger/60"}`} aria-hidden="true" />
        {!isGem && (
          <span className="pointer-events-none absolute inset-0 flex items-center justify-center text-[11px] font-black leading-none text-danger">
            ✕
          </span>
        )}
      </span>
      {showLabel ? <span className="text-xs font-semibold leading-none">{isGem ? "Gem" : "Bust"}</span> : null}
    </span>
  );
}

function RecruitStatusToggle({ value, onChange, compact = false }) {
  const selected = value === "gem" || value === "bust" ? value : "";
  const containerClass = compact ? "flex items-center gap-1" : "flex items-center gap-2";
  const paddingClass = compact ? "px-1 py-1" : "px-2 py-1";
  return (
    <div className={containerClass}>
      {recruitStatusOptions.map((option) => {
        const isSelected = selected === option.value;
        const tone =
          option.tone === "success"
            ? "border-success bg-success/10 text-success"
            : "border-danger bg-danger/10 text-danger";
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => onChange(isSelected ? "" : option.value)}
            className={`flex items-center gap-1 rounded-md border ${paddingClass} text-xs font-semibold transition ${
              isSelected
                ? tone
                : "border-border text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            }`}
            aria-pressed={isSelected}
          >
            <RecruitStatusBadge status={option.value} />
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
    recruitStatus: "",
  });
  const [draggingCardId, setDraggingCardId] = useState(null);
  const [draggingPlayer, setDraggingPlayer] = useState(null);
  const [editing, setEditing] = useState(null);
  const [dragOverSlot, setDragOverSlot] = useState(null); // { boardId, slotNum }
  const [dragOverRecruitBoard, setDragOverRecruitBoard] = useState(null); // boardId
  const [previewOrder, setPreviewOrder] = useState({ boardId: null, order: [] }); // local visual reorder
  const [newPlayerAttributes, setNewPlayerAttributes] = useState({});
  const [needDraft, setNeedDraft] = useState({
    boardId: null,
    needId: null,
    departingPlayerId: "",
    replacementPlayerId: "",
    slotNumber: "",
    resolved: false,
  });
  const [needBusy, setNeedBusy] = useState(false);
  const [needMessage, setNeedMessage] = useState("");
  const [attributeModal, setAttributeModal] = useState({ boardId: null, selected: [], custom: "" });
  const cardRefs = useRef({});

  useEffect(() => {
    const load = async () => {
      try {
        const [teamData, boardsData, playersData] = await Promise.all([
          fetchTeam(id),
          fetchSquadBoards(id),
          fetchPlayers(id, { status: ["recruit", "rostered"] }),
        ]);
        setTeam(teamData);
        setBoards(dedupeBoards(boardsData));
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

  const attributeBoard = useMemo(
    () => boards.find((b) => String(b.id) === String(attributeModal.boardId)),
    [attributeModal.boardId, boards],
  );

  const getRosterSlots = (board) =>
    [...((board?.rosterSlots || board?.roster_slots || []))].sort(
      (a, b) => (a.slotNumber || a.slot_number || 0) - (b.slotNumber || b.slot_number || 0),
    );

  const getOrderedSlotsForBoard = (board) => {
    const slots = getRosterSlots(board);
    const slotCount = board.slotsCount || board.slots_count || slots.length || 0;
    const playerMap = new Map(
      slots.map((rs) => [rs.playerId || rs.player_id, rs]),
    );
    const order =
      previewOrder.boardId === board.id && (previewOrder.order || []).length > 0
        ? previewOrder.order
        : slots.map((rs) => rs.playerId || rs.player_id);

    const orderedPlayers = order.map((pid) => playerMap.get(pid)).filter(Boolean);
    const slotsArray = Array.from({ length: slotCount }).map((_, idx) => {
      const occupant = orderedPlayers[idx] || null;
      return { slotNum: idx + 1, occupant };
    });
    return slotsArray;
  };

  const dedupeBoards = (list) => Array.from(new Map((list || []).map((b) => [b.id, b])).values());

  const loadAllBoards = async () => {
    const boardsData = await fetchSquadBoards(id);
    return dedupeBoards(boardsData);
  };

  const getPlayerAttributes = (player) =>
    sanitizeAttributeMap(player?.attributes || player?.attributeValues || {});

  const handleNewPlayerAttrChange = (boardId, attr, value) => {
    setNewPlayerAttributes((prev) => ({
      ...prev,
      [boardId]: { ...(prev[boardId] || {}), [attr]: value },
    }));
  };

  const openAttributeModal = (board) => {
    setAttributeModal({
      boardId: board?.id || null,
      selected: getBoardHighlightedAttributes(board),
      custom: "",
    });
  };

  const closeAttributeModal = () => setAttributeModal({ boardId: null, selected: [], custom: "" });

  const toggleAttributeSelection = (attr) => {
    const normalized = normalizeAttrKey(attr);
    if (!normalized) return;
    setAttributeModal((prev) => {
      const selected = new Set(prev.selected || []);
      if (selected.has(normalized)) {
        selected.delete(normalized);
      } else {
        selected.add(normalized);
      }
      return { ...prev, selected: Array.from(selected) };
    });
  };

  const addCustomAttribute = () => {
    const normalized = normalizeAttrKey(attributeModal.custom || "");
    if (!normalized) return;
    setAttributeModal((prev) => ({
      boardId: prev.boardId,
      custom: "",
      selected: Array.from(new Set([...(prev.selected || []), normalized])),
    }));
  };

  const setAttributeModalCustom = (value) => {
    setAttributeModal((prev) => ({ ...prev, custom: value }));
  };

  const saveHighlightedAttributes = async () => {
    if (!attributeModal.boardId) return;
    const uniqueAttrs = Array.from(new Set((attributeModal.selected || []).map(normalizeAttrKey))).filter(Boolean);
    setBusyBoardId(attributeModal.boardId);
    try {
      await updatePositionBoard(id, attributeModal.boardId, { highlighted_attributes: uniqueAttrs });
      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
      closeAttributeModal();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
    }
  };

  const clearPreview = () => setPreviewOrder({ boardId: null, order: [] });

  const findPlayerById = (playerId) => players.find((p) => String(p.id) === String(playerId));

  const setEditingDraft = (updater) => {
    setEditing((prev) => {
      const next = typeof updater === "function" ? updater(prev) : updater;
      if (!next) return next;
      const nextDraft = { ...next };
      if (nextDraft.flagged === undefined) {
        nextDraft.flagged = !!prev?.flagged;
      }
      nextDraft.flagged = !!nextDraft.flagged;
      nextDraft.attributeValues = sanitizeAttributeMap(nextDraft.attributeValues || prev?.attributeValues || {});

      const targetBoardId =
        nextDraft.boardSelection || nextDraft.boardId || nextDraft.positionBoardId || prev?.boardId || null;
      const targetBoard = boards.find((b) => String(b.id) === String(targetBoardId));
      nextDraft.highlightedAttributes = getBoardHighlightedAttributes(targetBoard);
      return nextDraft;
    });
  };

  const updatePreviewOrder = (boardId, dragPlayerId, targetPlayerId) => {
    if (!dragPlayerId || !targetPlayerId || dragPlayerId === targetPlayerId) return;
    const board = sortedBoards.find((b) => b.id === boardId);
    if (!board) return;
    const baseSlots = getRosterSlots(board);
    const currentOrder =
      previewOrder.boardId === boardId && previewOrder.order.length > 0
        ? [...previewOrder.order]
        : baseSlots.map((rs) => rs.playerId || rs.player_id);

    const fromIdx = currentOrder.indexOf(dragPlayerId);
    const toIdx = currentOrder.indexOf(targetPlayerId);
    if (fromIdx === -1 || toIdx === -1 || fromIdx === toIdx) return;

    const nextOrder = [...currentOrder];
    nextOrder.splice(fromIdx, 1);
    nextOrder.splice(toIdx, 0, dragPlayerId);
    setPreviewOrder({ boardId, order: nextOrder });
  };

  const applyRosterOrder = async (board, desiredOrder, existingSlots = null) => {
    if (!board || !desiredOrder || desiredOrder.length === 0) return;
    const safeOrder = desiredOrder.filter(Boolean);
    if (safeOrder.length === 0) return;

    const slots = existingSlots ? [...existingSlots] : getRosterSlots(board);
    const idToSlot = new Map(
      slots.map((rs) => [rs.playerId || rs.player_id, rs.id]).filter(([pid]) => pid),
    );

    // Use a fixed high-but-safe offset to avoid collisions while staying in 32-bit int range.
    const tempBase = 1_000_000;

    // Create any missing roster slots for players not yet on the board.
    for (let idx = 0; idx < safeOrder.length; idx += 1) {
      const pid = safeOrder[idx];
      if (!pid || idToSlot.has(pid)) continue;
      const slot = await createRosterSlot(board.id, { player_id: pid, slot_number: tempBase + idx });
      if (slot?.id) {
        idToSlot.set(pid, slot.id);
      }
    }

    // Phase 1: move everyone to unique temporary slots (sequential to avoid unique constraint races).
    for (let idx = 0; idx < safeOrder.length; idx += 1) {
      const pid = safeOrder[idx];
      const slotId = idToSlot.get(pid);
      if (!slotId) continue;
      await updateRosterSlot(board.id, slotId, { slot_number: tempBase + idx });
    }

    // Phase 2: finalize the target ordering (1-based).
    for (let idx = 0; idx < safeOrder.length; idx += 1) {
      const pid = safeOrder[idx];
      const slotId = idToSlot.get(pid);
      if (!slotId) continue;
      await updateRosterSlot(board.id, slotId, { slot_number: idx + 1 });
    }
  };

  const reorderWithinBoard = async (boardId, playerId, targetSlot) => {
    const board = sortedBoards.find((b) => b.id === boardId);
    if (!board) return;
    const slots = getRosterSlots(board);
    const currentIdx = slots.findIndex((rs) => (rs.playerId || rs.player_id) === playerId);
    if (currentIdx === -1) return;

    const order = slots.map((rs) => rs.playerId || rs.player_id);
    const clampedIdx = Math.max(0, Math.min(targetSlot - 1, order.length - 1));
    const nextOrder = [...order];
    nextOrder.splice(currentIdx, 1);
    nextOrder.splice(clampedIdx, 0, playerId);

    setBusyBoardId(boardId);
    try {
      await applyRosterOrder(board, nextOrder, slots);
      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
      setDraggingPlayer(null);
      clearPreview();
    }
  };

  const movePlayerToBoard = async (boardId, playerId, targetSlot) => {
    const targetBoard = sortedBoards.find((b) => b.id === boardId);
    if (!targetBoard) return;
    const targetSlots = getRosterSlots(targetBoard);
    const alreadyOnBoard = targetSlots.some((rs) => (rs.playerId || rs.player_id) === playerId);
    const slotLimit = targetBoard.slotsCount || targetBoard.slots_count || 0;
    if (!alreadyOnBoard && slotLimit && targetSlots.length >= slotLimit) {
      setError("This board is full. Remove a player first.");
      return;
    }

    setBusyBoardId(boardId);
    try {
      if (draggingPlayer?.fromBoardId && draggingPlayer.fromBoardId !== boardId) {
        const sourceBoard = sortedBoards.find((b) => b.id === draggingPlayer.fromBoardId);
        if (sourceBoard) {
          const sourceSlots = getRosterSlots(sourceBoard);
          const sourceSlot = sourceSlots.find((rs) => (rs.playerId || rs.player_id) === playerId);
          if (sourceSlot) {
            await deleteRosterSlot(sourceBoard.id, sourceSlot.id);
            const remainingOrder = sourceSlots
              .filter((rs) => (rs.playerId || rs.player_id) !== playerId)
              .map((rs) => rs.playerId || rs.player_id);
            if (remainingOrder.length > 0) {
              await applyRosterOrder(sourceBoard, remainingOrder, sourceSlots.filter((rs) => rs.id !== sourceSlot.id));
            }
          }
        }
      }

      const targetOrder = targetSlots
        .map((rs) => rs.playerId || rs.player_id)
        .filter((pid) => pid !== playerId);
      const insertIdx = Math.max(0, Math.min(targetSlot - 1, targetOrder.length));
      targetOrder.splice(insertIdx, 0, playerId);

      await applyRosterOrder(targetBoard, targetOrder, targetSlots);
      await updatePlayer(id, playerId, { status: "rostered", position_board_id: boardId });

      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
      const playersData = await fetchPlayers(id, { status: ["recruit", "rostered"] });
      setPlayers(playersData);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
      setDraggingPlayer(null);
      setDragOverSlot(null);
      setDragOverRecruitBoard(null);
      clearPreview();
    }
  };

  const startPlayerDrag = (e, playerId, fromBoardId) => {
    setDraggingPlayer({ playerId, fromBoardId });
    if (e?.dataTransfer) {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(playerId));
    }
  };

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
      JR: "text-[#c99b2b]",
      "JR(RS)": "text-[#c99b2b]",
      SR: "text-[#991B1B]",
      "SR(RS)": "text-[#991B1B]",
    };
    return map[cls] || "text-textSecondary";
  };

  const classPillClass = (cls) => {
    const map = {
      FR: { bg: "bg-[#4C7A4F1A]", border: "border-[#4C7A4F33]" },
      "FR(RS)": { bg: "bg-[#5C6F4E1A]", border: "border-[#5C6F4E33]" },
      SO: { bg: "bg-[#7595ba1a]", border: "border-[#7595ba33]" },
      "SO(RS)": { bg: "bg-[#7595ba1a]", border: "border-[#7595ba33]" },
      JR: { bg: "bg-[#c99b2b1a]", border: "border-[#c99b2b33]" },
      "JR(RS)": { bg: "bg-[#c99b2b1a]", border: "border-[#c99b2b33]" },
      SR: { bg: "bg-[#991B1B1a]", border: "border-[#991B1B33]" },
      "SR(RS)": { bg: "bg-[#991B1B1a]", border: "border-[#991B1B33]" },
    };
    const palette = map[cls];
    const base =
      "inline-flex items-center justify-center px-1.5 py-[2px] rounded-full text-[11px] font-semibold border max-w-[72px] w-full";
    if (!palette) {
      return `${base} text-textSecondary bg-textSecondary/10 border-textSecondary/20`;
    }
    return `${base} ${classColor(cls)} ${palette.bg} ${palette.border}`;
  };

  const PlayerSummary = ({ player, highlightedAttributes = [], attributes = {}, showRecruitStatus = true }) => {
    if (!player) return null;
    const star = player.starRating ?? player.star_rating;
    const classYear = player.classYear ?? player.class_year;
    const archetype = archetypeShort(player.archetype);
    const overall = player.overall;
    const trait = player.devTrait ?? player.dev_trait;
    const recruitStatus = showRecruitStatus ? getRecruitStatus(player) : "normal";
    const isGem = recruitStatus === "gem";
    const isBust = recruitStatus === "bust";
    const isFlagged = !!player.flagged;
    const attrValues = Object.keys(attributes || {}).length > 0 ? attributes : getPlayerAttributes(player);

    const AttributeCell = ({ value }) => (
      <div className="flex flex-col items-center min-w-0 overflow-hidden">
        <span className="text-xs text-textSecondary font-medium min-h-[1.1rem] flex items-center justify-center max-w-full w-full">
          {value ?? <span className="text-border">—</span>}
        </span>
      </div>
    );

    return (
      <div className="flex flex-col w-full gap-1">
        <div className="flex items-center justify-between gap-2 px-2 pt-2">
          <div className="flex items-center gap-2 min-w-0">
            <span className="text-textPrimary dark:text-white font-semibold truncate">
              {player.name || player.id}
            </span>
            {isFlagged ? <i className="fa-solid fa-flag text-danger text-xs" title="Flagged"></i> : null}
          </div>
          <div className="flex flex-wrap items-center gap-0">
            {highlightedAttributes.length > 0 && (
              <div className="flex flex-wrap items-center gap-1">
                {highlightedAttributes.map((attr) => {
                  const val = getAttrValueFromMap(attrValues, attr);
                  return (
                    <span
                      key={attr}
                      className="flex flex-col items-center gap-0 rounded-full bg-white/70 px-2 py-[3px] text-[11px] font-semibold uppercase text-textSecondary dark:border-darkborder dark:bg-white/10"
                    >
                      <span className="text-textSecondary dark:text-white">{val ?? "—"}</span>
                    </span>
                  );
                })}
              </div>
            )}
            {overall ? <OverallPill value={overall} /> : null}
          </div>
        </div>
        <div className="grid grid-cols-4 gap-1 px-1 bg-textSecondary/5 py-1 items-center">
          <AttributeCell
            value={
              classYear ? <span className={classPillClass(classYear)}>{classYear}</span> : null
            }
          />
          <AttributeCell
            value={
              star || isBust ? (
                <span className="flex items-center">
                  {star ? (
                    <>
                      <span
                        className={
                          isGem
                            ? "text-success"
                            : isBust
                              ? "text-danger"
                              : "text-textSecondary/80 dark:text-white"
                        }
                      >
                        {star}
                      </span>
                      <span
                        className={
                          isGem
                            ? "text-success"
                            : isBust
                              ? "text-danger"
                              : "text-textSecondary/50"
                        }
                      >
                        ★
                      </span>
                    </>
                  ) : (
                    <span
                      className={
                        isGem
                          ? "text-success text-xs font-semibold"
                          : isBust
                            ? "text-danger text-xs font-semibold"
                            : "text-textSecondary/80"
                      }
                    >
                      {isGem ? "Gem" : isBust ? "Bust" : ""}
                    </span>
                  )}
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

  const handleCreatePlayer = async (boardId) => {
    if (!newPlayer.name.trim()) return;
    setBusyBoardId(boardId);
    try {
      const attrPayload = buildAttributePayload(newPlayerAttributes[boardId]);
      await createPlayer(id, {
        name: newPlayer.name,
        star_rating: newPlayer.starRating || null,
        archetype: newPlayer.archetype || null,
        overall: newPlayer.overall || null,
        class_year: newPlayer.classYear || null,
        dev_trait: newPlayer.devTrait || null,
        recruit_status: newPlayer.recruitStatus || "normal",
        status: "recruit",
        position_board_id: boardId,
        attribute_values: attrPayload,
      });
      setNewPlayer({ name: "", starRating: "", archetype: "", overall: "", classYear: "", devTrait: "", recruitStatus: "" });
      setNewPlayerAttributes((prev) => ({ ...prev, [boardId]: {} }));
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
      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
    } catch (err) {
      setError(err.message);
    } finally {
      setBusyBoardId(null);
    }
  };

  const onPlayerDragEnd = () => {
    setDraggingPlayer(null);
    clearPreview();
  };

  const onSlotDrop = (boardId, slotNum) => {
    if (draggingPlayer?.playerId) {
      const targetBoard = sortedBoards.find((b) => b.id === boardId);
      const targetSlots = targetBoard ? getRosterSlots(targetBoard) : [];
      const alreadyOnTarget = targetSlots.some((rs) => (rs.playerId || rs.player_id) === draggingPlayer.playerId);
      if (alreadyOnTarget) {
        // Use preview order to pick intended position if available
        const previewIdx =
          previewOrder.boardId === boardId
            ? previewOrder.order.indexOf(draggingPlayer.playerId)
            : -1;
        const targetPosition = previewIdx >= 0 ? previewIdx + 1 : slotNum;
        reorderWithinBoard(boardId, draggingPlayer.playerId, targetPosition);
      } else {
        movePlayerToBoard(boardId, draggingPlayer.playerId, slotNum);
      }
    }
    setDragOverSlot(null);
    clearPreview();
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
      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
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
    const boardOptions = boards
      .map((b) => {
        const squadName =
          team?.squads?.find((sq) => String(sq.id) === String(b.squadId || b.squad_id))?.name || "Squad";
        return {
          id: b.id,
          sort: b.sortOrder || b.sort_order || 0,
          squadId: b.squadId || b.squad_id,
          squadName,
          label: `${squadName} • ${b.name}`,
        };
      })
      .sort((a, b) => {
        const squadCompare = Number(a.squadId || 0) - Number(b.squadId || 0);
        if (squadCompare !== 0) return squadCompare;
        const sortCompare = (a.sort || 0) - (b.sort || 0);
        if (sortCompare !== 0) return sortCompare;
        return (a.label || "").localeCompare(b.label || "", undefined, { sensitivity: "base" });
      });

    const boardForPlayer =
      boards.find((b) => b.id === boardId) ||
      boards.find((b) => String(b.id) === String(player.positionBoardId || player.position_board_id));
    const attributeValues = getPlayerAttributes(player);
    const highlightedAttributes = getBoardHighlightedAttributes(boardForPlayer);

    setEditingDraft({
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
      recruitStatus: getRecruitStatus(player),
      flagged: !!player.flagged,
      boardSelection: boardId || player.positionBoardId || player.position_board_id || "",
      boardOptions,
      attributeValues,
      highlightedAttributes,
    });
  };

  const closeEdit = () => setEditing(null);

  const saveEdit = async (draft = null) => {
    const payload = draft || editing;
    if (!payload) return;
    setBusyBoardId("edit");
    try {
      const isAlumni = payload.status === "graduated" || payload.status === "departed";
      const targetBoardId = payload.boardSelection || payload.boardId || null;
      const boardChanged = targetBoardId && String(targetBoardId) !== String(payload.boardId || "");
      const sourceBoard = boards.find((b) => b.id === payload.boardId);
      const sourceSlot = sourceBoard?.rosterSlots?.find((rs) => (rs.playerId || rs.player_id) === payload.id);
      const shouldRemoveSlot = isAlumni || boardChanged || payload.status === "recruit";

      const attributeValuesPayload = buildAttributePayload(payload.attributeValues);

      await updatePlayer(id, payload.id, {
        name: payload.name,
        class_year: payload.classYear,
        dev_trait: payload.devTrait,
        archetype: payload.archetype,
        overall: payload.overall,
        star_rating: payload.starRating,
        status: isAlumni ? payload.status : payload.status === "rostered" && !boardChanged ? "rostered" : "recruit",
        recruit_status: payload.recruitStatus || "normal",
        position_board_id: isAlumni ? null : targetBoardId || null,
        attribute_values: attributeValuesPayload,
        flagged: !!payload.flagged,
      });
      if (shouldRemoveSlot && sourceSlot) {
        await deleteRosterSlot(sourceBoard.id, sourceSlot.id);
      }
      const boardsData = await loadAllBoards();
      setBoards(dedupeBoards(boardsData));
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
      const boardsData = await loadAllBoards();
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

  const allNeeds = useMemo(() => {
    const byKey = new Map();
    boards.forEach((b) => {
      (b.needs || []).forEach((n) => {
        const dep = n.departingPlayerId || n.departing_player_id || "";
        const slotNum = n.slotNumber || n.slot_number || "";
        const rep = n.replacementPlayerId || n.replacement_player_id || "";
        const key = n.id ? `id:${n.id}` : `combo:${b.id}:${dep}:${slotNum}:${rep}`;
        if (byKey.has(key)) return;
        byKey.set(key, {
          ...n,
          boardName: b.name,
          boardId: b.id,
        });
      });
    });
    return Array.from(byKey.values());
  }, [boards]);

  const handleDeleteNeed = async (boardId, needId) => {
    setNeedBusy(true);
    setNeedMessage("");
    try {
      await deleteNeed(boardId, needId);
      const boardsData = await loadAllBoards();
      setBoards(boardsData);
      closeNeedModal();
    } catch (err) {
      setError(err.message);
    } finally {
      setNeedBusy(false);
    }
  };

  const closeNeedModal = () => {
    setNeedDraft({
      boardId: null,
      needId: null,
      departingPlayerId: "",
      replacementPlayerId: "",
      slotNumber: "",
      resolved: false,
    });
    setNeedMessage("");
    setNeedBusy(false);
  };

  const handleSaveNeed = async () => {
    if (!needDraft.boardId) return;
    if (!needDraft.departingPlayerId && !needDraft.slotNumber) {
      setNeedMessage("Pick a departing player or an empty slot.");
      return;
    }
    setNeedBusy(true);
    setNeedMessage("");
    try {
      const payload = {
        departing_player_id: needDraft.departingPlayerId || null,
        slot_number: needDraft.slotNumber ? Number(needDraft.slotNumber) : null,
        replacement_player_id: needDraft.replacementPlayerId || null,
        resolved: !!needDraft.resolved,
      };
      if (needDraft.needId) {
        await updateNeed(needDraft.boardId, needDraft.needId, payload);
      } else {
        await createNeed(needDraft.boardId, payload);
      }
      const boardsData = await loadAllBoards();
      setBoards(boardsData);
      closeNeedModal();
    } catch (err) {
      setError(err.message);
    } finally {
      setNeedBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title={team ? `${team.name}` : "Loading..."}
        eyebrow="Roster Planner"
        actions={
          squadList.length > 0 && (
            <div className="flex flex-wrap gap-2 mt-2 sm:mt-0">
              {squadList.map((sq) => (
                <Link
                  key={sq.id}
                  to={`/teams/${id}/squads/${sq.id}`}
                  className={`rounded-md px-3 py-2 text-sm transition font-varsity uppercase ${
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
                className="font-varsity uppercase rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              >
                Alumni
              </Link>
            </div>
          )
        }
      />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading squad...</p>}
      {allNeeds.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-semibold text-textSecondary uppercase tracking-[0.12em]">
            <span className="font-crayon">Planned Replacements</span> ({allNeeds.length})
          </h3>
          <div className="flex flex-wrap gap-1">
            {allNeeds.map((need) => {
              const departing =
                need.departingPlayer?.name ||
                (need.departing_player?.name) ||
                (need.slotNumber || need.slot_number ? `Empty Slot` : "Departing?");
              const replacement =
                need.replacementPlayer?.name ||
                (need.replacement_player?.name) ||
                "TBD";
              return (
                <button
                  key={need.id}
                  type="button"
                  onClick={() => {
                    setNeedDraft({
                      boardId: need.boardId,
                      needId: need.id,
                      departingPlayerId: need.departingPlayerId || need.departing_player_id || "",
                      replacementPlayerId: need.replacementPlayerId || need.replacement_player_id || "",
                      slotNumber: need.slotNumber || need.slot_number || "",
                      resolved: !!need.resolved,
                    });
                    setNeedMessage("");
                    setNeedBusy(false);
                  }}
                  className={`inline-flex items-center gap-1 rounded-full border px-2 bg-white py-1 text-xs font-semibold text-textSecondary shadow-sm ${
                    need.resolved ? "border-success/70" : "border-border dark:border-darkborder dark:bg-darksurface"
                  }`}
                >
                  <span className="text-burnt">{need.boardName}</span>
                  <span className="text-textPrimary">{departing}</span>
                  <span className="text-textSecondary/50">→</span>
                  <span className="text-textPrimary">{replacement}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}
      <div className="grid gap-2 sm:grid-cols-1 md:grid-cols-2 xl:grid-cols-3">
        {sortedBoards.map((board) => {
          const rosterSlots = board.rosterSlots || board.roster_slots || [];
          const highlightAttrs = getBoardHighlightedAttributes(board);
          const assignedIds = new Set(
            rosterSlots.map((rs) => rs.playerId || rs.player_id).filter(Boolean),
          );
          const slotsArray = getOrderedSlotsForBoard(board);
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
              className={`relative overflow-hidden bg-gradient-to-br from-[#fdfdfb] via-[#f9f7f3] to-[#f9f8f5] shadow-lg dark:from-[#1a1c1d] dark:via-[#151617] dark:to-[#111213] ${
                draggingCardId === board.id ? "opacity-70" : ""
              }`}
            >
              <div
                className="pointer-events-none absolute -top-5 left-1/2 z-0 flex -translate-x-1/2 flex-col items-center gap-1"
                aria-hidden="true"
              >
                <div className="h-6 w-24 rounded-b-2xl border border-[#d5cdbf] bg-[#f6f2ea] shadow-md dark:border-darkborder dark:bg-[#26282a]" />
                <div className="h-3 w-12 rounded-b-md border border-[#dcd5c9] bg-[#ebe6dc] shadow-sm dark:border-darkborder dark:bg-[#1d1f21]" />
              </div>
              <div
                className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_15%_10%,rgba(255,255,255,0.32),transparent_35%),radial-gradient(circle_at_85%_12%,rgba(255,255,255,0.18),transparent_30%)] mix-blend-screen dark:mix-blend-normal"
                aria-hidden="true"
              />
              <div
                className="pointer-events-none absolute top-3 left-5 h-3 w-3 rounded-full bg-[#e8e1d5] shadow-inner ring-1 ring-[#d8cfc1]/70 dark:bg-[#2b2d2f] dark:ring-darkborder/70"
                aria-hidden="true"
              />
              <div
                className="pointer-events-none absolute top-3 right-5 h-3 w-3 rounded-full bg-[#e8e1d5] shadow-inner ring-1 ring-[#d8cfc1]/70 dark:bg-[#2b2d2f] dark:ring-darkborder/70"
                aria-hidden="true"
              />
              <div className="relative z-[1] h-full space-y-3 p-3 pt-8">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-crayon text-xs uppercase tracking-[0.14em] text-textSecondary">Position</p>
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
                      <button
                        type="button"
                        onClick={() => openAttributeModal(board)}
                        className="font-varsity text-xl tracking-[0.07em] uppercase text-left hover:underline"
                        title="Click to edit highlighted attributes"
                      >
                        {board.name}
                      </button>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => {
                      setNeedDraft({
                        boardId: board.id,
                        needId: null,
                        departingPlayerId: "",
                        replacementPlayerId: "",
                        slotNumber: "",
                        resolved: false,
                      });
                      setNeedMessage("");
                      setNeedBusy(false);
                    }}
                    className="text-left"
                  >
                    <StatPill
                      label="Needs"
                      value={(board.needs || []).filter((n) => !n.resolved).length}
                    />
                  </button>
                </div>
                <div className="grid grid-cols-2 gap-2">
                <div className="rounded-lg bg-surface/60 text-sm text-textSecondary dark:border-darkborder dark:bg-darksurface/60 space-y-2">
                  <ul className="space-y-1">
                    {slotsArray.map(({ slotNum, occupant }) => {
                      const playerId = occupant?.playerId || occupant?.player_id;
                      const resolvedPlayer =
                        playerId ? findPlayerById(playerId) || occupant?.player || { id: playerId } : null;
                      const highlightAttrs = getBoardHighlightedAttributes(board);
                      const attrValues = resolvedPlayer ? getPlayerAttributes(resolvedPlayer) : {};
                      const isFlagged = !!resolvedPlayer?.flagged;
                      const isDraggingCurrent = draggingPlayer?.playerId === playerId;
                      const dropHoverClass =
                        !occupant && dragOverSlot?.boardId === board.id && dragOverSlot?.slotNum === slotNum
                          ? "border-burnt bg-burnt/15 scale-[1.02] shadow-inner"
                          : "border-border bg-white/80";
                      const flaggedClass = occupant && isFlagged ? "border-danger shadow-[0_0_0_1px_rgba(185,28,28,0.25)]" : "";
                      const draggingClass = occupant && isDraggingCurrent ? "opacity-70 ring-2 ring-burnt/50" : "";
                      return (
                        <li
                          key={slotNum}
                          className={`flex items-center justify-between gap-2 rounded-md border text-sm dark:border-darkborder dark:bg-darksurface/80 transition ${
                            occupant ? "cursor-grab active:cursor-grabbing" : ""
                          } ${dropHoverClass} ${flaggedClass} ${draggingClass}`}
                          draggable={Boolean(occupant)}
                          onDragStart={(e) => occupant && startPlayerDrag(e, playerId, board.id)}
                          onDragEnd={onPlayerDragEnd}
                          onDragOver={(e) => {
                            e.preventDefault();
                            if (!occupant) setDragOverSlot({ boardId: board.id, slotNum });
                          }}
                          onDragEnter={(e) => {
                            e.preventDefault();
                            if (!draggingPlayer?.playerId) return;
                            if (occupant) {
                              if (draggingPlayer.fromBoardId === board.id) {
                                updatePreviewOrder(board.id, draggingPlayer.playerId, playerId);
                              }
                            } else {
                              setDragOverSlot({ boardId: board.id, slotNum });
                            }
                          }}
                          onDragLeave={() => {
                            if (!occupant) setDragOverSlot(null);
                          }}
                          onDrop={(e) => {
                            e.preventDefault();
                            onSlotDrop(board.id, slotNum);
                          }}
                        >
                          <div className="flex items-center gap-2 w-full">
                            {occupant ? (
                              <div
                                className="flex flex-col cursor-pointer w-full"
                                onClick={() => resolvedPlayer && openEdit(resolvedPlayer, board.id, slotNum)}
                              >
                                <PlayerSummary
                                  player={resolvedPlayer}
                                  attributes={attrValues}
                                  highlightedAttributes={highlightAttrs}
                                  showRecruitStatus={false}
                                />
                              </div>
                            ) : (
                              <span className="text-textSecondary px-2 py-2">-</span>
                            )}
                          </div>
                        </li>
                      );
                    })}
                  </ul>
                </div>
                <div
                  className={`rounded-lg border p-2 space-y-2 transition dark:bg-darksurface/60 ${
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
                    <p className="text-sm font-semibold text-textSecondary font-crayon">Board</p>
                    <button
                      type="button"
                      onClick={() => setShowFormBoardId((prev) => (prev === board.id ? null : board.id))}
                      className="font-crayon text-sm font-semibold text-success hover:underline"
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
                      <div className="flex items-center items-between gap-2">
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
                                  (newPlayer.starRating ?? 3) >= star ? "text-burnt" : "text-border opacity-60"
                                }`}
                              >
                                ★
                              </span>
                            </button>
                          ))}
                        </div>
                        <RecruitStatusToggle
                          compact
                          value={newPlayer.recruitStatus}
                          onChange={(val) => setNewPlayer((p) => ({ ...p, recruitStatus: val }))}
                        />
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
                      {highlightAttrs.length > 0 && (
                        <div className="space-y-2">
                          <p className="text-xs font-semibold text-textSecondary uppercase tracking-[0.12em]">
                            Position attributes
                          </p>
                          <div className="grid gap-2 sm:grid-cols-2">
                            {highlightAttrs.map((attr) => (
                              <label
                                key={attr}
                                className="space-y-1 text-xs font-medium text-textSecondary dark:text-white/80"
                              >
                                <span>{humanizeAttr(attr)}</span>
                                <input
                                  type="number"
                                  inputMode="numeric"
                                  value={newPlayerAttributes[board.id]?.[attr] ?? ""}
                                  onChange={(e) => handleNewPlayerAttrChange(board.id, attr, e.target.value)}
                                  className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                                />
                              </label>
                            ))}
                          </div>
                        </div>
                      )}
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
                          className={`flex items-center justify-between rounded-md border text-sm dark:border-darkborder dark:bg-darksurface/80 cursor-grab active:cursor-grabbing ${
                            p.flagged
                              ? "border-danger shadow-[0_0_0_1px_rgba(185,28,28,0.25)]"
                              : "border-border bg-white/80"
                          } ${
                            draggingPlayer?.playerId === p.id ? "opacity-70 ring-2 ring-burnt/50" : ""
                          }`}
                          draggable
                          onDragStart={(e) => startPlayerDrag(e, p.id, board.id)}
                          onDragEnd={onPlayerDragEnd}
                          onClick={() => openEdit(p, board.id, null)}
                        >
                          <PlayerSummary
                            player={p}
                            attributes={getPlayerAttributes(p)}
                            highlightedAttributes={getBoardHighlightedAttributes(board)}
                          />
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              </div>
              </div>
            </Card>
          );
        })}
      </div>
      <AttributeModal
        draft={attributeModal}
        board={attributeBoard}
        onClose={closeAttributeModal}
        onSave={saveHighlightedAttributes}
        onToggle={toggleAttributeSelection}
        onCustomChange={setAttributeModalCustom}
        onAddCustom={addCustomAttribute}
        busy={busyBoardId === attributeModal.boardId}
      />
      <NeedModal
        needDraft={needDraft}
        setNeedDraft={setNeedDraft}
        needBusy={needBusy}
        needMessage={needMessage}
        onClose={closeNeedModal}
        onSave={handleSaveNeed}
        onDelete={handleDeleteNeed}
        boards={sortedBoards}
        players={players}
      />
      <PlayerEditModal
        editing={editing}
        onClose={closeEdit}
        onSaveDraft={setEditingDraft}
        onSave={() => saveEdit()}
        onDelete={deleteEditPlayer}
        busy={busyBoardId === "edit"}
      />
    </div>
  );
}

// Modal for selecting highlighted attributes for a position
function AttributeModal({ draft, board, onClose, onSave, onToggle, onCustomChange, onAddCustom, busy }) {
  if (!draft.boardId || !board) return null;
  const options = Array.from(
    new Set([
      ...defaultAttributeOptions,
      ...getBoardHighlightedAttributes(board),
      ...(draft.selected || []),
    ]),
  );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-lg rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-xs uppercase tracking-[0.14em] text-textSecondary">Position</p>
            <h3 className="font-varsity text-xl uppercase tracking-[0.06em]">{board.name}</h3>
          </div>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>
        <p className="mt-2 text-sm text-textSecondary">
          Choose the attributes to spotlight for this position. These will show on the card and in the player forms.
        </p>
        <div className="mt-4 space-y-3">
          <div className="flex flex-wrap gap-2">
            {options.map((attr) => {
              const selected = (draft.selected || []).includes(attr);
              return (
                <button
                  key={attr}
                  type="button"
                  onClick={() => onToggle(attr)}
                  className={`rounded-md px-3 py-2 text-xs font-semibold transition ${
                    selected
                      ? "bg-success text-white shadow-card"
                      : "border border-border text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                  }`}
                  aria-pressed={selected}
                >
                  {humanizeAttr(attr)}
                </button>
              );
            })}
          </div>
          <div className="flex gap-2">
            <input
              value={draft.custom}
              onChange={(e) => onCustomChange(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  onAddCustom();
                }
              }}
              placeholder="Add custom attribute (e.g., release)"
              className="flex-1 rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
            <button
              type="button"
              onClick={onAddCustom}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Add
            </button>
          </div>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            onClick={onSave}
            disabled={busy}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
          >
            {busy ? "Saving..." : "Save attributes"}
          </button>
        </div>
      </div>
    </div>
  );
}

// Modal for creating a need from a board
function NeedModal({
  needDraft,
  setNeedDraft,
  needBusy,
  needMessage,
  onClose,
  onSave,
  onDelete,
  boards,
  players,
}) {
  if (!needDraft.boardId) return null;
  const board = boards.find((b) => b.id === needDraft.boardId);
  const rosterSlots = board?.rosterSlots || board?.roster_slots || [];
  const occupants = rosterSlots
    .map((rs) => rs.player || players.find((p) => p.id === (rs.playerId || rs.player_id)))
    .filter(Boolean);
  const rosteredIds = new Set(
    boards
      .flatMap((b) => b.rosterSlots || b.roster_slots || [])
      .map((rs) => rs.playerId || rs.player_id)
      .filter(Boolean),
  );
  const slotCount = board?.slotsCount || board?.slots_count || 0;
  const occupiedSlotNumbers = new Set(
    (rosterSlots || []).map((rs) => rs.slotNumber || rs.slot_number).filter(Boolean),
  );
  const emptySlots = Array.from({ length: slotCount })
    .map((_, idx) => idx + 1)
    .filter((num) => !occupiedSlotNumbers.has(num));

  const boardLookup = new Map(boards.map((b) => [b.id, b]));
  const replacementOptions = players
    .filter((p) => p.id !== needDraft.departingPlayerId)
    .filter((p) => !rosteredIds.has(p.id))
    .map((p) => {
      const b = boardLookup.get(p.positionBoardId || p.position_board_id);
      return {
        player: p,
        boardName: b?.name || "Unassigned",
        sort: b?.sortOrder || b?.sort_order || 0,
      };
    })
    .sort((a, b) => {
      const sortDiff = (a.sort || 0) - (b.sort || 0);
      if (sortDiff !== 0) return sortDiff;
      return (a.boardName || "").localeCompare(b.boardName || "", undefined, { sensitivity: "base" });
    });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-lg rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <h3 className="font-varsity text-xl uppercase tracking-[0.06em]">
            {needDraft.needId ? "Edit planned replacement" : "Plan a replacement"}
          </h3>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>
        <div className="mt-4 space-y-3">
          <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Departing player or empty slot</span>
            <select
              value={
                needDraft.slotNumber
                  ? `slot:${needDraft.slotNumber}`
                  : needDraft.departingPlayerId || ""
              }
              onChange={(e) => {
                const val = e.target.value;
                if (val.startsWith("slot:")) {
                  const num = val.replace("slot:", "");
                  setNeedDraft((prev) => ({ ...prev, departingPlayerId: "", slotNumber: num }));
                } else {
                  setNeedDraft((prev) => ({ ...prev, departingPlayerId: val, slotNumber: "" }));
                }
              }}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            >
              <option value="">— Pick a player or empty slot —</option>
              {occupants.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
              {emptySlots.length > 0 && (
                <optgroup label="Empty slots">
                  {emptySlots.map((num) => (
                    <option key={num} value={`slot:${num}`}>
                      Empty Slot (#{num})
                    </option>
                  ))}
                </optgroup>
              )}
            </select>
          </label>
          <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <span>Optional replacement player</span>
            <select
              value={needDraft.replacementPlayerId}
              onChange={(e) => setNeedDraft((prev) => ({ ...prev, replacementPlayerId: e.target.value }))}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            >
              <option value="">Select later</option>
              {replacementOptions.map((opt) => (
                <option key={opt.player.id} value={opt.player.id}>
                  {opt.boardName} - {opt.player.name}
                </option>
              ))}
            </select>
          </label>
          <label className="flex items-center gap-2 text-sm font-medium text-textSecondary dark:text-white/80">
            <input
              type="checkbox"
              checked={!!needDraft.resolved}
              onChange={(e) => setNeedDraft((prev) => ({ ...prev, resolved: e.target.checked }))}
              className="h-4 w-4 rounded border-border text-burnt focus:ring-burnt"
            />
            <span>Mark as resolved</span>
          </label>
          {needMessage && <p className="text-xs text-success">{needMessage}</p>}
        </div>
        <div className="mt-4 flex justify-between items-end gap-2">
          {needDraft.needId ? (
            <button
              onClick={() => onDelete(needDraft.boardId, needDraft.needId)}
              disabled={needBusy}
              data-confirm="Delete this planned replacement?"
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-danger hover:bg-danger/10 disabled:opacity-60"
            >
              Delete
            </button>
          ) : (
            <div />
          )}
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Cancel
            </button>
            <button
              onClick={onSave}
              disabled={needBusy}
              className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:opacity-60"
            >
              {needBusy ? "Saving..." : needDraft.needId ? "Save" : "Plan"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// Modal for editing a player
function PlayerEditModal({ editing, onClose, onSaveDraft, onSave, onDelete, busy }) {
  if (!editing) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-lg rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <div className="flex flex-wrap items-center gap-3">
            <h3 className="font-varsity text-xl uppercase tracking-[0.06em]">Edit Player</h3>
            <div className="flex flex-wrap items-center gap-3">
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
              <RecruitStatusToggle
                compact
                value={editing.recruitStatus}
                onChange={(val) => onSaveDraft({ ...editing, recruitStatus: val })}
              />
            </div>
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
          {(editing.highlightedAttributes || []).length > 0 && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-textSecondary dark:text-white/80">
                  Position attributes
                </span>
                <span className="text-[11px] uppercase tracking-[0.12em] text-textSecondary/70">
                  {editing.highlightedAttributes.length} fields
                </span>
              </div>
              <div className="grid gap-2 sm:grid-cols-2">
                {editing.highlightedAttributes.map((attr) => {
                  const key = normalizeAttrKey(attr);
                  return (
                    <label
                      key={attr}
                      className="space-y-1 text-xs font-medium text-textSecondary dark:text-white/80"
                    >
                      <span>{humanizeAttr(attr)}</span>
                      <input
                        type="number"
                        inputMode="numeric"
                        value={editing.attributeValues?.[key] ?? ""}
                        onChange={(e) =>
                          onSaveDraft((prev) => ({
                            ...prev,
                            attributeValues: {
                              ...(prev?.attributeValues || {}),
                              [key]: e.target.value,
                            },
                          }))
                        }
                        className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                      />
                    </label>
                  );
                })}
              </div>
            </div>
          )}
          <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <div className="flex items-center justify-between mt-2">
              <span>Assign to another position</span>
              <span className="text-xs text-textSecondary/70">Optional</span>
            </div>
            <select
              value={editing.boardSelection || ""}
              onChange={(e) => onSaveDraft((prev) => ({ ...prev, boardSelection: e.target.value || null }))}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            >
              <option value="">— Keep current board —</option>
              {editing.boardOptions?.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.label}
                </option>
              ))}
            </select>
          </label>
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
              type="button"
              onClick={() => onSaveDraft((prev) => ({ ...prev, flagged: !prev.flagged }))}
              disabled={busy}
              aria-pressed={editing.flagged}
              title={editing.flagged ? "Unflag player" : "Flag player"}
              className={`rounded-md border px-4 py-2 text-sm font-semibold transition ${
                editing.flagged
                  ? "border-danger text-danger bg-danger/10 shadow-card"
                  : "border-border text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
              }`}
            >
              <i className="fa-solid fa-flag"></i>
            </button>
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

export default SquadBoardPage;
