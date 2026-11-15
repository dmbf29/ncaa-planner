import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { weekLabel } from "../components/LeagueGameRow";
import { API_BASE_URL, fetchDynastyVideos } from "../lib/apiClient";

const LATEST_COUNT = 6;

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

function SideLogo({ side }) {
  const src = logoSrc(side);
  return src ? (
    <img src={src} alt="" className="h-6 w-6 shrink-0 object-contain" />
  ) : (
    <span className="h-6 w-6 shrink-0 rounded-full bg-charcoal/10 dark:bg-white/10" />
  );
}

function VideoCard({ video, active, onSelect }) {
  const duration = formatDuration(video.durationSeconds);
  return (
    <button
      type="button"
      onClick={() => onSelect(video)}
      className={clsx(
        "w-full rounded-lg border px-3 py-2 text-left transition hover:bg-charcoal/5 dark:hover:bg-white/5",
        active ? "border-burnt bg-burnt/10" : "border-border dark:border-darkborder",
      )}
    >
      {(video.bowlName || video.title) && (
        <div className="truncate text-[10px] font-semibold uppercase tracking-wide text-textSecondary">
          {video.bowlName || video.title}
        </div>
      )}
      {[video.away, video.home].map((side) => (
        <div key={side.id} className="mt-0.5 flex items-center gap-2 text-sm">
          <SideLogo side={side} />
          <span className="min-w-0 flex-1 truncate">{side.name}</span>
          {side.score != null && <span className="font-varsity tabular-nums">{side.score}</span>}
        </div>
      ))}
      <div className="mt-1 text-[11px] text-textSecondary dark:text-white/50">
        {video.season.year} · {weekLabel(video.week)}
        {duration && ` · ${duration}`}
      </div>
    </button>
  );
}

function Grid({ videos, selected, onSelect }) {
  return (
    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
      {videos.map((video) => (
        <VideoCard key={video.id} video={video} active={selected?.id === video.id} onSelect={onSelect} />
      ))}
    </div>
  );
}

function SectionTitle({ children }) {
  return (
    <h2 className="mb-3 mt-8 inline-block border-b-2 border-burnt pb-0.5 font-varsity text-xl uppercase tracking-[0.06em]">
      {children}
    </h2>
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

  const teams = useMemo(() => {
    const names = new Set();
    (videos || []).forEach((v) => [v.home, v.away].forEach((side) => (!coachedOnly || side.coachedByUs) && names.add(side.name)));
    return [...names].sort();
  }, [videos, coachedOnly]);

  const filtered = useMemo(
    () =>
      (videos || []).filter((v) => {
        const sides = [v.home, v.away];
        if (coachedOnly && !sides.some((s) => s.coachedByUs)) return false;
        if (team && !sides.some((s) => s.name === team)) return false;
        return true;
      }),
    [videos, coachedOnly, team],
  );

  // The picked video lives in the URL (?v=id) so a game can be shared; it falls back to the newest.
  const selected = (videos || []).find((v) => String(v.id) === searchParams.get("v")) || filtered[0] || null;
  const select = (video) => {
    setSearchParams({ v: video.id }, { replace: true });
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const groups = useMemo(() => {
    const result = [];
    filtered.forEach((video) => {
      const key = `${video.season.id}:${video.week.id}`;
      let group = result[result.length - 1];
      if (!group || group.key !== key) {
        group = { key, title: `${video.season.year} · ${weekLabel(video.week)}`, videos: [] };
        result.push(group);
      }
      group.videos.push(video);
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
        <>
          <Player video={selected} />
          <div className="mt-3">
            <h2 className="font-varsity text-xl uppercase tracking-[0.04em]">{selected.title || matchup(selected)}</h2>
            <p className="text-sm text-textSecondary dark:text-white/60">
              {selected.title && `${matchup(selected)} · `}
              {selected.season.year} · {weekLabel(selected.week)}
              {selected.bowlName && ` · ${selected.bowlName}`}
            </p>
          </div>
        </>
      )}

      {videos && videos.length > 0 && (
        <Card className="mt-6 flex flex-wrap items-center gap-3 p-3 text-sm">
          <label className="flex items-center gap-2">
            <input
              type="checkbox"
              checked={coachedOnly}
              onChange={(e) => {
                setCoachedOnly(e.target.checked);
                setTeam("");
              }}
            />
            User-coached games only
          </label>
          <select
            value={team}
            onChange={(e) => setTeam(e.target.value)}
            className="rounded-md border border-border bg-transparent px-2 py-1 dark:border-darkborder"
          >
            <option value="">All teams</option>
            {teams.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
          <span className="text-textSecondary">{filtered.length} games</span>
        </Card>
      )}

      {filtered.length > LATEST_COUNT && (
        <>
          <SectionTitle>Latest</SectionTitle>
          <Grid videos={filtered.slice(0, LATEST_COUNT)} selected={selected} onSelect={select} />
        </>
      )}

      {groups.map((group) => (
        <section key={group.key}>
          <SectionTitle>{group.title}</SectionTitle>
          <Grid videos={group.videos} selected={selected} onSelect={select} />
        </section>
      ))}
      {videos && videos.length > 0 && filtered.length === 0 && (
        <p className="mt-6 text-sm text-textSecondary">No games match these filters.</p>
      )}
    </div>
  );
}

export default WatchPage;
