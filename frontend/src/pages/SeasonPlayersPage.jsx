import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import MultiSelect from "../components/MultiSelect";
import OverallBadge from "../components/OverallBadge";
import { API_BASE_URL, fetchSeasonStudentSeasons } from "../lib/apiClient";

// The full season pool is ~11k players — never render all of them. Filters
// narrow it down; this is just the ceiling on how many rows we paint.
const RENDER_CAP = 150;

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

// Text columns sort A→Z by default; rating columns sort high→low, since the
// top of the list is what you're looking for in the portal.
const ASCENDING_BY_DEFAULT = new Set(["name", "team", "devTrait"]);

const emptyFilters = () => ({
  search: "",
  positions: [],
  classYears: [],
  teams: [],
  conferences: [],
  minOverall: "",
});

function sortValueFor(player, field) {
  if (field === "team") return player.team;
  return player[field];
}

function SortableTh({ label, field, sort, onSort, align = "left" }) {
  const active = sort.field === field;
  return (
    <th className={`px-3 py-2 ${align === "right" ? "text-right" : align === "center" ? "text-center" : "text-left"}`}>
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

function SeasonPlayersPage() {
  const { dynastyId, seasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filters, setFilters] = useState(emptyFilters);
  const [sort, setSort] = useState({ field: "overall", direction: "desc" });

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetchSeasonStudentSeasons(dynastyId, seasonId)
      .then((result) => setData(result))
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
    () => (data?.filters.positions ?? []).map((pos) => ({ value: pos, label: pos })),
    [data],
  );
  const classYearOptions = useMemo(
    () => (data?.filters.classYears ?? []).map((year) => ({ value: year, label: year })),
    [data],
  );
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

    const rows = data.players.filter((p) => {
      if (search && !p.name.toLowerCase().includes(search)) return false;
      if (filters.positions.length && !filters.positions.includes(p.position)) return false;
      if (filters.classYears.length && !filters.classYears.includes(p.classYear)) return false;
      if (filters.teams.length && !filters.teams.includes(String(p.collegeSeasonId))) return false;
      if (filters.conferences.length && !filters.conferences.includes(p.conference)) return false;
      if (minOverall != null && (p.overall ?? -1) < minOverall) return false;
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
  }, [data, filters, sort]);

  const toggleSort = (field) =>
    setSort((prev) => {
      if (prev.field === field) return { field, direction: prev.direction === "asc" ? "desc" : "asc" };
      return { field, direction: ASCENDING_BY_DEFAULT.has(field) ? "asc" : "desc" };
    });

  const shown = filtered.slice(0, RENDER_CAP);
  const filtersActive =
    filters.search !== "" ||
    filters.minOverall !== "" ||
    filters.positions.length > 0 ||
    filters.classYears.length > 0 ||
    filters.teams.length > 0 ||
    filters.conferences.length > 0;
  const rosterPath = (collegeSeasonId) =>
    `/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${collegeSeasonId}/roster`;

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        eyebrow={data ? `${data.season.year} Season` : undefined}
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
                    <SortableTh label="Player" field="name" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Team" field="team" sort={sort} onSort={toggleSort} align="center" />
                    <SortableTh label="OVR" field="overall" sort={sort} onSort={toggleSort} align="center" />
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
                    <SortableTh label="Dev" field="devTrait" sort={sort} onSort={toggleSort} />
                    <SortableTh label="NIL" field="nilAmount" sort={sort} onSort={toggleSort} align="right" />
                  </tr>
                </thead>
                <tbody>
                  {shown.map((player) => {
                    const team = teamsById.get(player.collegeSeasonId);
                    return (
                      <tr key={player.id} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                        <td className="px-3 py-2">
                          <div className="font-semibold text-textPrimary dark:text-white">{player.name}</div>
                          <div className="text-xs font-normal text-textSecondary">
                            {player.position} &middot; {player.classYear}
                          </div>
                        </td>
                        <td className="px-3 py-2 text-center">
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
                        <td className="px-3 py-2 text-center">
                          <OverallBadge value={player.overall} />
                        </td>
                        {STAT_COLUMNS.map((col) => (
                          <td key={col.field} className="px-3 py-2 text-right tabular-nums text-textSecondary">
                            {player[col.field] ?? "—"}
                          </td>
                        ))}
                        <td className="px-3 py-2 text-textSecondary">{player.devTrait ?? "—"}</td>
                        <td className="px-3 py-2 text-right tabular-nums text-textSecondary">
                          {player.nilAmount != null ? `$${player.nilAmount.toLocaleString()}` : "—"}
                        </td>
                      </tr>
                    );
                  })}
                  {shown.length === 0 && (
                    <tr>
                      <td colSpan={11} className="px-3 py-6 text-center text-sm text-textSecondary">
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
    </div>
  );
}

export default SeasonPlayersPage;
