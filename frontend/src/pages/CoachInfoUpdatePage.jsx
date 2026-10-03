import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchCoachInfo, updateCoach } from "../lib/apiClient";

const inputClass =
  "w-28 rounded border border-border bg-white px-2 py-1 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const STATUS_LABELS = { saving: "Saving...", saved: "Saved", error: "Couldn't save" };
const STATUS_CLASSES = { saving: "text-textSecondary", saved: "text-success", error: "text-danger" };

// Mirrors CollegeSeason#job_security_label on the backend (shown live while typing).
function jobSecurityLabel(value) {
  if (value == null) return null;
  if (value >= 80) return "Safe";
  if (value >= 65) return "Safe for Now";
  if (value >= 50) return "Low";
  return "Hot Seat";
}

const LABEL_CLASSES = {
  Safe: "text-success",
  "Safe for Now": "text-olive",
  Low: "text-warning",
  "Hot Seat": "text-danger",
};

function CoachRow({ row }) {
  const [values, setValues] = useState({ nilAmount: row.coach.nilAmount, jobSecurity: row.coach.jobSecurity });
  const [status, setStatus] = useState(null);
  const saveTimer = useRef(null);

  useEffect(() => () => saveTimer.current && clearTimeout(saveTimer.current), []);

  const update = (patch) => {
    const next = { ...values, ...patch };
    setValues(next);
    if (saveTimer.current) clearTimeout(saveTimer.current);
    setStatus("saving");
    saveTimer.current = setTimeout(async () => {
      try {
        await updateCoach(row.coach.id, next);
        setStatus("saved");
      } catch {
        setStatus("error");
      }
    }, 600);
  };

  const toNumber = (e) => (e.target.value === "" ? null : Number(e.target.value));
  const label = jobSecurityLabel(values.jobSecurity);

  return (
    <tr className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
      <td className="px-4 py-2">
        <p className="font-semibold">{row.coach.name}</p>
        <p className="text-xs text-textSecondary">{row.college.name}</p>
      </td>
      <td className="px-2 py-2">
        <input
          type="number"
          min={0}
          value={values.nilAmount ?? ""}
          onChange={(e) => update({ nilAmount: toNumber(e) })}
          className={inputClass}
        />
      </td>
      <td className="px-2 py-2">
        <input
          type="number"
          min={0}
          max={100}
          value={values.jobSecurity ?? ""}
          onChange={(e) => update({ jobSecurity: toNumber(e) })}
          className={`${inputClass} w-20`}
        />
        <span className="ml-1 text-sm text-textSecondary">%</span>
      </td>
      <td className={`px-2 py-2 text-sm font-semibold ${LABEL_CLASSES[label] || ""}`}>{label}</td>
      <td className="px-3 py-2 text-xs">{status && <span className={STATUS_CLASSES[status]}>{STATUS_LABELS[status]}</span>}</td>
    </tr>
  );
}

function CoachInfoUpdatePage() {
  const navigate = useNavigate();

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
    <div className="max-w-4xl mx-auto px-4 space-y-4">
      <PageHeader
        title="Coach Info"
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
            {data.season.year} season. Changes save automatically as you type.
          </p>
          <Card className="overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="px-4 py-2 font-semibold">Coach</th>
                    <th className="px-2 py-2 font-semibold">NIL Amount</th>
                    <th className="px-2 py-2 font-semibold">Job Security</th>
                    <th className="px-2 py-2 font-semibold">Status</th>
                    <th className="px-3 py-2 font-semibold"></th>
                  </tr>
                </thead>
                <tbody>
                  {data.coaches.map((row) => (
                    <CoachRow key={row.coach.id} row={row} />
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

export default CoachInfoUpdatePage;
