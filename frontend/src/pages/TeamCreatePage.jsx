import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { createTeam, createPositionBoard, importRoster, fetchColleges } from "../lib/apiClient";
import {
  isOffenseSquad,
  getAvailablePositions,
  getDefaultSelection,
  getDefaultSlotsCount,
  getDefaultSortOrder,
  sortByPositionOrder,
} from "../lib/positionTemplates";

const ROSTER_TARGET = 85;

const virtualSquads = [{ key: "offense", name: "Offense" }, { key: "defense", name: "Defense" }];

const buildInitialPositionState = () => {
  const state = {};
  virtualSquads.forEach((squad) => {
    const selected = getDefaultSelection(squad);
    const slotsCounts = {};
    selected.forEach((name) => {
      slotsCounts[name] = getDefaultSlotsCount(squad, name);
    });
    state[squad.key] = { selected, slotsCounts };
  });
  return state;
};

function SquadPositionPicker({ squad, expanded, onToggle, selection, onTogglePosition, onSlotsCountChange }) {
  const selectedPositions = useMemo(() => new Set(selection.selected), [selection.selected]);
  const orderedSelected = useMemo(
    () => sortByPositionOrder(selection.selected, squad),
    [selection.selected, squad],
  );

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
          <div className="space-y-3 rounded-lg border border-border bg-surface/70 p-4 text-sm dark:border-darkborder dark:bg-darksurface/70">
            <div className="flex justify-between flex-col md:flex-row">
              <p className="font-semibold text-textSecondary">Choose positions for your board</p>
              <p className="text-xs text-textSecondary">Select positions, then set slot counts below.</p>
            </div>
            <div className="flex flex-wrap gap-2">
              {getAvailablePositions(squad).map((pos) => {
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

          {orderedSelected.length > 0 && (
            <div className="space-y-3">
              <p className="text-sm font-semibold text-textSecondary">Number of roster spots for each position</p>
              <div className="grid gap-3 xs:grid-cols-2 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-4">
                {orderedSelected.map((name) => (
                  <div
                    key={name}
                    className="rounded-lg border border-border bg-surface/60 p-3 dark:border-darkborder dark:bg-darksurface/60"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <span className="rounded-md bg-border/60 px-3 py-2 text-sm font-semibold uppercase tracking-wide text-charcoal dark:bg-white/10 dark:text-white">
                        {name}
                      </span>
                      <div className="flex items-center gap-2">
                        <label className="text-xs font-semibold text-textSecondary">Spots</label>
                        <input
                          type="number"
                          min={1}
                          value={selection.slotsCounts[name] ?? 1}
                          onChange={(e) => onSlotsCountChange(name, Number(e.target.value) || 1)}
                          className="w-20 rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
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

function TeamCreatePage() {
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [expandedSquadKeys, setExpandedSquadKeys] = useState({ offense: true, defense: true });
  const [positionState, setPositionState] = useState(buildInitialPositionState);
  const [importEnabled, setImportEnabled] = useState(false);
  const [colleges, setColleges] = useState([]);
  const [collegesLoading, setCollegesLoading] = useState(false);
  const [collegeId, setCollegeId] = useState("");

  useEffect(() => {
    if (!importEnabled || colleges.length > 0 || collegesLoading) return;
    setCollegesLoading(true);
    fetchColleges()
      .then(setColleges)
      .catch((err) => setError(err.message))
      .finally(() => setCollegesLoading(false));
  }, [importEnabled, colleges.length, collegesLoading]);

  const totalSlots = useMemo(
    () =>
      virtualSquads.reduce((sum, squad) => {
        const { selected, slotsCounts } = positionState[squad.key];
        return sum + selected.reduce((inner, name) => inner + Number(slotsCounts[name] || 0), 0);
      }, 0),
    [positionState],
  );

  const slotCounterTone =
    totalSlots === ROSTER_TARGET ? "text-success" : totalSlots > ROSTER_TARGET ? "text-warning" : "text-info";

  const togglePosition = (squadKey, name) => {
    setPositionState((prev) => {
      const current = prev[squadKey];
      const squad = virtualSquads.find((s) => s.key === squadKey);
      const nextSelected = new Set(current.selected);
      const nextSlotsCounts = { ...current.slotsCounts };
      if (nextSelected.has(name)) {
        nextSelected.delete(name);
        delete nextSlotsCounts[name];
      } else {
        nextSelected.add(name);
        nextSlotsCounts[name] = getDefaultSlotsCount(squad, name);
      }
      return {
        ...prev,
        [squadKey]: { selected: Array.from(nextSelected), slotsCounts: nextSlotsCounts },
      };
    });
  };

  const changeSlotsCount = (squadKey, name, value) => {
    setPositionState((prev) => ({
      ...prev,
      [squadKey]: {
        ...prev[squadKey],
        slotsCounts: { ...prev[squadKey].slotsCounts, [name]: value },
      },
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);

    for (const squad of virtualSquads) {
      if (positionState[squad.key].selected.length === 0) {
        setError(`Please select at least one position for ${squad.name}.`);
        return;
      }
    }
    if (importEnabled && !collegeId) {
      setError("Please choose a college to import, or turn off the import toggle.");
      return;
    }

    setLoading(true);
    try {
      const teamPayload = { name };
      if (importEnabled && collegeId) teamPayload.collegeId = collegeId;
      const team = await createTeam(teamPayload);

      const squadIdByKey = {};
      virtualSquads.forEach((squad) => {
        const match = team.squads.find((s) => isOffenseSquad(s) === isOffenseSquad(squad));
        squadIdByKey[squad.key] = match?.id;
      });

      await Promise.all(
        virtualSquads.flatMap((squad) => {
          const { selected, slotsCounts } = positionState[squad.key];
          const squadId = squadIdByKey[squad.key];
          return selected.map((name) =>
            createPositionBoard(team.id, {
              name,
              slotsCount: slotsCounts[name] || 1,
              sortOrder: getDefaultSortOrder(squad, name),
              squadId,
            }),
          );
        }),
      );

      if (importEnabled && collegeId) {
        await importRoster(team.id, { collegeId });
      }

      const offenseSquadId = squadIdByKey.offense;
      navigate(`/teams/${team.id}/squads/${offenseSquadId}`);
    } catch (err) {
      setError(err.message || "Could not create team");
      setLoading(false);
    }
  };

  return (
    <div className="max-w-4xl mx-auto px-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <PageHeader title="New Team" eyebrow="Setup" />
        <div className="flex flex-col md:flex-col-reverse items-center gap-1">
          <span className={`text-sm font-semibold ${slotCounterTone}`} aria-live="polite">
            {totalSlots} / {ROSTER_TARGET}
          </span>
          <p className="text-xs uppercase tracking-[0.1em] text-textSecondary">Scholarships</p>
        </div>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        {error && <p className="text-sm text-danger">{error}</p>}

        <Card>
          <div className="space-y-5 p-6">
            <div className="space-y-2">
              <label className="text-sm font-medium text-textSecondary">Team Name</label>
              <input
                required
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm shadow-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
              />
            </div>

            <div className="space-y-3 rounded-lg border border-border bg-surface/70 p-4 dark:border-darkborder dark:bg-darksurface/70">
              <label className="flex items-center gap-3">
                <input
                  type="checkbox"
                  checked={importEnabled}
                  onChange={(e) => setImportEnabled(e.target.checked)}
                  className="h-4 w-4 rounded border-border text-burnt focus:ring-burnt"
                />
                <span className="text-sm font-semibold text-textSecondary">Import a 2026 Squad</span>
              </label>
              {importEnabled && (
                <div className="space-y-2">
                  <p className="text-xs text-textSecondary">
                    Choose a college to pull its current roster onto the boards below.
                  </p>
                  <select
                    required={importEnabled}
                    value={collegeId}
                    onChange={(e) => setCollegeId(e.target.value)}
                    disabled={collegesLoading}
                    className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none disabled:opacity-60 dark:border-darkborder dark:bg-darksurface"
                  >
                    <option value="">
                      {collegesLoading ? "Loading colleges..." : "Select a college"}
                    </option>
                    {colleges.map((college) => (
                      <option key={college.id} value={college.id}>
                        {college.name}
                        {college.conference ? ` (${college.conference})` : ""}
                      </option>
                    ))}
                  </select>
                </div>
              )}
            </div>
          </div>
        </Card>

        {virtualSquads.map((squad) => (
          <SquadPositionPicker
            key={squad.key}
            squad={squad}
            expanded={!!expandedSquadKeys[squad.key]}
            onToggle={() =>
              setExpandedSquadKeys((prev) => ({ ...prev, [squad.key]: !prev[squad.key] }))
            }
            selection={positionState[squad.key]}
            onTogglePosition={(name) => togglePosition(squad.key, name)}
            onSlotsCountChange={(name, value) => changeSlotsCount(squad.key, name, value)}
          />
        ))}

        <button
          type="submit"
          disabled={loading}
          className="w-full rounded-lg bg-burnt px-4 py-2 text-white font-semibold shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-70 md:w-auto"
        >
          {loading ? "Creating..." : "Create Team"}
        </button>
      </form>
    </div>
  );
}

export default TeamCreatePage;
