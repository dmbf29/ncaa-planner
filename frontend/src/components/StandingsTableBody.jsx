import { clsx } from "clsx";

function StandingsTableBody({ teams }) {
  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
          <th className="px-4 py-2 font-semibold">Team</th>
          <th className="px-2 py-2 font-semibold text-right">Conf</th>
          <th className="px-2 py-2 font-semibold text-right">Overall</th>
          <th className="px-4 py-2 font-semibold text-right">PF-PA</th>
        </tr>
      </thead>
      <tbody>
        {teams.map((team) => (
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
                {team.college.name}
                {team.coachedByUs && <i className="fa-solid fa-gamepad text-[10px] text-burnt/80" title="User-coached" />}
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
      </tbody>
    </table>
  );
}

export default StandingsTableBody;
