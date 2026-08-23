import { useEffect, useRef, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchTeamAttributes, updateCollegeSeasonAttributes } from "../lib/apiClient";

const inputClass =
  "w-16 rounded border border-transparent bg-transparent px-1.5 py-1 text-sm text-textPrimary focus:border-burnt focus:bg-white focus:outline-none dark:text-white dark:focus:bg-darksurface";

const STATUS_LABELS = {
  saving: "Saving...",
  saved: "Saved",
  error: "Couldn't save",
};

const STATUS_CLASSES = {
  saving: "text-textSecondary",
  saved: "text-success",
  error: "text-danger",
};

function AttributeInput({ value, onChange, step = 1 }) {
  return (
    <input
      type="number"
      step={step}
      value={value ?? ""}
      onChange={(e) => onChange(e.target.value === "" ? null : Number(e.target.value))}
      className={inputClass}
    />
  );
}

function TeamAttributesRow({ team }) {
  const [values, setValues] = useState({
    overall: team.overall,
    offense: team.offense,
    defense: team.defense,
    prestige: team.prestige,
  });
  const [status, setStatus] = useState(null);
  const saveTimer = useRef(null);

  useEffect(() => () => saveTimer.current && clearTimeout(saveTimer.current), []);

  const scheduleSave = (nextValues) => {
    if (saveTimer.current) clearTimeout(saveTimer.current);
    setStatus("saving");
    saveTimer.current = setTimeout(async () => {
      try {
        await updateCollegeSeasonAttributes(team.id, nextValues);
        setStatus("saved");
      } catch {
        setStatus("error");
      }
    }, 600);
  };

  const update = (patch) => {
    const next = { ...values, ...patch };
    setValues(next);
    scheduleSave(next);
  };

  return (
    <tr className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
      <td className="px-4 py-1.5">{team.college.name}</td>
      <td className="px-2 py-1.5">
        <AttributeInput value={values.overall} onChange={(overall) => update({ overall })} />
      </td>
      <td className="px-2 py-1.5">
        <AttributeInput value={values.offense} onChange={(offense) => update({ offense })} />
      </td>
      <td className="px-2 py-1.5">
        <AttributeInput value={values.defense} onChange={(defense) => update({ defense })} />
      </td>
      <td className="px-2 py-1.5">
        <AttributeInput value={values.prestige} onChange={(prestige) => update({ prestige })} step={0.5} />
      </td>
      <td className="px-3 py-1.5 text-xs">
        {status && <span className={STATUS_CLASSES[status]}>{STATUS_LABELS[status]}</span>}
      </td>
    </tr>
  );
}

function ConferenceAttributesTable({ conference }) {
  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">{conference.conference}</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="px-4 py-2 font-semibold">Team</th>
              <th className="px-2 py-2 font-semibold">Overall</th>
              <th className="px-2 py-2 font-semibold">Offense</th>
              <th className="px-2 py-2 font-semibold">Defense</th>
              <th className="px-2 py-2 font-semibold">Prestige</th>
              <th className="px-3 py-2 font-semibold"></th>
            </tr>
          </thead>
          <tbody>
            {conference.teams.map((team) => (
              <TeamAttributesRow key={team.id} team={team} />
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function TeamAttributesPage() {
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
        setData(await fetchTeamAttributes(dynasty.id, latestSeason.id));
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
    <div className="max-w-5xl mx-auto px-4">
      <PageHeader
        title="Team Attributes"
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
          <p className="text-sm text-textSecondary">Changes save automatically as you type.</p>
          <div className="grid gap-4 md:grid-cols-2">
            {data.conferences.map((conference) => (
              <ConferenceAttributesTable key={conference.conference} conference={conference} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default TeamAttributesPage;
