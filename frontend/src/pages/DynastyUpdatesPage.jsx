import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, createSeason } from "../lib/apiClient";

const UPDATE_TYPES = [
  { key: "season", label: "Start a New Season", description: "Create the next season for your dynasty." },
  { key: "top25", label: "Update Top 25", description: "Upload the weekly AP-style poll screenshots.", to: "/dynasty/updates/top25" },
  { key: "games", label: "Add Games/Results", description: "Upload the weekly schedule screenshots.", to: "/dynasty/updates/schedule" },
  { key: "heisman", label: "Add Heisman Candidates", description: "Upload the weekly Heisman Watch List screenshot.", to: "/dynasty/updates/heisman" },
  { key: "players-of-the-week", label: "Add Players of the Week", description: "Upload the weekly National/Conference Players of the Week screenshots.", to: "/dynasty/updates/players-of-the-week" },
  { key: "standings", label: "Update Conference Standings", description: "Upload the conference standings screenshots.", to: "/dynasty/updates/standings" },
  { key: "team-stats", label: "Update Team Stats", description: "Coming soon." },
  { key: "player-stats", label: "Update Player Stats", description: "Coming soon." },
  { key: "all-americans", label: "Add All-Americans", description: "Upload the National/Conference All-American screenshots.", to: "/dynasty/updates/all-americans" },
  { key: "nil-spend", label: "Update NIL Spend", description: "Upload the conference NIL spend screenshots.", to: "/dynasty/updates/nil-spend" },
];

function UpdateCard({ update, onClick }) {
  const content = (
    <div className="p-5 space-y-1">
      <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{update.label}</h3>
      <p className="text-sm text-textSecondary">{update.description}</p>
    </div>
  );

  if (update.to) {
    return (
      <Link to={update.to}>
        <Card className="transition hover:-translate-y-0.5">{content}</Card>
      </Link>
    );
  }

  if (onClick) {
    return (
      <button type="button" onClick={onClick} className="w-full text-left">
        <Card className="transition hover:-translate-y-0.5">{content}</Card>
      </button>
    );
  }

  return <Card className="opacity-50">{content}</Card>;
}

function NewSeasonModal({ year, onYearChange, onClose, onSubmit, submitting, error, disabled }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
      <div className="w-full max-w-md rounded-xl bg-surface p-6 shadow-2xl dark:bg-darksurface">
        <div className="flex items-center justify-between">
          <h3 className="font-varsity text-xl uppercase tracking-[0.06em] text-charcoal dark:text-white">Start a New Season</h3>
          <button onClick={onClose} className="text-textSecondary hover:text-charcoal dark:hover:text-white">
            ✕
          </button>
        </div>
        <p className="mt-2 text-sm text-textSecondary">This creates the season and its 20 weeks. Nothing else is copied over.</p>
        <label className="mt-4 flex flex-col gap-1 text-sm">
          <span className="text-xs uppercase tracking-wide text-textSecondary">Year</span>
          <input
            type="number"
            value={year}
            onChange={(e) => onYearChange(e.target.value === "" ? "" : Number(e.target.value))}
            className="rounded-md border border-border bg-white px-3 py-2 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
          />
        </label>

        {error && <p className="mt-2 text-sm text-danger">{error}</p>}

        <div className="mt-5 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-md border border-border px-4 py-2 text-sm font-semibold text-textSecondary hover:bg-border/40 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            onClick={onSubmit}
            disabled={submitting || !year || disabled}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? "Creating..." : "Create Season"}
          </button>
        </div>
      </div>
    </div>
  );
}

function DynastyUpdatesPage() {
  const navigate = useNavigate();

  const [dynastyId, setDynastyId] = useState(null);
  const [nextYear, setNextYear] = useState("");

  const [showSeasonModal, setShowSeasonModal] = useState(false);
  const [year, setYear] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = async () => {
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) return;
        setDynastyId(dynasty.id);
        const latestYear = Math.max(0, ...(dynasty.seasons || []).map((s) => s.year));
        setNextYear(latestYear + 1);
      } catch {
        // Non-fatal here — the "Start a New Season" card will just be missing a default year.
      }
    };
    load();
  }, []);

  const openSeasonModal = () => {
    setYear(nextYear);
    setError(null);
    setShowSeasonModal(true);
  };

  const handleCreateSeason = async () => {
    setSubmitting(true);
    setError(null);
    try {
      await createSeason(dynastyId, { year });
      navigate("/dynasty");
    } catch (err) {
      setError(err.message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="max-w-5xl mx-auto px-4">
      <PageHeader
        title="Dynasty Updates"
        eyebrow="Keep your dynasty up to date"
        actions={
          <Link
            to="/dynasty"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dashboard
          </Link>
        }
      />
      <div className="grid gap-4 pb-8 sm:grid-cols-2">
        {UPDATE_TYPES.map((update) => (
          <UpdateCard key={update.key} update={update} onClick={update.key === "season" ? openSeasonModal : undefined} />
        ))}
      </div>

      {showSeasonModal && (
        <NewSeasonModal
          year={year}
          onYearChange={setYear}
          onClose={() => setShowSeasonModal(false)}
          onSubmit={handleCreateSeason}
          submitting={submitting}
          error={error}
          disabled={!dynastyId}
        />
      )}
    </div>
  );
}

export default DynastyUpdatesPage;
