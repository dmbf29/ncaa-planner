import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchDynasties, fetchSeason, fetchStandings, createSeason } from "../lib/apiClient";

const WEEKLY_UPDATES = [
  { key: "games", label: "Games/Results", description: "Upload the weekly schedule screenshots.", to: "/dynasty/updates/schedule" },
  { key: "top25", label: "Top 25", description: "Upload the weekly AP-style poll screenshots.", to: "/dynasty/updates/top25" },
  { key: "players-of-the-week", label: "Players of the Week", description: "Upload the weekly National/Conference Players of the Week screenshots.", to: "/dynasty/updates/players-of-the-week" },
  { key: "heisman", label: "Heisman Candidates", description: "Upload the weekly Heisman Watch List screenshot.", to: "/dynasty/updates/heisman" },
  { key: "standings", label: "Conference Standings", description: "Upload the conference standings screenshots.", to: "/dynasty/updates/standings" },
  { key: "team-schedule", label: "Team Schedule", description: "Upload a team's full-season schedule screenshots.", to: "/dynasty/updates/team-schedule" },
];

const OCCASIONAL_UPDATES = [
  { key: "nil-spend", label: "NIL Spend", description: "Upload the conference NIL spend screenshots.", to: "/dynasty/updates/nil-spend", tags: ["preseason"] },
  { key: "recruiting", label: "Recruiting Recap", description: "Upload the national recruiting class rankings screenshots.", to: "/dynasty/updates/recruiting", tags: ["postseason"] },
  { key: "all-americans", label: "All-Americans", description: "Upload the National/Conference All-American screenshots.", to: "/dynasty/updates/all-americans", tags: ["preseason", "postseason"] },
  { key: "team-attributes", label: "Team Attributes", description: "Update overall, offense, defense, and prestige for every team.", to: "/dynasty/updates/team-attributes", tags: ["preseason"] },
  { key: "team-stats", label: "Team Stats", description: "Upload the league-wide offense/defense stats screenshots.", to: "/dynasty/updates/team-stats" },
  { key: "season", label: "Start a New Season", description: "Create the next season for your dynasty.", tags: ["postseason"] },
];

// Occasional updates are tagged by when in the year they come up, and the section sorts by
// that tag (preseason before postseason) rather than the order above. An update tagged with
// both sorts alongside its earliest tag but still shows every tag it carries.
const TAG_ORDER = ["preseason", "postseason"];

const TAG_LABELS = {
  preseason: "Preseason",
  postseason: "Postseason",
};

const TAG_BADGE_CLASSES = {
  preseason: "bg-olive/10 text-olive",
  postseason: "bg-burnt/10 text-burnt",
};

function sortByTag(updates) {
  return [...updates].sort((a, b) => {
    const aRank = Math.min(...(a.tags || []).map((tag) => TAG_ORDER.indexOf(tag)));
    const bRank = Math.min(...(b.tags || []).map((tag) => TAG_ORDER.indexOf(tag)));
    return aRank - bRank;
  });
}

const COMING_SOON_UPDATES = [
  { key: "player-stats", label: "Player Stats", description: "Coming soon." },
];

const BADGE_TONE_CLASSES = {
  good: "bg-success/10 text-success",
  warn: "bg-warning/10 text-warning",
  neutral: "bg-textSecondary/10 text-textSecondary",
};

function WeeklyBadge({ status }) {
  if (!status) return null;

  return (
    <span className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${BADGE_TONE_CLASSES[status.tone]}`}>
      {status.label}
    </span>
  );
}

function TagBadges({ tags }) {
  if (!tags || tags.length === 0) return null;

  return (
    <div className="flex gap-1">
      {tags.map((tag) => (
        <span key={tag} className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${TAG_BADGE_CLASSES[tag]}`}>
          {TAG_LABELS[tag]}
        </span>
      ))}
    </div>
  );
}

function UpdateCard({ update, status, onClick }) {
  const content = (
    <div className="p-5 space-y-1.5">
      <div className="flex items-start justify-between gap-2">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{update.label}</h3>
        {status ? <WeeklyBadge status={status} /> : <TagBadges tags={update.tags} />}
      </div>
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

function UpdateSection({ title, hint, updates, statuses, onSeasonClick }) {
  return (
    <div className="space-y-3">
      <div>
        <h2 className="font-varsity text-xl uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h2>
        {hint && <p className="text-xs text-textSecondary">{hint}</p>}
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        {updates.map((update) => (
          <UpdateCard
            key={update.key}
            update={update}
            status={statuses?.[update.key]}
            onClick={update.key === "season" ? onSeasonClick : undefined}
          />
        ))}
      </div>
    </div>
  );
}

// "Caught up" means data covers through dueWeekNumber (the week the dynasty
// is currently in the middle of, for most weekly uploads — or the week
// before it for results, which can't exist until that week's games finish).
function weeklyStatus(lastWeekNumber, dueWeekNumber) {
  if (dueWeekNumber == null) return null;
  if (lastWeekNumber == null) return { label: "Not started", tone: "neutral" };
  if (lastWeekNumber >= dueWeekNumber) return { label: `Up to date · Week ${lastWeekNumber}`, tone: "good" };
  return { label: `Needs Week ${dueWeekNumber}`, tone: "warn" };
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
  const [weeklyStatuses, setWeeklyStatuses] = useState({});

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

        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) return;
        const [season] = await Promise.all([
          fetchSeason(dynasty.id, latestSeason.id),
          fetchStandings(dynasty.id, latestSeason.id).catch(() => null),
        ]);
        const currentWeekNumber = season.currentWeekNumber ?? null;
        const previousWeekNumber = currentWeekNumber == null ? null : currentWeekNumber - 1;
        setWeeklyStatuses({
          // Results and Players of the Week both cover a week only once it's been played,
          // so they're "due" for the week before the current one — not the current week itself.
          games: weeklyStatus(season.lastPlayedWeekNumber, previousWeekNumber),
          "players-of-the-week": weeklyStatus(season.playersOfTheWeek?.weeks?.[0]?.week?.number, previousWeekNumber),
          // Top 25 and Heisman polls are published going into the current week (they show its
          // upcoming matchups), so they're due as soon as the current week starts.
          top25: weeklyStatus(season.top25?.week?.number, currentWeekNumber),
          heisman: weeklyStatus(season.heismanWatch?.weeks?.[0]?.week?.number, currentWeekNumber),
        });
      } catch {
        // Non-fatal here — cards just render without their status badges.
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
      const result = await createSeason(dynastyId, { year });
      navigate(`/dynasty/updates/season/coaches?dynastyId=${dynastyId}&seasonId=${result.id}`);
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
      <div className="space-y-8 pb-8">
        <UpdateSection
          title="Weekly"
          hint="Upload each of these once for every week you play."
          updates={WEEKLY_UPDATES}
          statuses={weeklyStatuses}
        />
        <UpdateSection
          title="Occasional"
          hint="Update these as needed — not tied to a specific week."
          updates={sortByTag(OCCASIONAL_UPDATES)}
          onSeasonClick={openSeasonModal}
        />
        <UpdateSection title="Coming Soon" updates={COMING_SOON_UPDATES} />
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
