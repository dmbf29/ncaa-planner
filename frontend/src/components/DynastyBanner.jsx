import { Link } from "react-router-dom";
import { clsx } from "clsx";
import { weekLabel } from "./LeagueGameRow";

function DynastyBanner({ name, seasons, activeSeasonId, dynastyId, dashboard }) {
  const week = dashboard?.aroundTheLeague?.find((group) => group.week.number === dashboard.currentWeekNumber)?.week;
  const champion = dashboard?.reigningChampion;

  return (
    <div className="mb-4 overflow-hidden rounded-lg bg-charcoal text-white shadow-card dark:border dark:border-darkborder">
      <div className="flex flex-col gap-2 px-4 py-3 md:flex-row md:items-center md:justify-between md:px-5">
        <div className="min-w-0">
          <p className="font-crayon text-[10px] uppercase tracking-[0.2em] text-white/60 md:text-xs">{name || "Dynasty"}</p>
          <h1 className="flex flex-wrap items-baseline gap-x-3 font-varsity uppercase tracking-[0.06em]">
            <span className="text-2xl md:text-3xl">{dashboard ? `${dashboard.year} Season` : "Loading..."}</span>
            {week && <span className="text-base text-burnt md:text-lg">{weekLabel(week)}</span>}
          </h1>
        </div>

        {champion && (
          <div className="flex items-center gap-2.5 rounded-md border border-white/15 bg-white/5 px-3 py-2">
            <i className="fa-solid fa-trophy text-lg text-warning" />
            <div className="min-w-0 leading-tight">
              <p className="font-crayon text-[10px] uppercase tracking-[0.15em] text-white/60">
                Reigning Champs · {champion.year}
              </p>
              <p className="flex items-center gap-1.5 font-varsity text-base uppercase tracking-[0.06em]">
                {champion.coachedByUs && <i className="fa-solid fa-gamepad text-[10px] text-burnt" title="User-coached" />}
                {champion.name}
                <span className="font-sans text-[11px] normal-case tracking-normal text-white/60">
                  def. {champion.runnerUp} {champion.winnerScore}-{champion.loserScore}
                </span>
              </p>
            </div>
          </div>
        )}
      </div>

      {seasons?.length > 1 && (
        <div className="flex flex-wrap gap-1 border-t border-white/10 px-4 py-1.5 md:px-5">
          {seasons.map((season) => (
            <Link
              key={season.id}
              to={`/dynasty/${dynastyId}/seasons/${season.id}`}
              className={clsx(
                "rounded-md px-2.5 py-0.5 text-sm font-semibold transition",
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
