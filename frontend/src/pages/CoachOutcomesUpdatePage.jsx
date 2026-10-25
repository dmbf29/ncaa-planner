import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchCoachInfo, updateCollegeSeasonAttributes, assignOffseasonCoach } from "../lib/apiClient";

const selectClass =
  "rounded border border-border bg-white px-2 py-1 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const OUTCOMES = [
  { value: "", label: "Not decided" },
  { value: "continued", label: "Continuing" },
  { value: "fired", label: "Fired" },
  { value: "left", label: "Leaving (new job/retired)" },
];

const STATUS_LABELS = { saving: "Saving...", saved: "Saved", error: "Couldn't save" };
const STATUS_CLASSES = { saving: "text-textSecondary", saved: "text-success", error: "text-danger" };

function OutcomeRow({ row, colleges, dynastyId, seasonId }) {
  const [outcome, setOutcome] = useState(row.coachOutcome ?? "");
  const [newCollegeId, setNewCollegeId] = useState(row.offseasonCollegeId ?? "");
  const [moveError, setMoveError] = useState(null);
  const [status, setStatus] = useState(null);
  const requestId = useRef(0);

  const handleChange = async (e) => {
    const value = e.target.value;
    const id = ++requestId.current;
    setOutcome(value);
    setStatus("saving");
    try {
      await updateCollegeSeasonAttributes(row.collegeSeasonId, { coachOutcome: value === "" ? null : value });
      if (id === requestId.current) setStatus("saved");
    } catch {
      if (id === requestId.current) setStatus("error");
    }
  };

  const handleMove = async (e) => {
    const value = e.target.value;
    const previous = newCollegeId;
    const id = ++requestId.current;
    setNewCollegeId(value);
    setMoveError(null);
    setStatus("saving");
    try {
      await assignOffseasonCoach(dynastyId, seasonId, row.coach.id, value === "" ? null : Number(value));
      if (id === requestId.current) setStatus("saved");
    } catch (err) {
      setNewCollegeId(previous);
      setMoveError(err.message);
      if (id === requestId.current) setStatus("error");
    }
  };

  const departing = outcome === "fired" || outcome === "left";

  return (
    <tr className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
      <td className="px-4 py-2">
        <p className="font-semibold">{row.coach.name}</p>
        <p className="text-xs text-textSecondary">{row.college.name}</p>
      </td>
      <td className="px-2 py-2">
        <select value={outcome} onChange={handleChange} className={selectClass}>
          {OUTCOMES.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
      </td>
      <td className="px-2 py-2">
        {departing ? (
          <>
            <select value={newCollegeId} onChange={handleMove} className={selectClass}>
              <option value="">— no new job yet —</option>
              {colleges.map((college) => (
                <option key={college.id} value={college.id}>
                  {college.name}
                </option>
              ))}
            </select>
            {moveError && <p className="mt-1 text-xs text-danger">{moveError}</p>}
          </>
        ) : (
          <span className="text-xs text-textSecondary">—</span>
        )}
      </td>
      <td className="px-3 py-2 text-xs">{status && <span className={STATUS_CLASSES[status]}>{STATUS_LABELS[status]}</span>}</td>
    </tr>
  );
}

function CoachOutcomesUpdatePage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setError("This dynasty doesn't have a season yet.");
          return;
        }
        setDynastyId(dynasty.id);
        setData(await fetchCoachInfo(dynasty.id, latestSeason.id));
      } catch (err) {
        setError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate]);

  return (
    <div className="max-w-3xl mx-auto px-4 space-y-4">
      <PageHeader
        title="Coach Outcomes"
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

      {loading && <p className="text-sm text-textSecondary">Loading...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {data && (
        <div className="space-y-4 pb-8">
          <p className="text-sm text-textSecondary">
            {data.season.year} season. Record whether each user coach keeps their job. If a coach was fired or is leaving, pick the program they now
            run: the Portal Preview and Signing Day pods use it, while this season&rsquo;s recaps keep their old team. Changes save
            automatically.
          </p>
          <Card className="overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="px-4 py-2 font-semibold">Coach</th>
                    <th className="px-2 py-2 font-semibold">Outcome</th>
                    <th className="px-2 py-2 font-semibold">New job</th>
                    <th className="px-3 py-2 font-semibold"></th>
                  </tr>
                </thead>
                <tbody>
                  {data.coaches.map((row) => (
                    <OutcomeRow key={row.collegeSeasonId} row={row} colleges={data.colleges || []} dynastyId={dynastyId} seasonId={data.season.id} />
                  ))}
                </tbody>
              </table>
            </div>
            {data.coaches.length === 0 && <p className="p-4 text-sm text-textSecondary">No user-coached teams this season.</p>}
          </Card>
        </div>
      )}
    </div>
  );
}

export default CoachOutcomesUpdatePage;
