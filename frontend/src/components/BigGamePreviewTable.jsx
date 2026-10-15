import { formatEasternDateTime } from "../lib/easternTime";

const teamLabel = (team) => `${team.ranking ? `No. ${team.ranking} ` : ""}${team.college.name}`;

// "streaming on the Sun Belt Network" -> "Sun Belt Network"
const networkName = (broadcast) => broadcast.replace(/^(showing|streaming) on (the )?/, "");

const cellClass = "px-3 py-2 align-top";

// A read-only look at the week's Big Game Breakdown before exporting it: the
// games (most lopsided to closest), kickoff and network, the house line and
// total, and each host's locked bet. Asking for it never locks anything.
function BigGamePreviewTable({ preview, loading, error }) {
  if (loading) return <p className="text-sm text-textSecondary">Loading the week&rsquo;s games...</p>;
  if (error) return <p className="text-sm text-danger">{error}</p>;
  if (!preview) return null;
  if (preview.games.length === 0) {
    return <p className="text-sm text-textSecondary">None of our coached teams has a game this week.</p>;
  }

  const hosts = preview.hosts;
  const anyUnlocked = preview.games.some((game) => !game.picksLocked);

  return (
    <div className="space-y-2">
      <div className="overflow-x-auto rounded-md border border-border dark:border-darkborder">
        <table className="w-full min-w-[40rem] text-left text-sm">
          <thead className="bg-charcoal/5 text-xs uppercase tracking-wide text-textSecondary dark:bg-white/10">
            <tr>
              <th className={cellClass}>#</th>
              <th className={cellClass}>Game</th>
              <th className={cellClass}>Kickoff (ET) &amp; network</th>
              <th className={cellClass}>Line</th>
              <th className={cellClass}>Total</th>
              {hosts.map((host) => (
                <th key={host} className={cellClass}>
                  {host}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {preview.games.map((game, index) => (
              <tr key={game.id} className="border-t border-border text-charcoal dark:border-darkborder dark:text-white">
                <td className={`${cellClass} text-textSecondary`}>{index + 1}</td>
                <td className={cellClass}>
                  {teamLabel(game.away)} @ {teamLabel(game.home)}
                  {index === preview.games.length - 1 && <span className="ml-1 text-textSecondary">(finale)</span>}
                </td>
                <td className={cellClass}>
                  {game.time ? formatEasternDateTime(game.time) : "TBD"}
                  <span className="block text-xs text-textSecondary">{networkName(game.broadcast)}</span>
                </td>
                <td className={cellClass}>
                  {game.line.favorite} -{game.line.spread}
                </td>
                <td className={cellClass}>{game.line.total}</td>
                {hosts.map((host) => (
                  <td key={host} className={cellClass}>
                    {game.picks.find((pick) => pick.host === host)?.bet ?? "—"}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-textSecondary/80">
        {anyUnlocked
          ? "Picks aren't locked yet: they're assigned the first time you export this week, and today's lines can still shift a little before then."
          : "Picks are locked for this week."}
      </p>
    </div>
  );
}

export default BigGamePreviewTable;
