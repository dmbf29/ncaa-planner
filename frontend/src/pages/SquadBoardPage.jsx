import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import StatPill from "../components/StatPill";
import { fetchTeam, fetchSquadBoards } from "../lib/apiClient";

function SquadBoardPage() {
  const { id, squadId } = useParams();
  const [team, setTeam] = useState(null);
  const [boards, setBoards] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = async () => {
      try {
        const [teamData, boardsData] = await Promise.all([fetchTeam(id), fetchSquadBoards(id, squadId)]);
        setTeam(teamData);
        setBoards(boardsData);
      } catch (err) {
        setError(err.message);
      }
    };
    load();
  }, [id, squadId]);

  return (
    <div className="space-y-4">
      <PageHeader title="Squad Board" eyebrow={team ? `${team.name} · Squad ${squadId}` : "Loading..."} />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!team && !error && <p className="text-sm text-textSecondary">Loading squad...</p>}
      <div className="grid gap-4 md:grid-cols-2">
        {boards.map((board) => (
          <Card key={board.id}>
            <div className="p-5 space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs uppercase tracking-[0.14em] text-textSecondary">Position</p>
                  <h3 className="font-varsity text-xl tracking-[0.07em] uppercase">{board.name}</h3>
                </div>
                <StatPill label="Slots" value={board.slotsCount} />
              </div>
              <div className="yard-line rounded-lg border border-border bg-surface/60 p-3 text-sm text-textSecondary dark:border-darkborder dark:bg-darksurface/60">
                <p className="mb-2 font-semibold text-charcoal dark:text-white">Roster Slots</p>
                <ul className="space-y-1">
                  {(board.rosterSlots || []).map((slot) => (
                    <li key={slot.id} className="flex items-center gap-2 text-sm">
                      <span className="inline-flex h-6 w-6 items-center justify-center rounded-full bg-burnt/80 text-xs font-bold text-charcoal">
                        {slot.slotNumber}
                      </span>
                      <span className="text-textPrimary dark:text-white">Player #{slot.playerId}</span>
                    </li>
                  ))}
                  {(!board.rosterSlots || board.rosterSlots.length === 0) && (
                    <li className="text-xs text-textSecondary">No players assigned yet.</li>
                  )}
                </ul>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

export default SquadBoardPage;
