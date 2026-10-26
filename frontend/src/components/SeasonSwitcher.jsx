import { Link } from "react-router-dom";
import clsx from "clsx";

// `suffix` keeps the user on the same page (e.g. "/players") when hopping between seasons.
function SeasonSwitcher({ seasons, activeSeasonId, dynastyId, suffix = "", className = "mb-6" }) {
  if (!seasons || seasons.length < 2) return null;

  return (
    <div className={clsx("flex flex-wrap gap-1.5", className)}>
      {seasons.map((season) => (
        <Link
          key={season.id}
          to={`/dynasty/${dynastyId}/seasons/${season.id}${suffix}`}
          className={clsx(
            "rounded-md px-3 py-1.5 text-sm font-semibold transition",
            String(season.id) === String(activeSeasonId)
              ? "bg-charcoal text-white dark:bg-white/10"
              : "border border-border text-textSecondary hover:bg-border/30 dark:border-darkborder dark:hover:bg-white/10",
          )}
        >
          {season.year}
        </Link>
      ))}
    </div>
  );
}

export default SeasonSwitcher;
