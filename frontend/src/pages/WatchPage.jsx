import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import { weekLabel } from "../components/LeagueGameRow";
import { API_BASE_URL, fetchDynastyVideos } from "../lib/apiClient";

const isHighlights = (video) => video.kind === "highlights";
const matchup = (video) => `${video.away.name} at ${video.home.name}`;
const logoSrc = (side) => (side.logoUrl ? `${API_BASE_URL}${side.logoUrl}` : null);

const formatDuration = (seconds) => {
  if (!seconds) return null;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  return hours ? `${hours}h ${minutes}m` : `${minutes}m`;
};

function Player({ video }) {
  if (video.provider === "youtube") {
    return (
      <iframe
        key={video.id}
        src={`https://www.youtube-nocookie.com/embed/${video.source}?rel=0`}
        title={video.title || matchup(video)}
        allow="accelerometer; autoplay; encrypted-media; fullscreen; picture-in-picture"
        allowFullScreen
        className="aspect-video w-full rounded-xl bg-black"
      />
    );
  }
  return <video key={video.id} src={video.source} controls className="aspect-video w-full rounded-xl bg-black" />;
}

function SideLogo({ side, size = "h-6 w-6" }) {
  const src = logoSrc(side);
  return src ? (
    <img src={src} alt="" className={clsx(size, "shrink-0 object-contain")} />
  ) : (
    <span className={clsx(size, "shrink-0 rounded-full bg-charcoal/10 dark:bg-white/10")} />
  );
}

const gameTag = (game) => game.bowlName || (game.cfpRound ? `CFP ${game.cfpRound}` : null);

// A game is one card: its full replay and highlights (if both exist) share a game_id.
function groupGames(videos) {
  const byGame = new Map();
  videos.forEach((video) => {
    const key = video.gameId ?? `v${video.id}`;
    let game = byGame.get(key);
    if (!game) {
      game = { key, ...video, full: null, highlights: null };
      byGame.set(key, game);
    }
    game[isHighlights(video) ? "highlights" : "full"] = video;
  });
  return [...byGame.values()];
}

function KindButtons({ game, kind, onKind }) {
  if (!game.full || !game.highlights) return null;
  return (
    <div className="inline-flex rounded-full border border-white/20 p-0.5 text-xs font-semibold uppercase tracking-wide">
      {[
        ["full", "Full game"],
        ["highlights", "Highlights"],
      ].map(([value, label]) => (
        <button
          key={value}
          type="button"
          onClick={() => onKind(value)}
          className={clsx(
            "rounded-full px-3 py-1 transition",
            kind === value ? "bg-burnt text-white" : "text-white/60 hover:text-white",
          )}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

function Scoreboard({ game }) {
  const winner = game.home.score > game.away.score ? game.home.id : game.away.score > game.home.score ? game.away.id : null;
  const dim = (side) => winner && winner !== side.id && "opacity-50";
  return (
    <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-3 px-2 pt-4 sm:gap-6">
      <div className={clsx("flex items-center justify-end gap-3", dim(game.away))}>
        <span className="hidden min-w-0 truncate text-right text-lg font-semibold sm:block">{game.away.name}</span>
        <SideLogo side={game.away} size="h-12 w-12 sm:h-14 sm:w-14" />
      </div>
      <div className="text-center">
        <div className="font-varsity text-4xl tabular-nums tracking-wide sm:text-5xl">
          <span className={dim(game.away)}>{game.away.score ?? "-"}</span>
          <span className="mx-3 text-white/30">:</span>
          <span className={dim(game.home)}>{game.home.score ?? "-"}</span>
        </div>
        <div className="text-[10px] font-semibold uppercase tracking-[0.2em] text-white/50">Final</div>
      </div>
      <div className={clsx("flex items-center gap-3", dim(game.home))}>
        <SideLogo side={game.home} size="h-12 w-12 sm:h-14 sm:w-14" />
        <span className="hidden min-w-0 truncate text-lg font-semibold sm:block">{game.home.name}</span>
      </div>
    </div>
  );
}

const thumbnail = (video) =>
  video?.provider === "youtube" ? `https://img.youtube.com/vi/${video.source}/mqdefault.jpg` : null;

function GameCard({ game, active, onSelect }) {
  const tag = gameTag(game);
  const primary = game.full || game.highlights;
  const thumb = thumbnail(primary);
  const duration = formatDuration(primary.durationSeconds);
  const winner = game.home.score > game.away.score ? game.home.id : game.away.score > game.home.score ? game.away.id : null;
  return (
    <button
      type="button"
      onClick={() => onSelect(game)}
      className={clsx(
        "group/card w-full overflow-hidden rounded-xl text-left shadow-sm ring-1 transition hover:-translate-y-0.5 hover:shadow-lg",
        active ? "bg-charcoal text-white ring-2 ring-charcoal" : "bg-white ring-black/5 dark:bg-white/5 dark:ring-white/10",
      )}
    >
      <div className="relative aspect-video bg-charcoal">
        {thumb && <img src={thumb} alt="" loading="lazy" className="h-full w-full object-cover opacity-90 transition group-hover/card:scale-105" />}
        <div className="absolute inset-0 flex items-center justify-center bg-gradient-to-t from-black/50 to-transparent">
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-white/90 text-charcoal shadow-lg transition group-hover/card:scale-110">
            ▶
          </span>
        </div>
        <div className="absolute left-2 top-2 flex gap-1 text-[10px] font-bold uppercase tracking-wide">
          {active && <span className="rounded bg-white px-1.5 py-0.5 text-charcoal">Now playing</span>}
          {game.highlights && <span className="rounded bg-burnt px-1.5 py-0.5 text-white">Highlights</span>}
        </div>
        {duration && <span className="absolute bottom-2 right-2 rounded bg-black/70 px-1.5 py-0.5 text-[11px] text-white">{duration}</span>}
      </div>
      <div className="p-3">
        {tag && <div className="mb-1 truncate text-[10px] font-semibold uppercase tracking-wide opacity-60">{tag}</div>}
        {[game.away, game.home].map((side) => (
          <div key={side.id} className="flex items-center gap-2 py-0.5 text-sm">
            <SideLogo side={side} size="h-6 w-6" />
            <span className={clsx("min-w-0 flex-1 truncate", winner === side.id && "font-semibold")}>{side.name}</span>
            {side.score != null && (
              <span className={clsx("font-varsity text-lg tabular-nums", winner && winner !== side.id && "opacity-50")}>{side.score}</span>
            )}
          </div>
        ))}
      </div>
    </button>
  );
}

function Collapsible({ title, count, defaultOpen, level, children }) {
  const season = level === "season";
  return (
    <details
      open={defaultOpen}
      className={clsx("group", season ? "mt-6 overflow-hidden rounded-2xl bg-charcoal/[0.06] dark:bg-white/5" : "mt-3 rounded-xl bg-white shadow-sm dark:bg-white/5")}
    >
      <summary
        className={clsx(
          "flex cursor-pointer list-none items-center gap-3 [&::-webkit-details-marker]:hidden",
          season
            ? "bg-charcoal px-5 py-4 font-varsity text-2xl uppercase tracking-[0.08em] text-white"
            : "px-4 py-3 text-sm font-semibold hover:bg-charcoal/5 dark:hover:bg-white/5",
        )}
      >
        <span className={clsx("text-xs transition group-open:rotate-90", season ? "text-white/60" : "text-textSecondary")}>▸</span>
        <span>{title}</span>
        <span
          className={clsx(
            "ml-auto rounded-full px-2.5 py-0.5 font-sans text-xs font-normal normal-case tracking-normal",
            season ? "bg-white/15 text-white" : "bg-charcoal/10 text-textSecondary dark:bg-white/10",
          )}
        >
          {count} {count === 1 ? "game" : "games"}
        </span>
      </summary>
      <div className={season ? "p-3" : "px-4 pb-4 pt-1"}>{children}</div>
    </details>
  );
}

function WatchPage() {
  const { dynastyId } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const [videos, setVideos] = useState(null);
  const [error, setError] = useState(null);
  const [coachedOnly, setCoachedOnly] = useState(false);
  const [team, setTeam] = useState("");

  useEffect(() => {
    let cancelled = false;
    fetchDynastyVideos(dynastyId)
      .then((data) => !cancelled && setVideos(data.videos))
      .catch((err) => !cancelled && setError(err.message));
    return () => {
      cancelled = true;
    };
  }, [dynastyId]);

  const games = useMemo(() => groupGames(videos || []), [videos]);

  const teams = useMemo(() => {
    const names = new Set();
    games.forEach((g) => [g.home, g.away].forEach((side) => (!coachedOnly || side.coachedByUs) && names.add(side.name)));
    return [...names].sort();
  }, [games, coachedOnly]);

  const filtered = useMemo(
    () =>
      games.filter((g) => {
        const sides = [g.home, g.away];
        if (coachedOnly && !sides.some((s) => s.coachedByUs)) return false;
        if (team && !sides.some((s) => s.name === team)) return false;
        return true;
      }),
    [games, coachedOnly, team],
  );

  // The picked video lives in the URL (?v=id) so a game can be shared; it falls back to the newest.
  const pickedId = searchParams.get("v");
  const selectedGame =
    games.find((g) => [g.full, g.highlights].some((v) => v && String(v.id) === pickedId)) || filtered[0] || null;
  const selected =
    selectedGame && ([selectedGame.full, selectedGame.highlights].find((v) => v && String(v.id) === pickedId) || selectedGame.full || selectedGame.highlights);
  const selectVideo = (video, scroll) => {
    setSearchParams({ v: video.id }, { replace: true });
    if (scroll) window.scrollTo({ top: 0, behavior: "smooth" });
  };
  const selectGame = (game) => selectVideo(game.full || game.highlights, true);

  // Seasons newest first, each split into weeks; the first season and its first week start open.
  const seasons = useMemo(() => {
    const result = [];
    filtered.forEach((game) => {
      let season = result.find((s) => s.id === game.season.id);
      if (!season) {
        season = { id: game.season.id, year: game.season.year, weeks: [], count: 0 };
        result.push(season);
      }
      let week = season.weeks.find((w) => w.id === game.week.id);
      if (!week) {
        week = { id: game.week.id, title: weekLabel(game.week), games: [] };
        season.weeks.push(week);
      }
      week.games.push(game);
      season.count += 1;
    });
    return result;
  }, [filtered]);

  return (
    <div className="mx-auto max-w-5xl px-4 pb-10">
      <PageHeader title="Watch" eyebrow="Game replays" />

      {!videos && !error && <p className="text-sm text-textSecondary">Loading games...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}
      {videos && videos.length === 0 && (
        <p className="text-sm text-textSecondary">No game replays have been added yet.</p>
      )}

      {selected && (
        <section className="rounded-2xl bg-charcoal p-3 pb-4 text-white shadow-xl sm:p-4 sm:pb-5">
          <Player video={selected} />
          <div>
            <Scoreboard game={selectedGame} />
            <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-white/10 pt-3 px-2">
              <p className="text-sm text-white/60">
                {selectedGame.season.year} · {weekLabel(selectedGame.week)}
                {gameTag(selectedGame) && ` · ${gameTag(selectedGame)}`}
              </p>
              <KindButtons
                game={selectedGame}
                kind={isHighlights(selected) ? "highlights" : "full"}
                onKind={(kind) => selectVideo(selectedGame[kind], false)}
              />
            </div>
          </div>
        </section>
      )}

      {games.length > 0 && (
        <div className="mt-6 flex flex-wrap items-center gap-2 text-sm">
          <button
            type="button"
            onClick={() => {
              setCoachedOnly(!coachedOnly);
              setTeam("");
            }}
            className={clsx(
              "rounded-full border px-3 py-1 transition",
              coachedOnly ? "border-burnt bg-burnt text-white" : "border-border hover:border-burnt dark:border-darkborder",
            )}
          >
            User-coached
          </button>
          <select
            value={team}
            onChange={(e) => setTeam(e.target.value)}
            className="rounded-full border border-border bg-transparent px-3 py-1 dark:border-darkborder"
          >
            <option value="">All teams</option>
            {teams.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
          <span className="ml-auto text-textSecondary">{filtered.length} games</span>
        </div>
      )}

      {seasons.map((season, si) => (
        <Collapsible key={season.id} level="season" title={`${season.year} Season`} count={season.count} defaultOpen={si === 0}>
          {season.weeks.map((week, wi) => {
            const latest = si === 0 && wi === 0; // newest week opens by default
            return (
              <Collapsible key={week.id} title={week.title} count={week.games.length} defaultOpen={latest}>
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                  {week.games.map((game) => (
                    <GameCard key={game.key} game={game} active={selectedGame?.key === game.key} onSelect={selectGame} />
                  ))}
                </div>
              </Collapsible>
            );
          })}
        </Collapsible>
      ))}
      {games.length > 0 && filtered.length === 0 && (
        <p className="mt-6 text-sm text-textSecondary">No games match these filters.</p>
      )}
    </div>
  );
}

export default WatchPage;
