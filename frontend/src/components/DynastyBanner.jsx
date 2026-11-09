import { Link } from "react-router-dom";
import { clsx } from "clsx";
import { weekLabel } from "./LeagueGameRow";

function DynastyBanner({ name, seasons, activeSeasonId, dynastyId, dashboard }) {
  const week = dashboard?.aroundTheLeague?.find((group) => group.week.number === dashboard.currentWeekNumber)?.week;
  const champion = dashboard?.reigningChampion;

  return (
    <div className="mb-4 overflow-hidden rounded-lg bg-charcoal text-white shadow-card dark:border dark:border-darkborder">
      <div className="flex flex-col gap-4 px-4 py-4 md:flex-row md:items-end md:justify-between md:px-6 md:py-5">
        <div className="min-w-0">
          <p className="font-crayon text-xs uppercase tracking-[0.2em] text-white/60">{name || "Dynasty"}</p>
          <h1 className="mt-1 font-varsity text-3xl uppercase tracking-[0.06em] md:text-5xl">
            {dashboard ? `${dashboard.year} Season` : "Loading..."}
          </h1>
          {week && (
            <p className="mt-1 font-varsity text-lg uppercase tracking-[0.08em] text-burnt md:text-xl">
              {weekLabel(week)}
            </p>
          )}
        </div>

        {champion && (
          <div className="flex items-center gap-3 rounded-md border border-white/15 bg-white/5 px-4 py-3">
            <i className="fa-solid fa-trophy text-2xl text-warning" />
            <div className="min-w-0">
              <p className="font-crayon text-[10px] uppercase tracking-[0.2em] text-white/60">
                Reigning Champions · {champion.year}
              </p>
              <p className="flex items-center gap-1.5 font-varsity text-xl uppercase tracking-[0.06em]">
                {champion.coachedByUs && <i className="fa-solid fa-gamepad text-xs text-burnt" title="User-coached" />}
                {champion.name}
              </p>
              <p className="text-xs text-white/60">
                def. {champion.runnerUp} {champion.winnerScore}-{champion.loserScore}
              </p>
            </div>
          </div>
        )}
      </div>

      {seasons?.length > 1 && (
        <div className="flex flex-wrap gap-1.5 border-t border-white/10 px-4 py-2.5 md:px-6">
          {seasons.map((season) => (
            <Link
              key={season.id}
              to={`/dynasty/${dynastyId}/seasons/${season.id}`}
              className={clsx(
                "rounded-md px-3 py-1 text-sm font-semibold transition",
                String(season.id) === String(activeSeasonId)
                  ? "bg-burnt text-white"
                  : "text-white/70 hover:bg-white/10",
              )}
            >
              {season.year}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

export default DynastyBanner;
