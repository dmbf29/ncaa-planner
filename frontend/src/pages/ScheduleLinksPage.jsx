import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import ScheduleGrid from "../components/ScheduleGrid";
import useLatestSeason from "../lib/useLatestSeason";
import { fetchScheduling } from "../lib/apiClient";

function statusOf(team) {
  if (!team.uploaded) return { label: "Not set up", className: "text-textSecondary" };
  if (team.confirmed) return { label: "Confirmed", className: "text-success" };
  const filled = team.slots.filter((slot) => slot.state === "open" && slot.pick).length;
  const open = team.slots.filter((slot) => slot.state === "open").length;
  return { label: `Choosing (${filled}/${open} picked)`, className: "text-warning" };
}

function TeamLinkCard({ team }) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);
  const status = statusOf(team);
  const url = team.scheduleToken ? `${window.location.origin}/schedule/${team.scheduleToken}` : null;

  const copy = async () => {
    await navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <Card>
      <div className="space-y-3 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="font-semibold text-textPrimary dark:text-white">{team.college.name}</p>
            <p className="text-xs text-textSecondary">
              {team.coach} &middot; <span className={`font-semibold ${status.className}`}>{status.label}</span>
            </p>
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={() => setOpen(!open)} className="rounded-md border border-border px-3 py-2 text-sm dark:border-darkborder dark:text-white">
              {open ? "Hide schedule" : "View schedule"}
            </button>
            {url ? (
              <button type="button" onClick={copy} className="rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-white shadow-card">
                {copied ? "Copied!" : "Copy link"}
              </button>
            ) : (
              <Link to={`/dynasty/updates/scheduling/${team.id}`} className="rounded-md border border-border px-3 py-2 text-sm dark:border-darkborder dark:text-white">
                Set up first
              </Link>
            )}
          </div>
        </div>
        {url && <p className="break-all text-xs text-textSecondary">{url}</p>}
        {open && <ScheduleGrid slots={team.slots} />}
      </div>
    </Card>
  );
}

function ScheduleLinksPage() {
  const { dynastyId, seasonId, error: seasonError } = useLatestSeason();
  const [overview, setOverview] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!dynastyId) return;
    fetchScheduling(dynastyId, seasonId).then(setOverview).catch((err) => setError(err.message));
  }, [dynastyId, seasonId]);

  if (seasonError || error) return <p className="mx-auto max-w-4xl px-4 text-sm text-danger">{seasonError || error}</p>;
  if (!overview) return <p className="mx-auto max-w-4xl px-4 text-sm text-textSecondary">Loading...</p>;

  return (
    <div className="mx-auto max-w-4xl space-y-4 px-4">
      <PageHeader
        title="Coach Links"
        eyebrow="Schedule Setup"
        actions={
          <Link to="/dynasty/updates/scheduling" className="rounded-md border border-border px-3 py-2 text-sm text-charcoal dark:border-darkborder dark:text-white">
            Back to setup
          </Link>
        }
      />
      <p className="text-sm text-textSecondary">
        Send each coach their own link. They pick their non-conference opponents there &mdash; no login needed. Links only work once the data has been
        pushed to production.
      </p>
      {overview.teams.map((team) => (
        <TeamLinkCard key={team.id} team={team} />
      ))}
    </div>
  );
}

export default ScheduleLinksPage;
