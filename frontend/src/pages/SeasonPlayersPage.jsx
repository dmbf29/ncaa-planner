import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import SeasonSwitcher from "../components/SeasonSwitcher";
import Card from "../components/Card";
import MultiSelect from "../components/MultiSelect";
import OverallBadge from "../components/OverallBadge";
import AddToSquadModal from "../components/AddToSquadModal";
import { API_BASE_URL, fetchDynastyPortal, fetchFlags, fetchSeasonStudentSeasons } from "../lib/apiClient";

// The full season pool is ~11k players — never render all of them. Filters
// narrow it down; this is just the ceiling on how many rows we paint.
const RENDER_CAP = 150;

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

// Text columns sort A→Z by default; rating columns sort high→low, since the
// top of the list is what you're looking for in the portal.
const ASCENDING_BY_DEFAULT = new Set(["name", "team", "devTrait", "archetype"]);

const POSITION_ORDER = [
  "QB", "HB", "FB", "WR", "TE", "LT", "RT", "LG", "RG", "C", "LEDG", "REDG",
  "DT", "SAM", "MIKE", "WILL", "CB", "FS", "SS", "K", "P",
];
const positionRank = (pos) => {
  const i = POSITION_ORDER.indexOf(pos);
  return i === -1 ? POSITION_ORDER.length : i;
};

const emptyFilters = () => ({
  search: "",
  positions: [],
  classYears: [],
  teams: [],
  conferences: [],
  minOverall: "",
  archetypes: [],
  minHeight: "",
  maxHeight: "",
  minWeight: "",
  maxWeight: "",
});

// Compact archetype names for the table cells; the filter keeps the full names. Anything missing falls back to the full name.
const ARCHETYPE_ABBREVIATIONS = {
  "Pass Protector": "Pass Prot",
  "Raw Strength": "Raw Str",
  "Bump and Run": "Bump/Run",
  "Gap Specialist": "Gap Spec",
  "Power Rusher": "Pwr Rush",
  "Pure Power": "Pure Pwr",
  "Speed Rusher": "Spd Rush",
  "Box Specialist": "Box Spec",
  "Coverage Specialist": "Cov Spec",
  "Backfield Threat": "Bkfld Thr",
  "Contact Seeker": "Contact",
  "East/West Playmaker": "E/W Play",
  "Elusive Bruiser": "Elus Bruiser",
  "North/South Blocker": "N/S Block",
  "North/South Receiver": "N/S Rec",
  "Edge Setter": "Edge Set",
  "Well Rounded": "Well Rnd",
  "Signal Caller": "Sig Caller",
  "Backfield Creator": "Bkfld Crt",
  "Dual Threat": "Dual Thr",
  "Pocket Passer": "Pocket",
  "Pure Runner": "Pure Run",
  "Gritty Possession": "Gritty Poss",
  "Physical Route Runner": "Phys RR",
  "Pure Blocker": "Pure Blk",
  "Vertical Threat": "Vert Thr",
  "Contested Specialist": "Contested",
  "Elusive Route Runner": "Elus RR",
  "Route Artist": "Route Art",
};
const shortArchetype = (name) => ARCHETYPE_ABBREVIATIONS[name] ?? name;

const formatHeight = (inches) => (inches == null ? "—" : `${Math.floor(inches / 12)}'${inches % 12}"`);

// Accepts 6'2, 6'2", 6-2, 6 2 or plain inches (74); returns inches or null when blank/unparseable.
function parseHeight(text) {
  const t = text.trim();
  if (!t) return null;
  const ftIn = t.match(/^(\d)\s*['\-\s]\s*(\d{1,2})?\s*"?$/);
  if (ftIn) return Number(ftIn[1]) * 12 + Number(ftIn[2] ?? 0);
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

function sortValueFor(player, field) {
  if (field === "team") return player.team;
  if (field.startsWith("ratings.")) return player.ratings?.[field.slice(8)];
  return player[field];
}

function SortableTh({ label, field, sort, onSort, align = "left", sticky = false }) {
  const active = sort.field === field;
  return (
    <th
      className={`px-3 py-2 ${align === "right" ? "text-right" : align === "center" ? "text-center" : "text-left"} ${
        sticky ? "sticky left-0 z-10 bg-surface dark:bg-darksurface" : ""
      }`}
    >
      <button
        type="button"
        onClick={() => onSort(field)}
        className={`inline-flex items-center gap-1 uppercase tracking-wide hover:text-textPrimary dark:hover:text-white ${
          active ? "text-textPrimary dark:text-white" : ""
        }`}
      >
        {label}
        {active && <span className="text-[10px]">{sort.direction === "asc" ? "▲" : "▼"}</span>}
      </button>
    </th>
  );
}

const STAT_COLUMNS = [
  { field: "speed", label: "Spd" },
  { field: "acceleration", label: "Acc" },
  { field: "agility", label: "Agi" },
  { field: "changeOfDirection", label: "CoD" },
  { field: "strength", label: "Str" },
  { field: "awareness", label: "Awr" },
];

// Short column headers for the position-specific ratings (EA's own abbreviations where they exist).
const RATING_LABELS = {
  tackle: "TAK",
  runBlock: "RBK",
  passBlock: "PBK",
  hitPower: "POW",
  blockShedding: "BSH",
  manCoverage: "MCV",
  runBlockFinesse: "RBF",
  passBlockFinesse: "PBF",
  passBlockPower: "PBP",
  runBlockPower: "RBP",
  playRecognition: "PRC",
  spectacularCatch: "SPC",
  catchInTraffic: "CIT",
  catching: "CTH",
  throwAccuracyShort: "TAS",
  throwAccuracyMid: "TAM",
  throwAccuracyDeep: "TAD",
  throwOnRun: "TOR",
  throwPower: "THP",
  carrying: "CAR",
  breakTackle: "BTK",
  kickPower: "KPW",
  kickAccuracy: "KAC",
  trucking: "TRK",
  leadBlock: "LBK",
  impactBlock: "IBK",
};

// "throwAccuracyShort" -> "Throw Accuracy Short" for anything not in the table above
const ratingLabel = (key) =>
  RATING_LABELS[key] ?? key.replace(/([A-Z])/g, " $1").replace(/^./, (c) => c.toUpperCase());

// Players pulled onto a squad board from here are portal/scouting targets on
// someone else's team, so they land as recruits tagged with this flag.
const WATCH_FLAG_NAME = "watch";

// Watched players live in this browser only (no login), keyed by the stable student id so the
// list carries across seasons.
function useWatchlist(dynastyId) {
  const key = `watchlist:${dynastyId}`;
  const [ids, setIds] = useState(() => new Set());

  useEffect(() => {
    try {
      setIds(new Set(JSON.parse(localStorage.getItem(key) ?? "[]")));
    } catch {
      setIds(new Set());
    }
  }, [key]);

  const toggle = (studentId) =>
    setIds((prev) => {
      const next = new Set(prev);
      if (next.has(studentId)) next.delete(studentId);
      else next.add(studentId);
      try {
        localStorage.setItem(key, JSON.stringify([...next]));
      } catch {
        // storage unavailable: the star still works for this visit
      }
      return next;
    });

  return [ids, toggle];
}

function squadPayload(player, seasonYear, watchFlagId) {
  const attributes = {};
  STAT_COLUMNS.forEach(({ field }) => {
    if (player[field] != null) attributes[field] = player[field];
  });
  return {
    name: player.name,
    classYear: player.classYear || null,
    devTrait: player.devTrait || null,
    overall: player.overall ?? null,
    nilAmount: player.nilAmount ?? null,
    status: "recruit",
    recruitStatus: "normal",
    attributes,
    flagIds: watchFlagId ? [watchFlagId] : [],
    notes: [player.position, player.team, seasonYear && `${seasonYear} season`].filter(Boolean).join(" · "),
  };
}

function SeasonPlayersPage() {
  const { dynastyId, seasonId } = useParams();
  const [data, setData] = useState(null);
  const [seasons, setSeasons] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filters, setFilters] = useState(emptyFilters);
  // Which pool to browse. Defaults to the portal once anyone has been marked (Mark Transfers); until then there is
  // nothing to filter to, so it starts on everyone.
  const [pool, setPool] = useState("all");
  const [watchlist, toggleWatch] = useWatchlist(dynastyId);
  const [sort, setSort] = useState({ field: "overall", direction: "desc" });
  const [activePlayer, setActivePlayer] = useState(null);
  const [addedIds, setAddedIds] = useState(() => new Set());
  const [watchFlagId, setWatchFlagId] = useState(null);
  const authed = Boolean(localStorage.getItem("jwt"));

  useEffect(() => {
    if (!authed) return;
    fetchFlags()
      .then((flags) => setWatchFlagId(flags.find((f) => f.name === WATCH_FLAG_NAME)?.id ?? null))
      .catch(() => setWatchFlagId(null));
  }, [authed]);

  useEffect(() => {
    fetchDynastyPortal(dynastyId)
      .then((portal) => setSeasons(portal.seasons ?? []))
      .catch(() => {});
  }, [dynastyId]);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetchSeasonStudentSeasons(dynastyId, seasonId)
      .then((result) => {
        setData(result);
        setPool(result.players.some((p) => p.inPortal) ? "portal" : "all");
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [dynastyId, seasonId]);

  const setFilter = (key, value) => setFilters((prev) => ({ ...prev, [key]: value }));

  const teamsById = useMemo(() => {
    const map = new Map();
    (data?.filters.teams ?? []).forEach((team) => {
      map.set(team.collegeSeasonId, {
        ...team,
        logoUrl: team.logoUrl ? `${API_BASE_URL}${team.logoUrl}` : null,
      });
    });
    return map;
  }, [data]);

  const positionOptions = useMemo(
    () =>
      [...(data?.filters.positions ?? [])]
        .sort((a, b) => positionRank(a) - positionRank(b) || a.localeCompare(b))
        .map((pos) => ({ value: pos, label: pos })),
    [data],
  );
  const classYearOptions = useMemo(
    () => (data?.filters.classYears ?? []).map((year) => ({ value: year, label: year })),
    [data],
  );
  const archetypeOptions = useMemo(() => {
    const names = [...new Set((data?.players ?? []).map((p) => p.archetype).filter(Boolean))].sort();
    return names.map((name) => ({ value: name, label: name }));
  }, [data]);
  const teamOptions = useMemo(() => {
    const teams = [...(data?.filters.teams ?? [])].sort(
      (a, b) => Number(b.coached) - Number(a.coached) || a.name.localeCompare(b.name),
    );
    return teams.map((team) => ({
      value: String(team.collegeSeasonId),
      label: team.name,
      group: team.coached ? "Your teams" : "All teams",
    }));
  }, [data]);
  const conferenceOptions = useMemo(() => {
    const names = [...new Set((data?.filters.teams ?? []).map((t) => t.conference).filter(Boolean))].sort();
    return names.map((name) => ({ value: name, label: name }));
  }, [data]);

  const filtered = useMemo(() => {
    if (!data) return [];
    const search = filters.search.trim().toLowerCase();
    const minOverall = filters.minOverall === "" ? null : Number(filters.minOverall);
    const minHeight = parseHeight(filters.minHeight);
    const maxHeight = parseHeight(filters.maxHeight);
    const minWeight = filters.minWeight === "" ? null : Number(filters.minWeight);
    const maxWeight = filters.maxWeight === "" ? null : Number(filters.maxWeight);

    const rows = data.players.filter((p) => {
      if (pool === "portal" && !p.inPortal) return false;
      if (pool === "watchlist" && !watchlist.has(p.studentId)) return false;
      if (search && !p.name.toLowerCase().includes(search)) return false;
      if (filters.positions.length && !filters.positions.includes(p.position)) return false;
      if (filters.classYears.length && !filters.classYears.includes(p.classYear)) return false;
      if (filters.teams.length && !filters.teams.includes(String(p.collegeSeasonId))) return false;
      if (filters.conferences.length && !filters.conferences.includes(p.conference)) return false;
      if (minOverall != null && (p.overall ?? -1) < minOverall) return false;
      if (filters.archetypes.length && !filters.archetypes.includes(p.archetype)) return false;
      if (minHeight != null && (p.heightInches ?? -1) < minHeight) return false;
      if (maxHeight != null && (p.heightInches == null || p.heightInches > maxHeight)) return false;
      if (minWeight != null && (p.weightLbs ?? -1) < minWeight) return false;
      if (maxWeight != null && (p.weightLbs == null || p.weightLbs > maxWeight)) return false;
      return true;
    });

    const dir = sort.direction === "asc" ? 1 : -1;
    return rows.sort((a, b) => {
      const av = sortValueFor(a, sort.field);
      const bv = sortValueFor(b, sort.field);
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      const cmp = typeof av === "string" ? av.localeCompare(bv) : av - bv;
      return cmp * dir;
    });
  }, [data, filters, sort, pool, watchlist]);

  const portalCount = useMemo(() => (data?.players ?? []).filter((p) => p.inPortal).length, [data]);

  const toggleSort = (field) =>
    setSort((prev) => {
      if (prev.field === field) return { field, direction: prev.direction === "asc" ? "desc" : "asc" };
      return { field, direction: ASCENDING_BY_DEFAULT.has(field) ? "asc" : "desc" };
    });

  const shown = filtered.slice(0, RENDER_CAP);

  // Position-specific ratings (beyond the fixed columns) become trailing columns, most common first.
  const ratingColumns = useMemo(() => {
    const fixed = new Set(STAT_COLUMNS.map((c) => c.field));
    const counts = new Map();
    shown.forEach((p) =>
      Object.keys(p.ratings ?? {}).forEach((key) => {
        if (!fixed.has(key)) counts.set(key, (counts.get(key) ?? 0) + 1);
      }),
    );
    return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([key]) => key);
  }, [shown]);
  const filtersActive =
    filters.search !== "" ||
    filters.minOverall !== "" ||
    filters.archetypes.length > 0 ||
    filters.minHeight !== "" ||
    filters.maxHeight !== "" ||
    filters.minWeight !== "" ||
    filters.maxWeight !== "" ||
    filters.positions.length > 0 ||
    filters.classYears.length > 0 ||
    filters.teams.length > 0 ||
    filters.conferences.length > 0;
  const rosterPath = (collegeSeasonId) =>
    `/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${collegeSeasonId}/roster`;

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        eyebrow={
          seasons.length > 1 ? (
            <SeasonSwitcher
              seasons={seasons}
              activeSeasonId={seasonId}
              dynastyId={dynastyId}
              suffix="/players"
              className="mb-1 normal-case tracking-normal font-sans"
            />
          ) : data ? (
            `${data.season.year} Season`
          ) : undefined
        }
        title="All Players"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading players...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="space-y-4">
          <Card className="p-4">
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Show</span>
                <select
                  value={pool}
                  onChange={(e) => setPool(e.target.value)}
                  className={inputClass}
                >
                  <option value="portal">In Portal ({portalCount.toLocaleString()})</option>
                  <option value="all">All Players</option>
                  <option value="watchlist">Watchlist ({watchlist.size.toLocaleString()})</option>
                </select>
              </label>

              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Search name</span>
                <input
                  type="text"
                  value={filters.search}
                  onChange={(e) => setFilter("search", e.target.value)}
                  placeholder="Player name"
                  className={inputClass}
                />
              </label>

              <MultiSelect
                label="Positions"
                options={positionOptions}
                selected={filters.positions}
                onChange={(vals) => setFilter("positions", vals)}
              />
              <MultiSelect
                label="Class"
                options={classYearOptions}
                selected={filters.classYears}
                onChange={(vals) => setFilter("classYears", vals)}
              />
              <MultiSelect
                label="Teams"
                options={teamOptions}
                selected={filters.teams}
                onChange={(vals) => setFilter("teams", vals)}
                searchable
              />
              <MultiSelect
                label="Conferences"
                options={conferenceOptions}
                selected={filters.conferences}
                onChange={(vals) => setFilter("conferences", vals)}
              />
              <MultiSelect
                label="Archetype"
                options={archetypeOptions}
                selected={filters.archetypes}
                onChange={(vals) => setFilter("archetypes", vals)}
                searchable
              />

              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Min OVR</span>
                <input
                  type="number"
                  min={0}
                  max={99}
                  value={filters.minOverall}
                  onChange={(e) => setFilter("minOverall", e.target.value)}
                  placeholder="e.g. 80"
                  className={inputClass}
                />
              </label>
              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Min height</span>
                <input
                  type="text"
                  value={filters.minHeight}
                  onChange={(e) => setFilter("minHeight", e.target.value)}
                  placeholder="e.g. 6'2"
                  className={inputClass}
                />
              </label>
              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Max height</span>
                <input
                  type="text"
                  value={filters.maxHeight}
                  onChange={(e) => setFilter("maxHeight", e.target.value)}
                  placeholder="e.g. 6'6"
                  className={inputClass}
                />
              </label>
              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Min weight (lbs)</span>
                <input
                  type="number"
                  value={filters.minWeight}
                  onChange={(e) => setFilter("minWeight", e.target.value)}
                  placeholder="e.g. 200"
                  className={inputClass}
                />
              </label>
              <label className="block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                <span>Max weight (lbs)</span>
                <input
                  type="number"
                  value={filters.maxWeight}
                  onChange={(e) => setFilter("maxWeight", e.target.value)}
                  placeholder="e.g. 260"
                  className={inputClass}
                />
              </label>
            </div>

            <div className="mt-3 flex items-center justify-between gap-3">
              <p className="text-sm text-textSecondary">
                {filtered.length.toLocaleString()} player{filtered.length === 1 ? "" : "s"}
                {filtered.length > RENDER_CAP && (
                  <span> &middot; showing first {RENDER_CAP} — refine filters to narrow</span>
                )}
              </p>
              {filtersActive && (
                <button
                  type="button"
                  onClick={() => setFilters(emptyFilters())}
                  className="rounded-md border border-border px-3 py-1.5 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Clear filters
                </button>
              )}
            </div>
          </Card>

          <Card className="-mx-4 overflow-hidden rounded-none border-x-0 sm:mx-0 sm:rounded-xl sm:border-x">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <SortableTh label="Player" field="name" sort={sort} onSort={toggleSort} sticky />
                    <SortableTh label="Team" field="team" sort={sort} onSort={toggleSort} align="center" />
                    <SortableTh label="OVR" field="overall" sort={sort} onSort={toggleSort} align="center" />
                    <SortableTh label="Archetype" field="archetype" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Ht" field="heightInches" sort={sort} onSort={toggleSort} align="right" />
                    <SortableTh label="Wt" field="weightLbs" sort={sort} onSort={toggleSort} align="right" />
                    {STAT_COLUMNS.map((col) => (
                      <SortableTh
                        key={col.field}
                        label={col.label}
                        field={col.field}
                        sort={sort}
                        onSort={toggleSort}
                        align="right"
                      />
                    ))}
                    {ratingColumns.map((key) => (
                      <SortableTh
                        key={key}
                        label={ratingLabel(key)}
                        field={`ratings.${key}`}
                        sort={sort}
                        onSort={toggleSort}
                        align="right"
                      />
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {shown.map((player) => {
                    const team = teamsById.get(player.collegeSeasonId);
                    return (
                      <tr key={player.id} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                        <td className="sticky left-0 z-10 bg-surface px-1 py-1 shadow-[1px_0_0_0] shadow-border/60 dark:bg-darksurface dark:shadow-darkborder/60">
                          <div className="flex items-start gap-2">
                            <button
                              type="button"
                              onClick={() => toggleWatch(player.studentId)}
                              title={watchlist.has(player.studentId) ? "Remove from watchlist" : "Add to watchlist"}
                              aria-pressed={watchlist.has(player.studentId)}
                              className={`mt-0.5 text-lg leading-none ${
                                watchlist.has(player.studentId) ? "text-warning" : "text-textSecondary/40 hover:text-warning"
                              }`}
                            >
                              {watchlist.has(player.studentId) ? "★" : "☆"}
                            </button>
                            <div>
                          {authed ? (
                            <button
                              type="button"
                              onClick={() => setActivePlayer(player)}
                              title="Add to a squad board"
                              className="whitespace-nowrap text-sm text-left font-semibold text-textPrimary hover:text-burnt hover:underline dark:text-white dark:hover:text-burnt"
                            >
                              {player.name}
                              {addedIds.has(player.id) && (
                                <span className="ml-1.5 text-xs font-normal text-success">✓ added</span>
                              )}
                            </button>
                          ) : (
                            <div className="text-sm whitespace-nowrap font-semibold text-textPrimary dark:text-white">{player.name}</div>
                          )}
                          <div className="text-xs font-normal text-textSecondary">
                            {player.position} &middot; {player.classYear}
                          </div>
                            </div>
                          </div>
                        </td>
                        <td className="px-1 py-1 text-center">
                          <Link
                            to={rosterPath(player.collegeSeasonId)}
                            title={player.team}
                            className="inline-flex items-center justify-center"
                          >
                            {team?.logoUrl ? (
                              <img
                                src={team.logoUrl}
                                alt={player.team}
                                loading="lazy"
                                className="h-8 w-8 md:h-10 md:w-10 object-contain"
                              />
                            ) : (
                              <span className="text-xs text-textSecondary hover:text-burnt">{player.team}</span>
                            )}
                          </Link>
                        </td>
                        <td className="px-1 py-1 text-center">
                          <OverallBadge value={player.overall} />
                        </td>
                        <td className="px-3 py-2 whitespace-nowrap text-textSecondary" title={player.archetype ?? undefined}>
                          {player.archetype ? shortArchetype(player.archetype) : "—"}
                        </td>
                        <td className="px-3 py-2 text-right tabular-nums text-textSecondary">
                          {formatHeight(player.heightInches)}
                        </td>
                        <td className="px-3 py-2 text-right tabular-nums text-textSecondary">{player.weightLbs ?? "—"}</td>
                        {STAT_COLUMNS.map((col) => (
                          <td key={col.field} className="px-1 py-1 text-center tabular-nums text-textSecondary">
                            {player[col.field] ?? "—"}
                          </td>
                        ))}
                        {ratingColumns.map((key) => (
                          <td key={key} className="px-1 py-1 text-center tabular-nums text-textSecondary">
                            {player.ratings?.[key] ?? "—"}
                          </td>
                        ))}
                      </tr>
                    );
                  })}
                  {shown.length === 0 && (
                    <tr>
                      <td colSpan={12 + ratingColumns.length} className="px-3 py-6 text-center text-sm text-textSecondary">
                        No players match these filters.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </Card>
        </div>
      )}

      {activePlayer && (
        <AddToSquadModal
          position={activePlayer.position}
          name={activePlayer.name}
          title="Add to Squad"
          doneTitle="Player Added"
          actionLabel="Add & watch"
          summary={
            <p className="mt-1 text-sm text-textSecondary">
              {activePlayer.position} · {activePlayer.name}
              {activePlayer.overall != null ? ` · ${activePlayer.overall} OVR` : ""} · {activePlayer.team}
            </p>
          }
          doneMessage={({ name, teamName, boardName }) => (
            <>
              Added <span className="font-semibold">{name}</span> to {teamName}
              {boardName ? ` › ${boardName}` : ""}
              {watchFlagId ? " and flagged to watch." : "."}
            </>
          )}
          buildPayload={() => squadPayload(activePlayer, data?.season.year, watchFlagId)}
          onClose={() => setActivePlayer(null)}
          onAdded={() => setAddedIds((prev) => new Set(prev).add(activePlayer.id))}
        />
      )}
    </div>
  );
}

export default SeasonPlayersPage;
