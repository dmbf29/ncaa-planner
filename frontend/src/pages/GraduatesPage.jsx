import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import OverallPill from "../components/OverallPill";
import { deletePlayer, fetchPlayers, fetchTeam, fetchSquadBoards, updatePlayer } from "../lib/apiClient";

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
              <i className={`fa-solid ${meta.icon} ${selected ? "text-white" : meta.color}`} />
              <span>{option.label}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}

const renderTrait = (trait) => {
  const meta = devTraitMeta[trait] || devTraitMeta.normal;
  return (
    <span className="inline-flex items-center gap-1 text-xs">
      <i className={`fa-solid ${meta.color} ${meta.icon}`} />
    </span>
  );
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
        <span className="text-textPrimary dark:text-white font-semibold">{player.name || player.id}</span>
        {overall ? <OverallPill value={overall} /> : null}
      </div>
      <div className="grid grid-cols-4 gap-1 px-2 bg-textSecondary/5 py-1">
        <AttributeCell value={classYear ? <span className={classColor(classYear)}>{classYear}</span> : null} />
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
            <DevTraitButtons value={editing.devTrait} onChange={(val) => onSaveDraft({ ...editing, devTrait: val })} />
          </div>
          <label className="space-y-1 text-sm font-medium text-textSecondary dark:text-white/80">
            <div className="flex items-center justify-between">
              <span>Assign to position board (returns as recruit)</span>
              <span className="text-xs text-textSecondary/70">Optional</span>
            </div>
            <select
              value={editing.boardId || ""}
              onChange={(e) => onSaveDraft({ ...editing, boardId: e.target.value || null })}
              className="w-full rounded-md border border-border bg-white px-3 py-2 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            >
              <option value="">— Keep as alumni —</option>
              {editing.boardOptions?.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.label}
                </option>
              ))}
            </select>
          </label>
        </div>
        <div className="mt-4 flex justify-end items-end">
          <div className="flex gap-1">
            <button
              onClick={() => {
                if (busy) return;
                const message =
                  "Delete this player completely? This action cannot be undone. If you want to save his name, mark the player as graduated or departed. instead";
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

function GraduatesPage() {
  const { id } = useParams();
  const [team, setTeam] = useState(null);
  const [players, setPlayers] = useState([]);
  const [boards, setBoards] = useState([]);
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = async () => {
      try {
        const [teamData, playerData] = await Promise.all([
          fetchTeam(id),
          fetchPlayers(id, { status: ["graduated", "departed"] }),
        ]);
        setTeam(teamData);
        setPlayers(playerData);
        if (teamData?.squads?.length) {
          const boardGroups = await Promise.all(
            teamData.squads.map((sq) => fetchSquadBoards(id, sq.id)),
          );
          const flattened = boardGroups.flat().map((b) => ({
            ...b,
            label: `${teamData.squads.find((sq) => sq.id === (b.squadId || b.squad_id))?.name || "Squad"} • ${
              b.name
            }`,
          }));
          setBoards(flattened);
        } else {
          setBoards([]);
        }
      } catch (err) {
        setError(err.message);
      }
    };
    load();
  }, [id]);

  const sortedPlayers = useMemo(
    () =>
      [...players].sort((a, b) => (a.name || "").localeCompare(b.name || "", undefined, { sensitivity: "base" })),
    [players],
  );

  const openEdit = (player) => {
    setEditing({
      id: player.id,
      name: player.name || "",
      classYear: player.classYear || player.class_year || "",
      devTrait: player.devTrait || player.dev_trait || "",
      archetype: player.archetype || "",
      overall: player.overall || "",
      starRating: player.starRating || player.star_rating || 3,
      status: player.status || "graduated",
      boardId: player.positionBoardId || player.position_board_id || "",
      boardOptions: boards,
    });
  };

  const closeEdit = () => setEditing(null);

  const saveEdit = async () => {
    if (!editing) return;
    setSaving(true);
    try {
      const wantsReturn = !!editing.boardId;
      await updatePlayer(id, editing.id, {
        name: editing.name,
        class_year: editing.classYear || null,
        dev_trait: editing.devTrait || null,
        archetype: editing.archetype || null,
        overall: editing.overall || null,
        star_rating: editing.starRating || null,
        status: wantsReturn ? "recruit" : editing.status || "graduated",
        position_board_id: editing.boardId || null,
      });
      const playerData = await fetchPlayers(id, { status: ["graduated", "departed"] });
      setPlayers(playerData);
      closeEdit();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const deleteEditPlayer = async () => {
    if (!editing) return;
    setSaving(true);
    try {
      await deletePlayer(id, editing.id);
      const playerData = await fetchPlayers(id, { status: ["graduated", "departed"] });
      setPlayers(playerData);
      closeEdit();
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const headerActions =
    team?.squads?.length > 0 ? (
      <div className="flex flex-wrap gap-2">
        {team.squads.map((sq) => (
          <Link
            key={sq.id}
            to={`/teams/${id}/squads/${sq.id}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            {sq.name}
          </Link>
        ))}
        <Link
          to={`/teams/${id}/graduates`}
          className="rounded-md px-3 py-2 text-sm border bg-burnt/5 border-burnt font-semibold text-burnt shadow-card"
        >
          Alumni
        </Link>
      </div>
    ) : null;

  return (
    <div className="space-y-4">
      <PageHeader title="Alumni" eyebrow={team ? team.name : "Loading"} actions={headerActions} />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!sortedPlayers.length && !error && (
        <p className="text-sm text-textSecondary">No alumni (graduated or departed) yet.</p>
      )}
      <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
        {sortedPlayers.map((p) => (
          <Card key={p.id} className="h-full">
            <div className="p-4 space-y-2 h-full flex flex-col">
              <div className="flex items-start justify-between gap-2">
                <span className="rounded-full bg-textSecondary/10 px-2 py-1 text-[11px] font-semibold uppercase tracking-wide text-textSecondary">
                  {p.status}
                </span>
                <button
                  type="button"
                  onClick={() => openEdit(p)}
                  className="text-sm font-semibold text-burnt hover:underline"
                >
                  Edit
                </button>
              </div>
              <PlayerSummary player={p} />
            </div>
          </Card>
        ))}
      </div>
      <PlayerEditModal
        editing={editing}
        onClose={closeEdit}
        onSaveDraft={(draft) => setEditing(draft)}
        onSave={() => saveEdit()}
        onDelete={deleteEditPlayer}
        busy={saving}
      />
    </div>
  );
}

export default GraduatesPage;
