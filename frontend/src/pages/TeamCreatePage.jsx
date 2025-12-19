import { useState } from "react";
import { useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { createTeam } from "../lib/apiClient";

function TeamCreatePage() {
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const payload = { name };
      const created = await createTeam(payload);
      navigate(`/teams/${created.id}/setup`);
    } catch (err) {
      setError(err.message || "Could not create team");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-md mx-auto">
      <PageHeader title="New Team" eyebrow="Setup" />
      <Card>
        <form onSubmit={handleSubmit} className="space-y-5 p-6">
          {error && <p className="text-sm text-danger">{error}</p>}
          <div className="space-y-2">
            <label className="text-sm font-medium text-textSecondary">Team Name</label>
            <input
              required
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm shadow-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="rounded-lg bg-burnt px-4 py-2 text-white font-semibold shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-70"
          >
            {loading ? "Creating..." : "Create"}
          </button>
        </form>
      </Card>
    </div>
  );
}

export default TeamCreatePage;
