import { useEffect, useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { calculateTeamRatings, fetchTeamRatings } from "../lib/apiClient";

const RATINGS = [
  { key: "overall", label: "OVR" },
  { key: "offense", label: "OFF" },
  { key: "defense", label: "DEF" },
];

const diff = (team, key) => {
  const starter = team[`starter${key[0].toUpperCase()}${key.slice(1)}`];
  return starter == null || team[key] == null ? null : starter - team[key];
};

const columns = [
  { id: "name", label: "Team", value: (t) => t.college.name },
  ...RATINGS.map(({ key, label }) => ({ id: `game-${key}`, label, group: "In-game", value: (t) => t[key] })),
  ...RATINGS.map(({ key, label }) => ({
    id: `starter-${key}`,
    label,
    group: "Starters",
    value: (t) => t[`starter${key[0].toUpperCase()}${key.slice(1)}`],
  })),
  ...RATINGS.map(({ key, label }) => ({ id: `diff-${key}`, label, group: "Difference", value: (t) => diff(t, key) })),
  { id: "conference", label: "Conf", value: (t) => t.conference },
  { id: "prestige", label: "Prestige", value: (t) => t.prestige },
];

const format = (value, signed = false) => {
  if (value == null) return "—";
  const text = Number.isInteger(value) ? String(value) : value.toFixed(1);
  return signed && value > 0 ? `+${text}` : text;
};

const diffClass = (value) => {
  if (value == null || Math.abs(value) < 0.5) return "";
  return value > 0 ? "text-success" : "text-danger";
};

function TeamRatingsPage() {
  const { dynastyId, seasonId } = useParams();
  const authed = Boolean(localStorage.getItem("jwt"));

  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [calculating, setCalculating] = useState(false);
  const [error, setError] = useState(null);
  const [sort, setSort] = useState({ id: "starter-overall", direction: "desc" });
  const [conference, setConference] = useState("");
  const [rankedOnly, setRankedOnly] = useState(false);
  const [opponentsOf, setOpponentsOf] = useState("");
  const [showRanges, setShowRanges] = useState(false);
  const [ranges, setRanges] = useState({});

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        setData(await fetchTeamRatings(dynastyId, seasonId));
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [dynastyId, seasonId]);

  const calculate = async () => {
    setCalculating(true);
    setError(null);
    try {
      setData(await calculateTeamRatings(dynastyId, seasonId));
    } catch (err) {
      setError(err.message);
    } finally {
      setCalculating(false);
    }
  };

  const conferences = useMemo(
    () => (data ? [...new Set(data.teams.map((t) => t.conference).filter(Boolean))].sort() : []),
    [data],
  );

  const setRange = (id, bound, value) =>
    setRanges((current) => ({ ...current, [id]: { ...current[id], [bound]: value } }));

  const sortedTeams = useMemo(() => {
    if (!data) return [];
    const column = columns.find((c) => c.id === sort.id);
    const factor = sort.direction === "asc" ? 1 : -1;
    const coached = data.coachedTeams.find((c) => String(c.collegeId) === opponentsOf);
    const opponents = coached ? new Set([coached.collegeId, ...coached.opponentCollegeIds]) : null;
    const filled = (bound) => bound !== "" && bound != null;
    const active = Object.entries(ranges).filter(([, { min, max }]) => filled(min) || filled(max));
    const visible = data.teams.filter((team) => {
      if (conference && team.conference !== conference) return false;
      if (rankedOnly && team.rank == null) return false;
      if (opponents && !opponents.has(team.college.id)) return false;
      return active.every(([id, { min, max }]) => {
        const value = columns.find((c) => c.id === id).value(team);
        if (value == null) return false;
        return (min === "" || min == null || value >= Number(min)) && (max === "" || max == null || value <= Number(max));
      });
    });
    return visible.sort((a, b) => {
      const left = column.value(a);
      const right = column.value(b);
      if (left == null && right == null) return a.college.name.localeCompare(b.college.name);
      if (left == null) return 1;
      if (right == null) return -1;
      if (left === right) return a.college.name.localeCompare(b.college.name);
      return (typeof left === "string" ? left.localeCompare(right) : left - right) * factor;
    });
  }, [data, sort, conference, rankedOnly, opponentsOf, ranges]);

  const toggleSort = (id) =>
    setSort((current) =>
      current.id === id
        ? { id, direction: current.direction === "desc" ? "asc" : "desc" }
        : { id, direction: id === "name" || id === "conference" ? "asc" : "desc" },
    );

  const groups = [
    { label: "", span: 1 },
    { label: "In-game (from the game)", span: 3 },
    { label: "Starters (calculated)", span: 3 },
    { label: "Difference (starters minus in-game)", span: 3 },
    { label: "", span: 2 },
  ];

  return (
    <div className="mx-auto max-w-[1420px]">
      <PageHeader
        title="Team Ratings"
        eyebrow="Dynasty"
        actions={
          <Link
            to={`/dynasty/${dynastyId}/seasons/${seasonId}`}
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dynasty
          </Link>
        }
      />

      {loading && <p className="text-sm text-textSecondary">Loading...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="space-y-4 pb-8">
          <div className="flex flex-wrap items-center gap-3">
            {authed && (
              <button
                type="button"
                onClick={calculate}
                disabled={calculating}
                className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
              >
                {calculating ? "Calculating..." : "Calculate starter ratings"}
              </button>
            )}
            <p className="text-sm text-textSecondary">
              {data.season.year} season.{" "}
              {data.calculatedAt
                ? `Last calculated ${new Date(data.calculatedAt).toLocaleString()}.`
                : "Not calculated yet."}{" "}
              Starter ratings average each team&apos;s 11 best players per side (QB counts double), from the current
              rosters.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-3 text-sm">
            <label className="flex items-center gap-2">
              <span className="text-textSecondary">Conference</span>
              <select
                value={conference}
                onChange={(e) => setConference(e.target.value)}
                className="rounded border border-border bg-white px-2 py-1 dark:border-darkborder dark:bg-darksurface"
              >
                <option value="">All</option>
                {conferences.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </label>
            {data.coachedTeams.length > 0 && (
              <label className="flex items-center gap-2">
                <span className="text-textSecondary">Schedule of</span>
                <select
                  value={opponentsOf}
                  onChange={(e) => setOpponentsOf(e.target.value)}
                  className="rounded border border-border bg-white px-2 py-1 dark:border-darkborder dark:bg-darksurface"
                >
                  <option value="">Anyone</option>
                  {data.coachedTeams.map((team) => (
                    <option key={team.collegeId} value={team.collegeId}>
                      {team.collegeName} ({team.coachName})
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label className="flex items-center gap-2">
              <input type="checkbox" checked={rankedOnly} onChange={(e) => setRankedOnly(e.target.checked)} />
              <span>Ranked only</span>
            </label>
            <button type="button" onClick={() => setShowRanges((open) => !open)} className="text-burnt hover:underline">
              {showRanges ? "Hide min/max filters" : "Min/max filters"}
            </button>
            <span className="text-textSecondary">{sortedTeams.length} teams</span>
            {(conference || rankedOnly || opponentsOf || Object.values(ranges).some((r) => r.min || r.max)) && (
              <button
                type="button"
                onClick={() => {
                  setConference("");
                  setRankedOnly(false);
                  setOpponentsOf("");
                  setRanges({});
                }}
                className="text-burnt hover:underline"
              >
                Clear filters
              </button>
            )}
          </div>

          <Card className="-mx-4 overflow-x-auto rounded-none p-0 sm:mx-0 sm:rounded-lg">
            <table className="w-full min-w-[820px] text-sm">
              <thead>
                <tr className="text-xs uppercase tracking-wide text-textSecondary">
                  {groups.map((group, index) => (
                    <th key={index} colSpan={group.span} className="px-2 pt-2 text-center font-semibold">
                      {group.label}
                    </th>
                  ))}
                </tr>
                <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                  {columns.map((column) => (
                    <th
                      key={column.id}
                      className={`cursor-pointer select-none whitespace-nowrap px-2 py-2 font-semibold hover:text-burnt ${
                        column.id === "name" || column.id === "conference" ? "text-left" : "text-center"
                      } ${column.id === "name" ? "sticky left-0 bg-white dark:bg-darksurface" : ""}`}
                      onClick={() => toggleSort(column.id)}
                    >
                      {column.label}
                      {sort.id === column.id ? (sort.direction === "desc" ? " ▼" : " ▲") : ""}
                    </th>
                  ))}
                </tr>
                <tr className={`border-b border-border dark:border-darkborder ${showRanges ? "" : "hidden"}`}>
                  {columns.map((column) => (
                    <th key={column.id} className="px-1 pb-2 font-normal">
                      {column.id !== "name" && column.id !== "conference" && (
                        <div className="flex justify-center gap-1">
                          {["min", "max"].map((bound) => (
                            <input
                              key={bound}
                              type="number"
                              step="any"
                              placeholder={bound}
                              value={ranges[column.id]?.[bound] ?? ""}
                              onChange={(e) => setRange(column.id, bound, e.target.value)}
                              aria-label={`${column.group ? `${column.group} ` : ""}${column.label} ${bound}`}
                              className="w-14 rounded border border-border bg-transparent px-1 py-0.5 text-center text-xs dark:border-darkborder"
                            />
                          ))}
                        </div>
                      )}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {sortedTeams.map((team) => (
                  <tr key={team.id} className="border-b border-border/50 last:border-0 dark:border-darkborder/50">
                    {columns.map((column) => {
                      const value = column.value(team);
                      const isDiff = column.id.startsWith("diff-");
                      if (column.id === "name" || column.id === "conference") {
                        return (
                          <td
                            key={column.id}
                            className={`whitespace-nowrap px-2 py-1.5 text-left ${
                              column.id === "name" ? "sticky left-0 bg-white dark:bg-darksurface" : ""
                            }`}
                          >
                            {column.id === "name" && team.rank != null && (
                              <span className="mr-1.5 text-xs font-semibold text-burnt">#{team.rank}</span>
                            )}
                            {value ?? "—"}
                          </td>
                        );
                      }
                      return (
                        <td
                          key={column.id}
                          className={`px-2 py-1.5 text-center tabular-nums ${isDiff ? diffClass(value) : ""}`}
                        >
                          {format(value, isDiff)}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </div>
      )}
    </div>
  );
}

export default TeamRatingsPage;
