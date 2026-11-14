import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import MultiSelect from "../components/MultiSelect";
import { fetchRecruitSigningTeams, fetchSeason, fetchSeasonRecruits, signRecruit } from "../lib/apiClient";
import { formatHeight, parseHeight } from "../lib/height";
import useWatchlist from "../lib/useWatchlist";

// The pool is ~4,100 recruits, so only this many rows are painted at a time; "Show more" adds another page.
const PAGE_SIZE = 100;

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const labelClass = "block space-y-1 text-xs font-semibold uppercase tracking-wide text-textSecondary";

// Text columns sort A→Z by default; ranks too (1 is best). Stars, height and weight sort high→low.
const ASCENDING_BY_DEFAULT = new Set(["name", "position", "archetype", "hometown", "pipeline", "rank", "stateRank", "positionRank"]);

const SORT_OPTIONS = [
  { field: "rank", label: "National rank" },
  { field: "stars", label: "Stars" },
  { field: "name", label: "Name" },
  { field: "position", label: "Position" },
  { field: "archetype", label: "Archetype" },
  { field: "heightInches", label: "Height" },
  { field: "weightLbs", label: "Weight" },
  { field: "stateRank", label: "State rank" },
  { field: "positionRank", label: "Position rank" },
];

const emptyFilters = () => ({
  search: "",
  positions: [],
  stars: [],
  states: [],
  archetypes: [],
  pipelines: [],
  signing: "all",
  pool: "all",
  minHeight: "",
  maxHeight: "",
  minWeight: "",
  maxWeight: "",
});

const toOptions = (values) => values.map((value) => ({ value: String(value), label: String(value) }));

function SortableTh({ label, field, sort, onSort, align = "left" }) {
  const active = sort.field === field;
  return (
    <th className={`px-3 py-2 ${align === "right" ? "text-right" : align === "center" ? "text-center" : "text-left"}`}>
      <button
        type="button"
        onClick={() => onSort(field)}
        className={`inline-flex items-center gap-1 uppercase tracking-wide hover:text-textPrimary dark:hover:text-white ${active ? "text-textPrimary dark:text-white" : ""}`}
      >
        <span className="whitespace-nowrap">{label}</span>
        {active && <span className="text-[10px]">{sort.direction === "asc" ? "▲" : "▼"}</span>}
      </button>
    </th>
  );
}

function Stars({ count }) {
  return (
    <span className="whitespace-nowrap text-warning" title={`${count} stars`}>
      {"★".repeat(count)}
      <span className="text-textSecondary/30">{"★".repeat(Math.max(5 - count, 0))}</span>
    </span>
  );
}

// "Signed · Team" once a signing is recorded, else the owner's team picker and Sign button. Only the signed-in
// owner sees this: signings are tracked for user teams alone, so for anyone else "available" would mislead.
function Signing({ recruit, teams, onSign }) {
  const [collegeId, setCollegeId] = useState("");
  const [saving, setSaving] = useState(false);

  if (recruit.signedWith) {
    return <span className="inline-block rounded-full bg-success/10 px-2 py-0.5 text-xs font-semibold text-success">Signed · {recruit.signedWith}</span>;
  }
  const sign = async () => {
    setSaving(true);
    await onSign(recruit, Number(collegeId));
    setSaving(false);
  };

  return (
    <div className="flex items-center gap-2">
      <select value={collegeId} onChange={(e) => setCollegeId(e.target.value)} className={`${inputClass} min-w-0 flex-1 md:w-36 md:flex-none`} aria-label={`Team for ${recruit.name}`}>
        <option value="">Team…</option>
        {teams.map((team) => (
          <option key={team.collegeId} value={team.collegeId}>{team.name}</option>
        ))}
      </select>
      <button
        type="button"
        onClick={sign}
        disabled={!collegeId || saving}
        className="rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
      >
        {saving ? "Saving…" : "Sign"}
      </button>
    </div>
  );
}

function WatchStar({ watched, onToggle }) {
  return (
    <button
      type="button"
      onClick={onToggle}
      title={watched ? "Remove from watchlist" : "Add to watchlist"}
      aria-pressed={watched}
      className={`text-lg leading-none ${watched ? "text-warning" : "text-textSecondary/40 hover:text-warning"}`}
    >
      {watched ? "★" : "☆"}
    </button>
  );
}

function RecruitCard({ recruit, teams, onSign, watched, onToggleWatch }) {
  const showSigning = teams != null;
  return (
    <div className="space-y-1 px-4 py-2.5">
      <div className="flex items-baseline justify-between gap-3">
        <div className="flex min-w-0 items-center gap-2">
          <WatchStar watched={watched} onToggle={onToggleWatch} />
          <p className="min-w-0 truncate font-semibold text-textPrimary dark:text-white">
            <span className="mr-1.5 text-textSecondary">#{recruit.rank}</span>
            {recruit.name}
          </p>
        </div>
        <span className="whitespace-nowrap text-sm font-semibold text-warning" title={`${recruit.stars} stars`}>{recruit.stars}★</span>
      </div>
      <p className="text-sm text-textSecondary">
        {recruit.position}
        {recruit.archetype ? ` · ${recruit.archetype}` : ""}
      </p>
      <p className="text-xs text-textSecondary">
        {formatHeight(recruit.heightInches)} · {recruit.weightLbs ?? "—"} · {recruit.pipeline} · St {recruit.stateRank} · Pos {recruit.positionRank}
      </p>
      {showSigning && <div className="pt-1"><Signing recruit={recruit} teams={teams} onSign={onSign} /></div>}
    </div>
  );
}

function SeasonRecruitsPage() {
  const { dynastyId, seasonId } = useParams();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filters, setFilters] = useState(emptyFilters);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [sort, setSort] = useState({ field: "rank", direction: "asc" });
  const [shownCount, setShownCount] = useState(PAGE_SIZE);
  // The signed-in owner's coached teams, and the week a signing is recorded in; null for everyone else.
  const [teams, setTeams] = useState(null);
  const [weekNumber, setWeekNumber] = useState(null);
  const [notice, setNotice] = useState(null);
  const showSigning = teams != null;
  // Recruit ranks are only stable within a class, so each season keeps its own list.
  const [watchlist, toggleWatch] = useWatchlist(`recruit-watchlist:${dynastyId}:${seasonId}`);

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetchSeasonRecruits(dynastyId, seasonId)
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [dynastyId, seasonId]);

  useEffect(() => {
    if (!localStorage.getItem("jwt")) return;
    Promise.all([fetchRecruitSigningTeams(dynastyId, seasonId), fetchSeason(dynastyId, seasonId)])
      .then(([signing, season]) => {
        setTeams(signing.teams);
        setWeekNumber(season.currentWeekNumber);
      })
      .catch(() => setTeams(null)); // signed in, but not this dynasty's owner
  }, [dynastyId, seasonId]);

  const setFilter = (key, value) => {
    setFilters((prev) => ({ ...prev, [key]: value }));
    setShownCount(PAGE_SIZE);
  };

  const recruits = useMemo(() => data?.recruits ?? [], [data]);
  const positionOptions = useMemo(() => toOptions([...new Set(recruits.map((r) => r.position))].filter(Boolean).sort()), [recruits]);
  const starOptions = useMemo(() => [5, 4, 3, 2, 1].map((n) => ({ value: String(n), label: `${n}★` })), []);
  const stateOptions = useMemo(() => toOptions([...new Set(recruits.map((r) => r.state))].filter(Boolean).sort()), [recruits]);
  const archetypeOptions = useMemo(() => toOptions([...new Set(recruits.map((r) => r.archetype))].filter(Boolean).sort()), [recruits]);
  const pipelineOptions = useMemo(() => toOptions([...new Set(recruits.map((r) => r.pipeline))].filter(Boolean).sort()), [recruits]);

  const filtered = useMemo(() => {
    const search = filters.search.trim().toLowerCase();
    const minHeight = parseHeight(filters.minHeight);
    const maxHeight = parseHeight(filters.maxHeight);
    const minWeight = filters.minWeight === "" ? null : Number(filters.minWeight);
    const maxWeight = filters.maxWeight === "" ? null : Number(filters.maxWeight);

    const rows = recruits.filter((r) => {
      if (search && !r.name.toLowerCase().includes(search)) return false;
      if (filters.positions.length && !filters.positions.includes(r.position)) return false;
      if (filters.stars.length && !filters.stars.includes(String(r.stars))) return false;
      if (filters.states.length && !filters.states.includes(r.state)) return false;
      if (filters.archetypes.length && !filters.archetypes.includes(r.archetype)) return false;
      if (filters.pipelines.length && !filters.pipelines.includes(r.pipeline)) return false;
      if (filters.pool === "watchlist" && !watchlist.has(r.rank)) return false;
      if (filters.signing === "available" && r.signedWith) return false;
      if (filters.signing === "signed" && !r.signedWith) return false;
      if (minHeight != null && (r.heightInches ?? -1) < minHeight) return false;
      if (maxHeight != null && (r.heightInches == null || r.heightInches > maxHeight)) return false;
      if (minWeight != null && (r.weightLbs ?? -1) < minWeight) return false;
      if (maxWeight != null && (r.weightLbs == null || r.weightLbs > maxWeight)) return false;
      return true;
    });

    const dir = sort.direction === "asc" ? 1 : -1;
    return rows.sort((a, b) => {
      const av = a[sort.field];
      const bv = b[sort.field];
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      return (typeof av === "string" ? av.localeCompare(bv) : av - bv) * dir;
    });
  }, [recruits, filters, sort, watchlist]);

  const toggleSort = (field) =>
    setSort((prev) =>
      prev.field === field
        ? { field, direction: prev.direction === "asc" ? "desc" : "asc" }
        : { field, direction: ASCENDING_BY_DEFAULT.has(field) ? "asc" : "desc" },
    );

  const shown = filtered.slice(0, shownCount);
  const activeFilterCount = Object.entries(filters).filter(([key, value]) =>
    key === "signing" || key === "pool" ? value !== "all" : Array.isArray(value) ? value.length > 0 : value !== "",
  ).length;

  const sign = async (recruit, collegeId) => {
    setNotice(null);
    setError(null);
    try {
      const result = await signRecruit(dynastyId, seasonId, recruit.rank, collegeId, weekNumber);
      setData((prev) => ({
        ...prev,
        recruits: prev.recruits.map((item) => (item.rank === recruit.rank ? { ...item, signedWith: result.signedWith } : item)),
      }));
      setNotice(`${recruit.name} signed with ${result.signedWith}.`);
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div className="mx-auto max-w-6xl">
      <PageHeader
        eyebrow={data ? `${data.season.year} Recruit Class` : undefined}
        title="Recruits"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading the recruit pool (the first load can take a few seconds)...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}
      {notice && <p className="mb-4 rounded-md bg-success/10 px-3 py-2 text-sm text-success">{notice}</p>}

      {data && (
        <div className="space-y-4">
          <Card className="p-4">
            <button
              type="button"
              onClick={() => setFiltersOpen((open) => !open)}
              aria-expanded={filtersOpen}
              className="flex w-full items-center justify-between rounded-md border border-border px-3 py-2 text-sm font-semibold text-charcoal md:hidden dark:border-darkborder dark:text-white"
            >
              <span>Filters{activeFilterCount ? ` (${activeFilterCount} active)` : ""}</span>
              <i className={`fa-solid ${filtersOpen ? "fa-chevron-up" : "fa-chevron-down"}`} />
            </button>

            <div className={`${filtersOpen ? "mt-3" : "hidden"} md:mt-0 md:block`}>
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-3">
                <label className={`${labelClass} col-span-2 lg:col-span-1`}>
                  <span>Search name</span>
                  <input type="text" value={filters.search} onChange={(e) => setFilter("search", e.target.value)} placeholder="Recruit name" autoComplete="off" data-1p-ignore className={inputClass} />
                </label>
                <label className={`${labelClass} col-span-2 lg:col-span-1`}>
                  <span>Show</span>
                  <select value={filters.pool} onChange={(e) => setFilter("pool", e.target.value)} className={inputClass}>
                    <option value="all">All recruits</option>
                    <option value="watchlist">Watchlist ({watchlist.size.toLocaleString()})</option>
                  </select>
                </label>
                {showSigning && (
                  <label className={`${labelClass} col-span-2 lg:col-span-1`}>
                    <span>Signing</span>
                    <select value={filters.signing} onChange={(e) => setFilter("signing", e.target.value)} className={inputClass}>
                      <option value="all">All recruits</option>
                      <option value="available">Not signed by you</option>
                      <option value="signed">Signed by you</option>
                    </select>
                  </label>
                )}
                <MultiSelect label="Positions" options={positionOptions} selected={filters.positions} onChange={(vals) => setFilter("positions", vals)} />
                <MultiSelect label="Stars" options={starOptions} selected={filters.stars} onChange={(vals) => setFilter("stars", vals)} />
                <MultiSelect label="Archetype" options={archetypeOptions} selected={filters.archetypes} onChange={(vals) => setFilter("archetypes", vals)} searchable />
                <MultiSelect label="States" options={stateOptions} selected={filters.states} onChange={(vals) => setFilter("states", vals)} searchable />
                <MultiSelect label="Pipeline" options={pipelineOptions} selected={filters.pipelines} onChange={(vals) => setFilter("pipelines", vals)} searchable />
                <label className={labelClass}>
                  <span>Min height</span>
                  <input type="text" value={filters.minHeight} onChange={(e) => setFilter("minHeight", e.target.value)} placeholder="e.g. 6'2" className={inputClass} />
                </label>
                <label className={labelClass}>
                  <span>Max height</span>
                  <input type="text" value={filters.maxHeight} onChange={(e) => setFilter("maxHeight", e.target.value)} placeholder="e.g. 6'6" className={inputClass} />
                </label>
                <label className={labelClass}>
                  <span>Min weight (lbs)</span>
                  <input type="number" inputMode="numeric" value={filters.minWeight} onChange={(e) => setFilter("minWeight", e.target.value)} placeholder="e.g. 200" className={inputClass} />
                </label>
                <label className={labelClass}>
                  <span>Max weight (lbs)</span>
                  <input type="number" inputMode="numeric" value={filters.maxWeight} onChange={(e) => setFilter("maxWeight", e.target.value)} placeholder="e.g. 260" className={inputClass} />
                </label>
              </div>
            </div>

            <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
              <p className="text-sm text-textSecondary">
                {filtered.length.toLocaleString()} recruit{filtered.length === 1 ? "" : "s"}
              </p>
              <div className="flex items-center gap-2">
                <label className="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-textSecondary md:hidden">
                  Sort
                  <select
                    value={sort.field}
                    onChange={(e) => setSort({ field: e.target.value, direction: ASCENDING_BY_DEFAULT.has(e.target.value) ? "asc" : "desc" })}
                    className={`${inputClass} w-36 normal-case`}
                  >
                    {SORT_OPTIONS.map((option) => <option key={option.field} value={option.field}>{option.label}</option>)}
                  </select>
                </label>
                {activeFilterCount > 0 && (
                  <button
                    type="button"
                    onClick={() => { setFilters(emptyFilters()); setShownCount(PAGE_SIZE); }}
                    className="rounded-md border border-border px-3 py-1.5 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                  >
                    Clear filters
                  </button>
                )}
              </div>
            </div>
          </Card>

          <Card className="-mx-4 overflow-hidden rounded-none border-x-0 sm:mx-0 sm:rounded-xl sm:border-x">
            <div className="hidden overflow-x-auto md:block">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="w-8 px-2 py-2" aria-label="Watchlist" />
                    <SortableTh label="Nat" field="rank" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Name" field="name" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Pos" field="position" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Stars" field="stars" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Archetype" field="archetype" sort={sort} onSort={toggleSort} />
                    <SortableTh label="Ht" field="heightInches" sort={sort} onSort={toggleSort} align="right" />
                    <SortableTh label="Wt" field="weightLbs" sort={sort} onSort={toggleSort} align="right" />
                    <SortableTh label="Pipeline" field="pipeline" sort={sort} onSort={toggleSort} />
                    <SortableTh label="St" field="stateRank" sort={sort} onSort={toggleSort} align="right" />
                    <SortableTh label="Pos" field="positionRank" sort={sort} onSort={toggleSort} align="right" />
                    <SortableTh label="Hometown" field="hometown" sort={sort} onSort={toggleSort} />
                    {showSigning && <th className="px-3 py-2 text-left">Signing</th>}
                  </tr>
                </thead>
                <tbody className="text-textPrimary dark:text-white">
                  {shown.map((recruit) => (
                    <tr key={recruit.rank} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                      <td className="px-2 py-2"><WatchStar watched={watchlist.has(recruit.rank)} onToggle={() => toggleWatch(recruit.rank)} /></td>
                      <td className="px-3 py-2 font-semibold tabular-nums">{recruit.rank}</td>
                      <td className="whitespace-nowrap px-3 py-2 font-semibold">{recruit.name}</td>
                      <td className="px-3 py-2">{recruit.position}</td>
                      <td className="px-3 py-2"><Stars count={recruit.stars} /></td>
                      <td className="whitespace-nowrap px-3 py-2 text-textSecondary">{recruit.archetype ?? "—"}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-textSecondary">{formatHeight(recruit.heightInches)}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-textSecondary">{recruit.weightLbs ?? "—"}</td>
                      <td className="whitespace-nowrap px-3 py-2 text-textSecondary">{recruit.pipeline}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-textSecondary">{recruit.stateRank}</td>
                      <td className="px-3 py-2 text-right tabular-nums text-textSecondary">{recruit.positionRank}</td>
                      <td className="whitespace-nowrap px-3 py-2 text-textSecondary">{recruit.hometown}, {recruit.state}</td>
                      {showSigning && <td className="px-3 py-2"><Signing recruit={recruit} teams={teams} onSign={sign} /></td>}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div className="divide-y divide-border/60 md:hidden dark:divide-darkborder/60">
              {shown.map((recruit) => (
                <RecruitCard key={recruit.rank} recruit={recruit} teams={teams} onSign={sign} watched={watchlist.has(recruit.rank)} onToggleWatch={() => toggleWatch(recruit.rank)} />
              ))}
            </div>

            {shown.length === 0 && <p className="px-3 py-6 text-center text-sm text-textSecondary">No recruits match these filters.</p>}

            {filtered.length > shown.length && (
              <div className="flex items-center justify-between gap-3 border-t border-border p-4 text-sm text-textSecondary dark:border-darkborder">
                <span>Showing {shown.length.toLocaleString()} of {filtered.length.toLocaleString()}</span>
                <button
                  type="button"
                  onClick={() => setShownCount((count) => count + PAGE_SIZE)}
                  className="rounded-md border border-border px-3 py-1.5 text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
                >
                  Show more
                </button>
              </div>
            )}
          </Card>
        </div>
      )}
    </div>
  );
}

export default SeasonRecruitsPage;
