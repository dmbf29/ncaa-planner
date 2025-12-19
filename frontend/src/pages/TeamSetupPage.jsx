import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import {
  fetchTeam,
  createPositionBoard,
  updatePositionBoard,
  deletePositionBoard,
} from "../lib/apiClient";

const offenseTemplate = [
  { name: "QB", slotsCount: 5 },
  { name: "HB", slotsCount: 7 },
  { name: "WR", slotsCount: 8 },
  { name: "TE", slotsCount: 4 },
  { name: "OT", slotsCount: 7 },
  { name: "OG", slotsCount: 7 },
  { name: "C", slotsCount: 4 },
  { name: "K", slotsCount: 1 },
  { name: "P", slotsCount: 1 },
];

const defenseTemplate = [
  { name: "DE", slotsCount: 8 },
  { name: "DT", slotsCount: 5 },
  { name: "WILL", slotsCount: 4 },
  { name: "SAM", slotsCount: 4 },
  { name: "MIKE", slotsCount: 4 },
  { name: "CB", slotsCount: 8 },
  { name: "FS", slotsCount: 4 },
  { name: "SS", slotsCount: 4 },
];

const offenseOptionalPositions = ["FB", "LT", "LG", "RG", "RT", "OL", "OTHER"];
const defenseOptionalPositions = ["LE", "RE", "OLB", "LB", "DB", "NICKEL", "OTHER"];

const offensePositionNames = offenseTemplate.map((pos) => pos.name);
const defensePositionNames = defenseTemplate.map((pos) => pos.name);

const uniqueOrdered = (list) => {
  const seen = new Set();
  const ordered = [];
  list.forEach((item) => {
    if (!seen.has(item)) {
      seen.add(item);
      ordered.push(item);
    }
  });
  return ordered;
};

const isOffenseSquad = (squad) => squad?.name?.toLowerCase()?.includes("off");

const getAvailablePositions = (squad) => {
  const base = isOffenseSquad(squad) ? offensePositionNames : defensePositionNames;
  const optional = isOffenseSquad(squad)
    ? offenseOptionalPositions
    : defenseOptionalPositions;
  return uniqueOrdered([...base, ...optional]);
};

const getDefaultSelection = (squad) =>
  isOffenseSquad(squad) ? offensePositionNames : defensePositionNames;

const getDefaultSlotsCount = (squad, name) => {
  const template = (isOffenseSquad(squad) ? offenseTemplate : defenseTemplate).find(
    (pos) => pos.name === name,
  );
  return template?.slotsCount ?? 1;
};

const sortByPositionOrder = (names, squad) => {
  const order = getAvailablePositions(squad);
  const orderMap = new Map(order.map((name, index) => [name, index]));
  return [...names].sort((a, b) => {
    const ai = orderMap.has(a) ? orderMap.get(a) : Number.MAX_SAFE_INTEGER;
    const bi = orderMap.has(b) ? orderMap.get(b) : Number.MAX_SAFE_INTEGER;
    if (ai !== bi) return ai - bi;
    return a.localeCompare(b);
  });
};

function SquadAccordion({
  squad,
  availablePositions = [],
  expanded,
  selection = [],
  confirmed = false,
  busy,
  onToggle,
  onTogglePosition,
  onEnterEditMode,
  onUpdateBoard,
}) {
  const selectedPositions = useMemo(() => new Set(selection), [selection]);
  const orderedBoards = useMemo(() => {
    const orderMap = new Map(availablePositions.map((name, index) => [name, index]));
    const boards = squad.positionBoards || [];
    return [...boards].sort((a, b) => {
      const ai = orderMap.has(a.name) ? orderMap.get(a.name) : Number.MAX_SAFE_INTEGER;
      const bi = orderMap.has(b.name) ? orderMap.get(b.name) : Number.MAX_SAFE_INTEGER;
      if (ai !== bi) return ai - bi;
      return a.name.localeCompare(b.name);
    });
  }, [availablePositions, squad.positionBoards]);

  return (
    <Card>
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center justify-between px-5 py-4 text-left"
      >
        <div>
          <p className="text-xs uppercase tracking-[0.14em] text-textSecondary">Squad</p>
          <h3 className="font-varsity text-xl tracking-[0.06em] uppercase">{squad.name}</h3>
        </div>
        <span className="text-sm text-textSecondary">{expanded ? "Collapse" : "Expand"}</span>
      </button>
      {expanded && (
        <div className="space-y-4 border-t border-border px-5 py-4 dark:border-darkborder">
          {!confirmed && (
            <div className="space-y-3 rounded-lg border border-border bg-surface/70 p-4 text-sm dark:border-darkborder dark:bg-darksurface/70">
              <div className="flex justify-between flex-col md:flex-row">
                <p className="font-semibold text-textSecondary">Choose positions for your board</p>
                <p className="text-xs text-textSecondary">
                  Select positions, then confirm to set slot counts.
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                {availablePositions.map((pos) => {
                  const selected = selectedPositions.has(pos);
                  return (
                    <button
                      key={pos}
                      type="button"
                      onClick={() => onTogglePosition(pos)}
                      className={`rounded-md px-3 py-2 text-xs font-semibold transition ${
                        selected
                          ? "bg-success text-white shadow-card"
                          : "border border-border text-charcoal hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                      }`}
                      aria-pressed={selected}
                    >
                      {pos}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {confirmed && (
            <div className="space-y-3">
              <div className="flex items-start justify-between flex-col sm:flex-row">
                <div>
                  <p className="text-sm font-semibold text-textSecondary">
                    Number of roster spots for each position
                  </p>
                  <p className="text-xs text-textSecondary">
                    To add or remove positions, click Edit positions.
                  </p>
                </div>
                <button
                  type="button"
                  onClick={onEnterEditMode}
                  className="rounded-md border border-border px-3 py-2 text-xs font-semibold text-charcoal transition hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Edit positions
                </button>
              </div>

              <div className="grid gap-3 xs:grid-cols-2 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-4">
                {orderedBoards.map((board) => (
                  <div
                    key={board.id}
                    className="rounded-lg border border-border bg-surface/60 p-3 dark:border-darkborder dark:bg-darksurface/60"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <span className="rounded-md bg-border/60 px-3 py-2 text-sm font-semibold uppercase tracking-wide text-charcoal dark:bg-white/10 dark:text-white">
                        {board.name}
                      </span>
                      <div className="flex items-center gap-2">
                        <label className="text-xs font-semibold text-textSecondary">Spots</label>
                        <input
                          type="number"
                          min={1}
                          defaultValue={board.slotsCount}
                          disabled={busy}
                          onChange={(e) =>
                            onUpdateBoard(board.id, {
                              slotsCount: Number(e.target.value) || 1,
                            })
                          }
                          className="w-20 rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none disabled:cursor-not-allowed disabled:opacity-70 dark:border-darkborder dark:bg-darksurface"
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </Card>
  );
}

function TeamSetupPage() {
  const { id } = useParams();
  const ROSTER_TARGET = 85;
  const [team, setTeam] = useState(null);
  const [error, setError] = useState(null);
  const [expandedSquadIds, setExpandedSquadIds] = useState({});
  const [busy, setBusy] = useState(false);
  const [positionSelections, setPositionSelections] = useState({});

  const squads = useMemo(() => team?.squads || [], [team]);
  const offenseSquad = useMemo(
    () => squads.find((squad) => isOffenseSquad(squad)),
    [squads],
  );

  const refresh = async () => {
    try {
      const data = await fetchTeam(id);
      setTeam(data);
      setExpandedSquadIds((prev) => {
        const next = { ...prev };
        (data.squads || []).forEach((squad) => {
          if (next[squad.id] === undefined) {
            next[squad.id] = true; // open all by default
          }
        });
        return next;
      });
      setPositionSelections((prev) => {
        const next = { ...prev };
        (data.squads || []).forEach((squad) => {
          const boards = squad.positionBoards || [];
          if (boards.length > 0) {
            next[squad.id] = {
              selected: sortByPositionOrder(boards.map((b) => b.name), squad),
              confirmed: true,
            };
          } else {
            next[squad.id] = {
              selected: [...getDefaultSelection(squad)],
              confirmed: false,
            };
          }
        });
        return next;
      });
    } catch (err) {
      setError(err.message);
    }
  };

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const handleUpdateBoard = async (boardId, payload) => {
    setBusy(true);
    try {
      await updatePositionBoard(id, boardId, payload);
      await refresh();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const totalSlots = useMemo(() => {
    if (!team?.squads) return 0;
    return team.squads.reduce((sum, squad) => {
      const boards = squad.positionBoards || [];
      return (
        sum +
        boards.reduce((inner, board) => inner + Number(board.slotsCount || 0), 0)
      );
    }, 0);
  }, [team]);

  const showSlotCounter = useMemo(
    () =>
      squads.length > 0 &&
      squads.every((squad) => positionSelections[squad.id]?.confirmed),
    [positionSelections, squads],
  );

  const slotCounterTone = totalSlots === ROSTER_TARGET
    ? "text-success"
    : totalSlots > ROSTER_TARGET
    ? "text-warning"
    : "text-info";

  const offenseLinkReady =
    offenseSquad &&
    ((positionSelections[offenseSquad.id]?.confirmed ?? false) ||
      (offenseSquad.positionBoards || []).length > 0);

  const togglePositionSelection = (squadId, positionName) => {
    setPositionSelections((prev) => {
    const current = prev[squadId] || { selected: [], confirmed: false };
    const nextSelected = new Set(current.selected || []);
      if (nextSelected.has(positionName)) {
        nextSelected.delete(positionName);
      } else {
        nextSelected.add(positionName);
      }
    const squad = squads.find((s) => s.id === squadId);
    const orderedSelected = squad
      ? sortByPositionOrder(Array.from(nextSelected), squad)
      : Array.from(nextSelected);
      return {
        ...prev,
      [squadId]: { ...current, selected: orderedSelected },
      };
    });
  };

  const enterEditMode = (squad) => {
    setPositionSelections((prev) => ({
      ...prev,
      [squad.id]: {
      selected: sortByPositionOrder((squad.positionBoards || []).map((b) => b.name), squad),
        confirmed: false,
      },
    }));
  };

  const confirmAllPositions = async () => {
    setError(null);
    setBusy(true);
    try {
      for (const squad of squads) {
        const currentSelection = positionSelections[squad.id]?.selected || [];
        if (currentSelection.length === 0) {
          throw new Error(
            `Please select at least one position for ${squad.name || "a squad"}.`,
          );
        }

        const selectedSet = new Set(currentSelection);
        const existingBoards = squad.positionBoards || [];
        const createList = currentSelection.filter(
          (name) => !existingBoards.some((b) => b.name === name),
        );
        const deleteList = existingBoards.filter((board) => !selectedSet.has(board.name));

        await Promise.all([
          ...createList.map((name) =>
            createPositionBoard(id, {
              name,
              slotsCount: getDefaultSlotsCount(squad, name),
              squadId: squad.id,
            }),
          ),
          ...deleteList.map((board) => deletePositionBoard(id, board.id)),
        ]);
      }

      await refresh();
      setPositionSelections((prev) => {
        const next = { ...prev };
        squads.forEach((squad) => {
          const selected = sortByPositionOrder(prev[squad.id]?.selected || [], squad);
          if (selected.length > 0) {
            next[squad.id] = { selected, confirmed: true };
          }
        });
        return next;
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="max-w-6xl mx-auto px-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <PageHeader title="Board Setup" eyebrow={team ? team.name : "Loading..."} />
        <div className="flex w-full flex-col gap-2 md:w-auto md:flex-row md:items-center md:justify-end md:gap-5">
          {showSlotCounter && (
            <div className="flex flex-col md:flex-col-reverse items-center gap-1">
              <span
                className={`text-sm font-semibold ${slotCounterTone} md:order-1`}
                aria-live="polite"
              >
                {totalSlots} / {ROSTER_TARGET}
              </span>
              <p className="text-xs uppercase tracking-[0.1em] text-textSecondary">Scholarships</p>
            </div>
          )}
          <div className="flex flex-col gap-2 md:flex-row md:gap-3 w-full md:w-auto">
            <button
              type="button"
              onClick={confirmAllPositions}
              disabled={busy || squads.length === 0}
              className="w-full rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60 md:w-auto mb-1 md:mb-0"
            >
              Confirm All Positions
            </button>
            {offenseLinkReady && (
              <Link
                to={`/teams/${id}/squads/${offenseSquad.id}`}
                className="w-full md:w-auto rounded-md border border-border px-4 py-2 text-sm font-semibold text-burnt border-burnt transition hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10 text-center"
              >
                Go to Roster
              </Link>
            )}
          </div>
        </div>
      </div>
      {error && <p className="text-sm text-danger">{error}</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading team...</p>}

      {squads.map((squad) => (
        <SquadAccordion
          key={squad.id}
          squad={squad}
          expanded={!!expandedSquadIds[squad.id]}
          onToggle={() =>
            setExpandedSquadIds((prev) => ({
              ...prev,
              [squad.id]: !prev[squad.id],
            }))
          }
          selection={positionSelections[squad.id]?.selected}
          confirmed={positionSelections[squad.id]?.confirmed}
          busy={busy}
          onTogglePosition={(name) => togglePositionSelection(squad.id, name)}
          onEnterEditMode={() => enterEditMode(squad)}
          onUpdateBoard={handleUpdateBoard}
          availablePositions={getAvailablePositions(squad)}
        />
      ))}
    </div>
  );
}

export default TeamSetupPage;
