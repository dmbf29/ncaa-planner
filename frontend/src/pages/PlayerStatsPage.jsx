import { useEffect, useState } from "react";
import { Link, useParams, useSearchParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynastyTeams, fetchPlayerStats } from "../lib/apiClient";
import { PLAYER_FIELD_LABELS } from "../lib/gameStatFields";

const CATEGORY_LABELS = { passing: "Passing", rushing: "Rushing", receiving: "Receiving", defense: "Defense" };

const CATEGORY_COLUMNS = {
  passing: [
    "passingCompletions", "passingAttempts", "passingAvg", "passingYards", "passingTds", "passingInterceptions",
    "passingSacksTaken", "passingLongest", "passingRating",
  ],
  rushing: ["rushingCarries", "rushingYards", "rushingTds", "rushingFumbles", "rushingYac", "rushingLongest", "rushingAvg"],
  receiving: ["receivingReceptions", "receivingYards", "receivingTds", "receivingRac", "receivingDrop", "receivingLongest", "receivingAvg"],
  defense: [
    "defenseSoloTackles", "defenseAssistTackles", "defenseTackles", "defenseTfl", "defenseSacks",
    "defenseInterceptions", "defenseInterceptionsLongest",
  ],
};

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const tabButtonClass = (active) =>
  `flex-1 rounded-md px-3 py-2 text-sm font-semibold uppercase tracking-wide transition ${
    active
      ? "bg-burnt text-white"
      : "border border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
  }`;

const encodeScope = (scope) => {
  if (scope.type === "college") return `college:${scope.collegeId}`;
  if (scope.type === "conference") return `conference:${scope.conference}`;
  if (scope.type === "coached") return "coached";
  return "national";
};

const decodeScope = (value) => {
  if (value === "national") return { type: "national" };
  if (value === "coached") return { type: "coached" };
  if (value.startsWith("college:")) return { type: "college", collegeId: Number(value.slice("college:".length)) };
  return { type: "conference", conference: value.slice("conference:".length) };
};

const defaultScope = (teams) => {
  const firstCoached = teams.find((team) => team.coached);
  return firstCoached ? { type: "college", collegeId: firstCoached.id } : { type: "national" };
};

function ScopeSelect({ teams, conferences, value, onChange }) {
  const coached = teams.filter((t) => t.coached);
  const others = teams.filter((t) => !t.coached);

  return (
    <select
      value={encodeScope(value)}
      onChange={(e) => onChange(decodeScope(e.target.value))}
      className={`${inputClass} max-w-xs`}
    >
      <option value="national">National</option>
      {coached.length > 0 && (
        <>
          <option value="coached">My Teams</option>
          <optgroup label="Your Teams">
            {coached.map((team) => (
              <option key={team.id} value={`college:${team.id}`}>
                {team.name}
              </option>
            ))}
          </optgroup>
        </>
      )}
      {conferences.length > 0 && (
        <optgroup label="Conferences">
          {conferences.map((conference) => (
            <option key={conference} value={`conference:${conference}`}>
              {conference}
            </option>
          ))}
        </optgroup>
      )}
      <optgroup label="All Teams">
        {others.map((team) => (
          <option key={team.id} value={`college:${team.id}`}>
            {team.name}
          </option>
        ))}
      </optgroup>
    </select>
  );
}

// Text columns (name/position/team/seasons) sort ascending by default;
// stat columns sort descending by default, since a bigger number is what
// you want to see first.
const ASCENDING_BY_DEFAULT = new Set([ "name", "position", "team", "seasons" ]);

function sortValueFor(player, field) {
  if (field === "name") return player.name;
  if (field === "position") return player.position;
  if (field === "team") return player.college?.name;
  if (field === "seasons") return player.years?.length;
  if (field === "gamesPlayed") return player.totals.gamesPlayed;
  return player.totals[field];
}

function SortableTh({ label, field, sort, onSort, align }) {
  const active = sort?.field === field;

  return (
    <th className={`px-3 py-2 ${align === "center" ? "text-center" : "text-left"}`}>
      <button
        type="button"
        onClick={() => onSort(field)}
        className={`inline-flex items-center gap-1 uppercase tracking-wide hover:text-textPrimary dark:hover:text-white ${
          align === "center" ? "justify-center" : "justify-start"
        } ${active ? "text-textPrimary dark:text-white" : ""}`}
      >
        {label}
        {active && <span className="text-[10px]">{sort.direction === "asc" ? "▲" : "▼"}</span>}
      </button>
    </th>
  );
}

function StatCategoryTable({ category, players, showSeasons, showTeam }) {
  const [sort, setSort] = useState(null);

  if (!players || players.length === 0) return null;

  const columns = CATEGORY_COLUMNS[category];

  const toggleSort = (field) => {
    setSort((prev) => {
      if (prev?.field === field) return { field, direction: prev.direction === "asc" ? "desc" : "asc" };
      return { field, direction: ASCENDING_BY_DEFAULT.has(field) ? "asc" : "desc" };
    });
  };

  const sortedPlayers = sort
    ? [ ...players ].sort((a, b) => {
        const av = sortValueFor(a, sort.field);
        const bv = sortValueFor(b, sort.field);
        if (av == null && bv == null) return 0;
        if (av == null) return 1;
        if (bv == null) return -1;

        const cmp = typeof av === "string" ? av.localeCompare(bv) : av - bv;
        return sort.direction === "asc" ? cmp : -cmp;
      })
    : players;

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-white">{CATEGORY_LABELS[category]}</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <SortableTh label="Player" field="name" sort={sort} onSort={toggleSort} align="left" />
              {showTeam && <SortableTh label="Team" field="team" sort={sort} onSort={toggleSort} align="left" />}
              <SortableTh label="Pos" field="position" sort={sort} onSort={toggleSort} align="left" />
              {showSeasons && (
                <SortableTh label="Seasons" field="seasons" sort={sort} onSort={toggleSort} align="left" />
              )}
              <SortableTh label="GP" field="gamesPlayed" sort={sort} onSort={toggleSort} align="center" />
              {columns.map((field) => (
                <SortableTh
                  key={field}
                  label={PLAYER_FIELD_LABELS[field]}
                  field={field}
                  sort={sort}
                  onSort={toggleSort}
                  align="center"
                />
              ))}
            </tr>
          </thead>
          <tbody>
            {sortedPlayers.map((player) => (
              <tr
                key={player.studentSeasonId ?? player.studentId}
                className="border-b border-border last:border-b-0 dark:border-darkborder"
              >
                <td className="px-3 py-2 font-semibold text-textPrimary dark:text-white">{player.name}</td>
                {showTeam && <td className="px-3 py-2 text-textSecondary">{player.college.name}</td>}
                <td className="px-3 py-2 text-textSecondary">{player.position}</td>
                {showSeasons && <td className="px-3 py-2 text-textSecondary">{player.years.join(", ")}</td>}
                <td className="px-3 py-2 text-center text-textSecondary">{player.totals.gamesPlayed}</td>
                {columns.map((field) => (
                  <td key={field} className="px-3 py-2 text-center text-textPrimary dark:text-white">
                    {player.totals[field] ?? "—"}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function scopeTitle(scope) {
  if (scope.type === "college") return scope.college.name;
  if (scope.type === "conference") return `${scope.conference} Conference`;
  if (scope.type === "coached") return "My Teams";
  return "National";
}

function PlayerStatsPage() {
  const { dynastyId } = useParams();
  const [searchParams] = useSearchParams();
  const [teams, setTeams] = useState(null);
  const [conferences, setConferences] = useState([]);
  const [selectedScope, setSelectedScope] = useState(() => {
    const fromQuery = searchParams.get("collegeId");
    return fromQuery ? { type: "college", collegeId: Number(fromQuery) } : null;
  });
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [tab, setTab] = useState("season");
  const [selectedYear, setSelectedYear] = useState(null);

  useEffect(() => {
    fetchDynastyTeams(dynastyId)
      .then((result) => {
        setTeams(result.teams);
        setConferences(result.conferences);
        setSelectedScope((prev) => {
          if (prev?.type === "college" && !result.teams.some((team) => team.id === prev.collegeId)) {
            return defaultScope(result.teams);
          }
          return prev ?? defaultScope(result.teams);
        });
      })
      .catch((err) => setError(err.message));
  }, [dynastyId]);

  useEffect(() => {
    if (!selectedScope) return undefined;

    setLoading(true);
    setError(null);
    fetchPlayerStats(dynastyId, selectedScope)
      .then((result) => {
        setData(result);
        setSelectedYear(result.seasons.at(-1)?.year ?? null);
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, [dynastyId, selectedScope]);

  const selectedSeason = data?.seasons.find((s) => s.year === selectedYear);
  const showTeamColumn = data?.scope.type !== "college";
  const hasAnyStats =
    data &&
    (data.seasons.some((s) => Object.values(s.categories).some((rows) => rows.length > 0)) ||
      Object.values(data.clubHistory.categories).some((rows) => rows.length > 0));

  return (
    <div className="max-w-5xl mx-auto px-4">
      <PageHeader
        title={data ? `${scopeTitle(data.scope)} Player Stats` : "Player Stats"}
        actions={
          <Link
            to={`/dynasty/${dynastyId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            &larr; Back to Dashboard
          </Link>
        }
      />

      {teams && selectedScope && (
        <div className="flex flex-wrap items-center justify-between gap-3">
          <ScopeSelect teams={teams} conferences={conferences} value={selectedScope} onChange={setSelectedScope} />
          {tab === "season" && data && (
            <select
              value={selectedYear ?? ""}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
              className={`${inputClass} max-w-[120px]`}
            >
              {data.seasons.map((s) => (
                <option key={s.year} value={s.year}>
                  {s.year}
                </option>
              ))}
            </select>
          )}
        </div>
      )}

      <div className="mt-4">
        {loading && <p className="text-sm text-textSecondary">Loading player stats...</p>}
        {error && <p className="text-sm text-danger">{error}</p>}

        {data && !hasAnyStats && <p className="text-sm text-textSecondary">No player stats recorded yet.</p>}

        {data && hasAnyStats && (
          <div className="space-y-4">
            <div className="flex gap-2">
              <button type="button" className={tabButtonClass(tab === "season")} onClick={() => setTab("season")}>
                Per Season
              </button>
              <button type="button" className={tabButtonClass(tab === "history")} onClick={() => setTab("history")}>
                Club History
              </button>
            </div>

            {tab === "season" && (
              <div className="space-y-4">
                {selectedSeason && Object.values(selectedSeason.categories).every((rows) => rows.length === 0) && (
                  <p className="text-sm text-textSecondary">No player stats recorded for this season.</p>
                )}

                {Object.keys(CATEGORY_LABELS).map((category) => (
                  <StatCategoryTable
                    key={category}
                    category={category}
                    players={selectedSeason?.categories[category]}
                    showTeam={showTeamColumn}
                  />
                ))}
              </div>
            )}

            {tab === "history" && (
              <div className="space-y-4">
                {Object.keys(CATEGORY_LABELS).map((category) => (
                  <StatCategoryTable
                    key={category}
                    category={category}
                    players={data.clubHistory.categories[category]}
                    showSeasons
                    showTeam={showTeamColumn}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default PlayerStatsPage;
