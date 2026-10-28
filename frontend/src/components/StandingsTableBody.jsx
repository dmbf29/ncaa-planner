import { Fragment } from "react";
import { clsx } from "clsx";
import { Link } from "react-router-dom";

// Teams arrive sorted best-first, so grouping by division keeps each division
// ordered and its first team is the division leader. A conference with no
// divisions set renders as a single ungrouped table.
function groupByDivision(teams) {
  if (!teams.some((team) => team.division)) return [{ division: null, teams }];

  const groups = new Map();
  teams.forEach((team) => {
    const key = team.division || "No division";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(team);
  });
  return [...groups].sort(([a], [b]) => a.localeCompare(b)).map(([division, rows]) => ({ division, teams: rows }));
}

function StandingsTableBody({ teams, dynastyId, seasonId }) {
  const canLinkToRoster = Boolean(dynastyId && seasonId);
  const groups = groupByDivision(teams);
  return (
    <table className="w-full text-xs md:text-sm">
      <thead>
        <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
          <th className="px-4 py-2 font-semibold">Team</th>
          <th className="px-2 py-2 font-semibold text-right">Conf</th>
          <th className="px-2 py-2 font-semibold text-right">Overall</th>
          <th className="px-4 py-2 font-semibold text-right">PF-PA</th>
        </tr>
      </thead>
      <tbody>
        {groups.map((group) => (
          <Fragment key={group.division ?? "all"}>
            {group.division && (
              <tr className="border-b border-border bg-border/30 dark:border-darkborder dark:bg-white/5">
                <td colSpan={4} className="px-4 py-1.5 text-xs font-semibold uppercase tracking-wide text-textSecondary">
                  {group.division}
                </td>
              </tr>
            )}
            {group.teams.map((team) => (
          <tr
            key={team.id}
            className={clsx(
              "border-b border-border/60 last:border-0 dark:border-darkborder/60",
              team.coachedByUs && "bg-burnt/10 font-semibold",
            )}
          >
            <td className="px-4 py-2">
              <span className="flex items-center gap-1.5">
                {team.rank && <span className="text-textSecondary">#{team.rank}</span>}
                {canLinkToRoster ? (
                  <Link
                    to={`/dynasty/${dynastyId}/seasons/${seasonId}/college_seasons/${team.id}/roster`}
                    className="hover:text-burnt hover:underline"
                  >
                    {team.college.name}
                  </Link>
                ) : (
                  team.college.name
                )}
                {team.coachedByUs && <i className="fa-solid fa-gamepad text-[10px] text-burnt/80" title="User-coached" />}
                {team.playerCount === 0 && (
                  <i
                    className="fa-solid fa-triangle-exclamation text-[11px] text-warning"
                    title="No players — roster needs uploading"
                  />
                )}
              </span>
            </td>
            <td className="px-2 py-1.5 text-right text-textSecondary">
              {team.conferenceWins ?? 0}-{team.conferenceLosses ?? 0}
            </td>
            <td className="px-2 py-1.5 text-right">
              {team.wins ?? 0}-{team.losses ?? 0}
            </td>
            <td className="px-4 py-1.5 text-right text-textSecondary">
              {team.pointsFor ?? "—"}-{team.pointsAgainst ?? "—"}
            </td>
          </tr>
            ))}
          </Fragment>
        ))}
      </tbody>
    </table>
  );
}

export default StandingsTableBody;
