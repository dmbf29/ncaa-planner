import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import PodcastEpisodePanel from "../components/PodcastEpisodePanel";
import { fetchDynasties, fetchSeason } from "../lib/apiClient";

const weekLabel = (week) => {
  if (week.conferenceChampionship) return "Conf. Champ";
  if (week.postSeason) return week.name || "Bowl";
  return `Week ${week.number}`;
};

// Every tab is one podcast episode: the weekly recap + preview, or a season-long show. Each is written, fact-checked,
// voiced and published from the page (see PodcastEpisodePanel); the id is the kind the backend's EpisodeSpec knows.
const EXPORT_TABS = [
  { id: "weekly", label: "Weekly Episode" },
  { id: "win_totals", label: "Win Totals: Over/Under" },
  { id: "roster_breakdown", label: "Roster Breakdown" },
  { id: "midseason_report_cards", label: "Midseason Report Cards" },
  { id: "end_of_season_report_cards", label: "End of Season Report Cards" },
  { id: "portal_preview", label: "Portal Preview" },
  { id: "nsd_breakdown", label: "Signing Day Breakdown" },
];

function ExportTabs({ activeTab, onSelect }) {
  return (
    <div className="mb-4 flex gap-1.5 flex-wrap">
      {EXPORT_TABS.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onSelect(tab.id)}
          className={clsx(
            "shrink-0 rounded-md px-3 py-1.5 text-sm font-semibold transition",
            tab.id === activeTab
              ? "bg-charcoal text-white dark:bg-white/10"
              : "border border-border text-textSecondary hover:bg-border/30 dark:border-darkborder dark:hover:bg-white/10",
          )}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}

function ExportPage() {
  const [season, setSeason] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const navigate = useNavigate();

  const [activeTab, setActiveTab] = useState(EXPORT_TABS[0].id);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setError("This dynasty doesn't have a season yet.");
          return;
        }
        const data = await fetchSeason(dynasty.id, latestSeason.id);
        setSeason({ ...data, dynastyId: dynasty.id });
      } catch (err) {
        setError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate]);

  const weeks = useMemo(() => {
    const source = season?.teams?.[0]?.weeks || [];
    return source.filter((w) => w.number !== 0).map((w) => ({ number: w.number, label: weekLabel(w) }));
  }, [season]);

  return (
    <div className="max-w-4xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Export"
        eyebrow={season ? `${season.dynasty.name} · ${season.year} Season` : "Dynasty"}
        actions={
          <Link
            to="/dynasty"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dashboard
          </Link>
        }
      />
      {loading && <p className="text-sm text-textSecondary">Loading dynasty...</p>}
      {error && <p className="text-sm text-danger">{error}</p>}

      {season && (
        <>
          <ExportTabs activeTab={activeTab} onSelect={setActiveTab} />
          <PodcastEpisodePanel key={activeTab} season={season} weeks={weeks} kind={activeTab} />
        </>
      )}
    </div>
  );
}

export default ExportPage;
