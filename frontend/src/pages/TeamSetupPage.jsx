import { useEffect, useMemo, useState } from "react";
import { useParams } from "react-router-dom";
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
  { name: "RB", slotsCount: 7 },
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

function SquadAccordion({
  squad,
  expanded,
  onToggle,
  onCreateBoard,
  onTemplate,
  onUpdateBoard,
  onDeleteBoard,
}) {
  const [newBoard, setNewBoard] = useState({ name: "", slotsCount: 1 });

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
          {(!squad.positionBoards || squad.positionBoards.length === 0) && (
            <div className="space-y-2 rounded-lg border border-border bg-surface/70 p-3 text-sm text-textSecondary dark:border-darkborder dark:bg-darksurface/70">
              <p>Suggested template</p>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => onTemplate("offense", squad)}
                  className="rounded-md border border-border px-3 py-2 text-xs font-semibold text-charcoal transition hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Apply Offense Template
                </button>
                <button
                  type="button"
                  onClick={() => onTemplate("defense", squad)}
                  className="rounded-md border border-border px-3 py-2 text-xs font-semibold text-charcoal transition hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Apply Defense Template
                </button>
              </div>
            </div>
          )}

          <div className="space-y-3">
            {(squad.positionBoards || []).map((board) => (
              <div
                key={board.id}
                className="rounded-lg border border-border bg-surface/60 p-3 dark:border-darkborder dark:bg-darksurface/60"
              >
                <div className="grid gap-3 md:grid-cols-3 md:items-center">
                  <input
                    defaultValue={board.name}
                    onBlur={(e) => onUpdateBoard(board.id, { name: e.target.value })}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  />
                  <input
                    type="number"
                    min={1}
                    defaultValue={board.slotsCount}
                    onBlur={(e) => onUpdateBoard(board.id, { slotsCount: Number(e.target.value) || 1 })}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
                  />
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => onDeleteBoard(board.id)}
                      className="rounded-md border border-danger px-3 py-2 text-sm font-semibold text-danger hover:bg-danger/10"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>

          <div className="rounded-lg border border-border bg-surface/60 p-3 dark:border-darkborder dark:bg-darksurface/60">
            <p className="text-sm font-semibold text-textSecondary">Add position board</p>
            <div className="mt-2 grid gap-3 md:grid-cols-3 md:items-center">
              <input
                placeholder="Name (e.g., RB)"
                value={newBoard.name}
                onChange={(e) => setNewBoard((prev) => ({ ...prev, name: e.target.value }))}
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              />
              <input
                type="number"
                min={1}
                value={newBoard.slotsCount}
                onChange={(e) =>
                  setNewBoard((prev) => ({ ...prev, slotsCount: Number(e.target.value) || 1 }))
                }
                className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              />
              <button
                type="button"
                onClick={() => {
                  if (!newBoard.name.trim()) return;
                  onCreateBoard({ ...newBoard, squadId: squad.id });
                  setNewBoard({ name: "", slotsCount: 1 });
                }}
                className="rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-charcoal shadow-card transition hover:-translate-y-0.5"
              >
                Add
              </button>
            </div>
          </div>
        </div>
      )}
    </Card>
  );
}

function TeamSetupPage() {
  const { id } = useParams();
  const [team, setTeam] = useState(null);
  const [error, setError] = useState(null);
  const [expandedSquadId, setExpandedSquadId] = useState(null);
  const [busy, setBusy] = useState(false);

  const squads = useMemo(() => team?.squads || [], [team]);

  const refresh = async () => {
    try {
      const data = await fetchTeam(id);
      setTeam(data);
      const firstId = data.squads?.[0]?.id;
      setExpandedSquadId((prev) => {
        if (prev && data.squads?.some((s) => s.id === prev)) return prev;
        return firstId || prev;
      });
    } catch (err) {
      setError(err.message);
    }
  };

  useEffect(() => {
    refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const applyTemplate = async (type, squad) => {
    setBusy(true);
    const template = type === "offense" ? offenseTemplate : defenseTemplate;
    try {
      await Promise.all(
        template.map((b) =>
          createPositionBoard(id, { ...b, squadId: squad.id }),
        ),
      );
      await refresh();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleCreateBoard = async (payload) => {
    setBusy(true);
    try {
      await createPositionBoard(id, payload);
      await refresh();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

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

  const handleDeleteBoard = async (boardId) => {
    setBusy(true);
    try {
      await deletePositionBoard(id, boardId);
      await refresh();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <PageHeader title="Team Setup" eyebrow={team ? team.name : "Loading..."} />
      {error && <p className="text-sm text-danger">{error}</p>}
      {busy && <p className="text-sm text-textSecondary">Saving...</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading team...</p>}

      {squads.map((squad) => (
        <SquadAccordion
          key={squad.id}
          squad={squad}
          expanded={expandedSquadId === squad.id}
          onToggle={() =>
            setExpandedSquadId((prev) => (prev === squad.id ? null : squad.id))
          }
          onCreateBoard={handleCreateBoard}
          onTemplate={applyTemplate}
          onUpdateBoard={handleUpdateBoard}
          onDeleteBoard={handleDeleteBoard}
        />
      ))}
    </div>
  );
}

export default TeamSetupPage;
