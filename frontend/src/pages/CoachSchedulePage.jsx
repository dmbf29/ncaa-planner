import { useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import Card from "../components/Card";
import ScheduleGrid from "../components/ScheduleGrid";
import { fetchCoachSchedule, pickCoachOpponent, removeCoachOpponent, confirmCoachSchedule } from "../lib/apiClient";

const STATUS_STYLES = {
  ok: "border-border dark:border-darkborder",
  warning: "border-warning/60 bg-warning/10",
  blocked: "border-border opacity-60 dark:border-darkborder",
};

function OptionRow({ option, onPick, busy }) {
  const blocked = option.status === "blocked";
  return (
    <div className={`rounded-md border p-3 ${STATUS_STYLES[option.status]}`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-semibold text-textPrimary dark:text-white">
            {option.ranked && (
              <span className="mr-2 rounded bg-burnt px-1.5 py-0.5 text-xs font-bold text-white">{option.rank ? `#${option.rank}` : "Ranked"}</span>
            )}
            {option.college.name}
          </p>
          <p className="text-xs text-textSecondary">
            {option.overall ?? "?"} OVR &middot; {option.offense ?? "?"} OFF &middot; {option.defense ?? "?"} DEF
            {option.prestige != null && ` · ${option.prestige}★`}
          </p>
        </div>
        {!blocked && (
          <div className="flex gap-2">
            <button type="button" disabled={busy} onClick={() => onPick(option, false)} className="rounded-md border border-border px-3 py-1.5 text-sm dark:border-darkborder dark:text-white">
              Home
            </button>
            <button type="button" disabled={busy} onClick={() => onPick(option, true)} className="rounded-md bg-burnt px-3 py-1.5 text-sm font-semibold text-white">
              Away
            </button>
          </div>
        )}
      </div>
      {option.reasons.map((reason) => (
        <p key={reason} className={`mt-1 text-xs ${blocked ? "text-textSecondary" : "font-semibold text-warning"}`}>
          {blocked ? "" : "⚠ "}
          {reason}
        </p>
      ))}
    </div>
  );
}

function WeekPanel({ slot, options, onPick, onRemove, busy }) {
  const pick = slot.pick;
  return (
    <Card>
      <div className="space-y-3 p-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Week {slot.weekNumber}</h3>
        {pick && (
          <div className="flex flex-wrap items-center justify-between gap-2 rounded-md bg-border/30 p-3 text-sm dark:bg-white/10">
            <p className="font-semibold text-textPrimary dark:text-white">
              {pick.isAway ? "@" : "vs"} {pick.opponent.name}
              {pick.shared && <span className="ml-2 text-xs font-normal text-textSecondary">Set by the other coach &mdash; only they can change it.</span>}
            </p>
            {!pick.shared && (
              <div className="flex gap-2">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => onPick({ college: pick.opponent }, !pick.isAway)}
                  className="rounded-md border border-border px-3 py-1.5 dark:border-darkborder dark:text-white"
                >
                  Switch to {pick.isAway ? "home" : "away"}
                </button>
                <button type="button" disabled={busy} onClick={onRemove} className="rounded-md border border-danger px-3 py-1.5 text-danger">
                  Remove
                </button>
              </div>
            )}
          </div>
        )}
        {!pick?.shared && (
          <>
            <p className="text-xs text-textSecondary">Choose an opponent. Teams already on another coach&rsquo;s schedule are flagged, and can only go after that coach&rsquo;s week.</p>
            <div className="max-h-[28rem] space-y-2 overflow-y-auto">
              {options.length === 0 && <p className="text-sm text-textSecondary">No opponents have been loaded for this week yet.</p>}
              {options.map((option) => (
                <OptionRow key={option.college.id} option={option} onPick={onPick} busy={busy} />
              ))}
            </div>
          </>
        )}
      </div>
    </Card>
  );
}

function CoachSchedulePage() {
  const { token } = useParams();
  const [data, setData] = useState(null);
  const [selectedWeekId, setSelectedWeekId] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const load = useCallback(() => fetchCoachSchedule(token).then(setData).catch((err) => setError(err.message)), [token]);
  useEffect(() => {
    load();
  }, [load]);

  const run = async (action) => {
    setBusy(true);
    setError(null);
    try {
      setData(await action());
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  if (!data) return <p className="mx-auto max-w-4xl px-4 text-sm text-textSecondary">{error || "Loading..."}</p>;

  const { team } = data;
  const selected = team.slots.find((slot) => slot.weekId === selectedWeekId);
  const roadOk = data.roadGames >= data.roadGamesRequired;

  return (
    <div className="mx-auto max-w-4xl space-y-6 px-4">
      <div>
        <p className="text-xs uppercase tracking-wide text-textSecondary">{data.season.year} non-conference schedule</p>
        <h1 className="font-varsity text-3xl uppercase tracking-[0.06em] text-charcoal dark:text-white">{team.college.name}</h1>
        <p className="text-sm text-textSecondary">Coach {team.coach}</p>
      </div>

      <Card>
        <div className="space-y-2 p-4 text-sm">
          <p className={roadOk ? "text-success" : "text-textPrimary dark:text-white"}>
            Non-conference road games: <strong>{data.roadGames}</strong> of at least <strong>{data.roadGamesRequired}</strong>
            {data.roadGamesRequired > 1 && " (reigning national champions need 2)"}
          </p>
          {data.byeWeekNumbers.length > 0 && <p className="text-textSecondary">Bye weeks: {data.byeWeekNumbers.join(", ")}</p>}
          {data.confirmed ? (
            <p className="font-semibold text-success">Your schedule is confirmed. You can still change it &mdash; just confirm again afterwards.</p>
          ) : (
            data.problems.length > 0 && (
              <ul className="list-disc pl-5 text-textSecondary">
                {data.problems.map((problem) => (
                  <li key={problem}>{problem}</li>
                ))}
              </ul>
            )
          )}
        </div>
      </Card>

      {error && <p className="rounded-md border border-danger/40 bg-danger/10 p-3 text-sm text-danger">{error}</p>}

      <Card>
        <div className="space-y-3 p-4">
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Your schedule</h3>
          <ScheduleGrid slots={team.slots} onSelect={(slot) => setSelectedWeekId(slot.weekId)} selectedWeekId={selectedWeekId} />
          <button
            type="button"
            disabled={busy || data.confirmed || data.problems.length > 0}
            onClick={() => run(() => confirmCoachSchedule(token))}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card disabled:cursor-not-allowed disabled:opacity-50"
          >
            {data.confirmed ? "Confirmed" : "Confirm schedule"}
          </button>
        </div>
      </Card>

      {selected && (
        <WeekPanel
          key={selected.weekId}
          slot={selected}
          options={data.options[selected.weekNumber] || []}
          busy={busy}
          onPick={(option, isAway) => run(() => pickCoachOpponent(token, selected.weekId, option.college.id, isAway))}
          onRemove={() => run(() => removeCoachOpponent(token, selected.weekId))}
        />
      )}

      <div className="space-y-3">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Everyone else</h3>
        {data.otherTeams.map((other) => (
          <Card key={other.id}>
            <div className="space-y-2 p-4">
              <p className="font-semibold text-textPrimary dark:text-white">
                {other.college.name} <span className="text-xs font-normal text-textSecondary">Coach {other.coach}</span>
                {other.confirmed && <span className="ml-2 text-xs font-semibold text-success">Confirmed</span>}
              </p>
              <ScheduleGrid slots={other.slots} />
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

export default CoachSchedulePage;
