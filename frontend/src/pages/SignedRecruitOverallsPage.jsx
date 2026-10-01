import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import {
  fetchDynasties,
  fetchSignedRecruitOveralls,
  commitSignedRecruitOveralls,
} from "../lib/apiClient";

const inputClass =
  "w-16 rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

function RecruitRow({ recruit, value, onChange }) {
  return (
    <tr className="border-b border-border dark:border-darkborder">
      <td className="p-2 text-sm text-charcoal dark:text-white">{recruit.name}</td>
      <td className="p-2 text-sm">{recruit.position}</td>
      <td className="p-2 text-sm">{recruit.starRating ? `${recruit.starRating}★` : "—"}</td>
      <td className="p-2 text-sm">{recruit.nationalRank ?? "—"}</td>
      <td className="p-2 text-sm">{recruit.classYear || "—"}</td>
      <td className="p-2">
        {recruit.transfer ? (
          <span className="text-sm text-textSecondary">
            {recruit.overall != null ? `${recruit.overall} (roster)` : recruit.matched ? "no rating found" : "unmatched"}
          </span>
        ) : (
          <input
            type="number"
            min="1"
            max="99"
            value={value ?? ""}
            onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
            className={inputClass}
          />
        )}
      </td>
    </tr>
  );
}

function SignedRecruitOverallsPage() {
  const navigate = useNavigate();
  const [ids, setIds] = useState({ dynastyId: null, seasonId: null });
  const [teams, setTeams] = useState([]);
  const [values, setValues] = useState({});
  const [original, setOriginal] = useState({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [saving, setSaving] = useState(false);
  const [saveMessage, setSaveMessage] = useState(null);
  const [saveError, setSaveError] = useState(null);

  const applyTeams = (loadedTeams) => {
    const initial = {};
    loadedTeams.forEach((team) =>
      team.recruits.filter((r) => !r.transfer).forEach((r) => (initial[r.id] = r.overall ?? null)),
    );
    setTeams(loadedTeams);
    setValues(initial);
    setOriginal(initial);
  };

  useEffect(() => {
    const load = async () => {
      try {
        const dynasty = (await fetchDynasties())[0];
        if (!dynasty) {
          setLoadError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setLoadError("This dynasty doesn't have a season yet.");
          return;
        }
        setIds({ dynastyId: dynasty.id, seasonId: latestSeason.id });
        const result = await fetchSignedRecruitOveralls(dynasty.id, latestSeason.id);
        applyTeams(result.teams || []);
      } catch (err) {
        setLoadError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) navigate("/auth/login");
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate]);

  const changedRows = Object.keys(values)
    .filter((id) => values[id] !== original[id])
    .map((id) => ({ id: Number(id), overall: values[id] }));

  const handleSave = async () => {
    setSaving(true);
    setSaveError(null);
    setSaveMessage(null);
    try {
      const result = await commitSignedRecruitOveralls(ids.dynastyId, ids.seasonId, changedRows);
      const warnings = result.warnings || [];
      if (warnings.length) {
        setSaveError(warnings.map((w) => `${w.recruit}: ${w.error}`).join("; "));
      } else {
        setSaveMessage(`Saved ${changedRows.length} overall${changedRows.length === 1 ? "" : "s"}.`);
      }
      const refreshed = await fetchSignedRecruitOveralls(ids.dynastyId, ids.seasonId);
      applyTeams(refreshed.teams || []);
    } catch (err) {
      setSaveError(err.message);
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="max-w-4xl mx-auto px-4">
        <p className="text-sm text-textSecondary">Loading...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="max-w-4xl mx-auto px-4">
        <p className="text-sm text-danger">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Recruit Overalls"
        eyebrow="Dynasty Updates"
        actions={
          <Link
            to="/dynasty/updates"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Updates
          </Link>
        }
      />

      <p className="text-sm text-textSecondary">
        Enter each signed high school/JUCO recruit&rsquo;s overall from the next screen. Leave it blank if you
        don&rsquo;t have it — the signing day breakdown falls back to star rating. Transfers show the rating from
        their previous roster and can&rsquo;t be edited here.
      </p>

      {teams.map((team) => (
        <Card key={team.college.id}>
          <div className="p-5 space-y-3">
            <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">
              {team.college.name}
            </h3>
            {team.recruits.length === 0 ? (
              <p className="text-sm text-textSecondary">No signed recruits logged yet.</p>
            ) : (
              <table className="w-full text-left">
                <thead>
                  <tr className="border-b border-border text-xs uppercase text-textSecondary dark:border-darkborder">
                    <th className="p-2">Name</th>
                    <th className="p-2">Pos</th>
                    <th className="p-2">Stars</th>
                    <th className="p-2">Nat&rsquo;l</th>
                    <th className="p-2">Class</th>
                    <th className="p-2">Overall</th>
                  </tr>
                </thead>
                <tbody>
                  {team.recruits.map((recruit) => (
                    <RecruitRow
                      key={recruit.id}
                      recruit={recruit}
                      value={values[recruit.id]}
                      onChange={(overall) => setValues((prev) => ({ ...prev, [recruit.id]: overall }))}
                    />
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </Card>
      ))}

      <div className="flex items-center gap-3 pb-6">
        <button
          type="button"
          onClick={handleSave}
          disabled={saving || changedRows.length === 0}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {saving ? "Saving..." : `Save${changedRows.length ? ` (${changedRows.length})` : ""}`}
        </button>
        {saveMessage && <p className="text-sm text-success">{saveMessage}</p>}
        {saveError && <p className="text-sm text-danger">{saveError}</p>}
      </div>
    </div>
  );
}

export default SignedRecruitOverallsPage;
