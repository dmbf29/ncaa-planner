import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import useLatestSeason from "../lib/useLatestSeason";
import { fetchScheduling, updateSchedulingByes } from "../lib/apiClient";

const MAX_BYES = 2;

function ByePicker({ weeks, byes, onChange, saving }) {
  const toggle = (number) => {
    if (byes.includes(number)) return onChange(byes.filter((n) => n !== number));
    if (byes.length < MAX_BYES) onChange([...byes, number].sort((a, b) => a - b));
  };

  return (
    <Card>
      <div className="space-y-3 p-5">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Bye Weeks</h3>
        <p className="text-sm text-textSecondary">
          Pick up to {MAX_BYES} weeks every coach has off. Set these before uploading any team&rsquo;s schedule.
        </p>
        <div className="flex flex-wrap gap-2">
          {weeks.map((week) => {
            const active = byes.includes(week.number);
            return (
              <button
                key={week.id}
                type="button"
                disabled={saving || (!active && byes.length >= MAX_BYES)}
                onClick={() => toggle(week.number)}
                className={`h-10 w-10 rounded-md border text-sm font-semibold transition disabled:opacity-40 ${
                  active ? "border-burnt bg-burnt text-white" : "border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white"
                }`}
              >
                {week.number}
              </button>
            );
          })}
        </div>
      </div>
    </Card>
  );
}

function slotSummary(slots) {
  const open = slots.filter((slot) => slot.state === "open");
  const options = open.reduce((sum, slot) => sum + slot.optionCount, 0);
  const ranked = open.reduce((sum, slot) => sum + slot.rankedCount, 0);
  return { open: open.length, options, ranked, locked: slots.filter((slot) => slot.state === "locked").length };
}

function TeamRow({ team }) {
  const summary = slotSummary(team.slots);
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
      <div>
        <p className="font-semibold text-textPrimary dark:text-white">{team.college.name}</p>
        <p className="text-xs text-textSecondary">
          {team.coach}
          {team.uploaded
            ? ` · ${summary.locked} locked · ${summary.open} open weeks · ${summary.options} possible opponents (${summary.ranked} ranked)`
            : " · schedule not uploaded yet"}
        </p>
      </div>
      <div className="flex items-center gap-3">
        {team.confirmed && <span className="text-xs font-semibold text-success">Confirmed</span>}
        <Link
          to={`/dynasty/updates/scheduling/${team.id}`}
          className="rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5"
        >
          {team.uploaded ? "Open" : "Upload schedule"}
        </Link>
      </div>
    </div>
  );
}

function SchedulingPage() {
  const { dynastyId, seasonId, error: seasonError } = useLatestSeason();
  const [overview, setOverview] = useState(null);
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    try {
      setOverview(await fetchScheduling(dynastyId, seasonId));
    } catch (err) {
      setError(err.message);
    }
  }, [dynastyId, seasonId]);

  useEffect(() => {
    if (dynastyId) load();
  }, [dynastyId, load]);

  const saveByes = async (byes) => {
    setSaving(true);
    setError(null);
    try {
      setOverview(await updateSchedulingByes(dynastyId, seasonId, byes));
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  };

  if (seasonError || error) {
    return (
      <div className="mx-auto max-w-4xl px-4">
        <p className="text-sm text-danger">{seasonError || error}</p>
      </div>
    );
  }
  if (!overview) {
    return (
      <div className="mx-auto max-w-4xl px-4">
        <p className="text-sm text-textSecondary">Loading...</p>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6 px-4">
      <PageHeader
        title="Schedule Setup"
        eyebrow="Dynasty Updates"
        actions={
          <div className="flex gap-2">
            <Link
              to="/dynasty/updates/scheduling/links"
              className="rounded-md bg-burnt px-3 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5"
            >
              Coach links
            </Link>
            <Link
              to="/dynasty/updates"
              className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
            >
              Back to Updates
            </Link>
          </div>
        }
      />
      <ByePicker weeks={overview.weeks} byes={overview.byeWeekNumbers} onChange={saveByes} saving={saving} />
      <Card className="overflow-hidden">
        <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Coached Teams</h3>
        </div>
        <div className="divide-y divide-border dark:divide-darkborder">
          {overview.teams.length === 0 && <p className="px-4 py-3 text-sm text-textSecondary">No coached teams this season.</p>}
          {overview.teams.map((team) => (
            <TeamRow key={team.id} team={team} />
          ))}
        </div>
      </Card>
    </div>
  );
}

export default SchedulingPage;
