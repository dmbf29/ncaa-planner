import { useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchPlayers, fetchTeam } from "../lib/apiClient";

function GraduatesPage() {
  const { id } = useParams();
  const [team, setTeam] = useState(null);
  const [players, setPlayers] = useState([]);
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
      } catch (err) {
        setError(err.message);
      }
    };
    load();
  }, [id]);

  return (
    <div className="space-y-4">
      <PageHeader title="Graduates / Departures" eyebrow={team ? team.name : "Loading"} />
      {error && <p className="text-sm text-danger">{error}</p>}
      {!players.length && !error && <p className="text-sm text-textSecondary">No graduates or departures yet.</p>}
      <div className="grid gap-3 md:grid-cols-2">
        {players.map((p) => (
          <Card key={p.id}>
            <div className="p-4 space-y-1">
              <div className="flex items-center justify-between">
                <h3 className="font-semibold text-charcoal dark:text-white">{p.name}</h3>
                <span className="text-xs uppercase tracking-wide text-textSecondary">{p.status}</span>
              </div>
              <p className="text-sm text-textSecondary dark:text-white/70">
                Class: {p.classYear || "—"} · Dev: {p.devTrait || "—"} · OVR: {p.overall || "—"}
              </p>
              {p.archetype && <p className="text-sm text-textSecondary">Archetype: {p.archetype}</p>}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

export default GraduatesPage;
