import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { clsx } from "clsx";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { API_BASE_URL, fetchDynasties, fetchSeason } from "../lib/apiClient";

const weekLabel = (week) => {
  if (week.conferenceChampionship) return "Conf. Champ";
  if (week.postSeason) return week.name || "Bowl";
  return `Week ${week.number}`;
};

const downloadFile = async (url, filename) => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Request failed (${response.status})`);
  const text = await response.text();
  const blob = new Blob([text], { type: response.headers.get("content-type") || "text/plain" });
  const blobUrl = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = blobUrl;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(blobUrl);
};

const EXPORT_TABS = [
  { id: "weekly", label: "Weekly Recap & Preview" },
  { id: "win_totals", label: "Win Totals: Over/Under" },
  { id: "roster_breakdown", label: "Roster Breakdown" },
  { id: "midseason_report_cards", label: "Midseason Report Cards" },
  { id: "end_of_season_report_cards", label: "End of Season Report Cards" },
  { id: "portal_preview", label: "Portal Preview" },
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

function SegmentedControl({ options, value, onChange }) {
  return (
    <div className="inline-flex rounded-md border border-border p-0.5 dark:border-darkborder">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          onClick={() => onChange(option.value)}
          className={clsx(
            "rounded px-3 py-1.5 text-sm font-medium transition",
            value === option.value
              ? "bg-burnt text-white shadow-card"
              : "text-textSecondary hover:bg-border/30 dark:hover:bg-white/10",
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

function ExportCard({ title, description, format, setFormat, mode, setMode, url, filename, extraControls, disabled }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [copied, setCopied] = useState(false);

  const handleExport = async () => {
    setError(null);
    if (mode === "view") {
      window.open(url, "_blank", "noopener,noreferrer");
      return;
    }
    setBusy(true);
    try {
      await downloadFile(url, filename);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  const handleCopy = async () => {
    await navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <Card>
      <div className="p-5 space-y-4">
        <div>
          <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{title}</h3>
          <p className="mt-1 text-sm text-textSecondary">{description}</p>
        </div>

        {extraControls}

        <div className="flex flex-wrap items-center gap-6">
          <div className="space-y-1.5">
            <p className="text-xs uppercase tracking-wide text-textSecondary">Format</p>
            <SegmentedControl
              value={format}
              onChange={setFormat}
              options={[
                { value: "markdown", label: "Markdown" },
                { value: "json", label: "JSON" },
              ]}
            />
          </div>
          <div className="space-y-1.5">
            <p className="text-xs uppercase tracking-wide text-textSecondary">Viewing</p>
            <SegmentedControl
              value={mode}
              onChange={setMode}
              options={[
                { value: "download", label: "Download" },
                { value: "view", label: "View in browser" },
              ]}
            />
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-2 border-t border-border pt-4 dark:border-darkborder">
          <button
            type="button"
            onClick={handleExport}
            disabled={disabled || busy}
            className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busy ? "Exporting..." : mode === "view" ? "Open" : "Download"}
          </button>
          <button
            type="button"
            onClick={handleCopy}
            disabled={disabled}
            className="rounded-md border border-border px-4 py-2 text-sm text-charcoal transition hover:bg-border/30 disabled:cursor-not-allowed disabled:opacity-60 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            {copied ? "Copied!" : "Copy Link"}
          </button>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <p className="break-all rounded-md bg-charcoal/5 px-3 py-2 font-mono text-xs text-textSecondary dark:bg-white/10">
          {url}
        </p>
      </div>
    </Card>
  );
}

function ExportPage() {
  const [season, setSeason] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const navigate = useNavigate();

  const [winTotalsFormat, setWinTotalsFormat] = useState("markdown");
  const [winTotalsMode, setWinTotalsMode] = useState("download");

  const [weeksFormat, setWeeksFormat] = useState("markdown");
  const [weeksMode, setWeeksMode] = useState("download");
  const [selectedWeeks, setSelectedWeeks] = useState([]);

  const [teamBreakdownFormat, setTeamBreakdownFormat] = useState("markdown");
  const [teamBreakdownMode, setTeamBreakdownMode] = useState("download");

  const [midseasonReportCardsFormat, setMidseasonReportCardsFormat] = useState("markdown");
  const [midseasonReportCardsMode, setMidseasonReportCardsMode] = useState("download");

  const [endOfSeasonReportCardsFormat, setEndOfSeasonReportCardsFormat] = useState("markdown");
  const [endOfSeasonReportCardsMode, setEndOfSeasonReportCardsMode] = useState("download");

  const [portalPreviewFormat, setPortalPreviewFormat] = useState("markdown");
  const [portalPreviewMode, setPortalPreviewMode] = useState("download");

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

  const toggleWeek = (number) => {
    setSelectedWeeks((prev) => (prev.includes(number) ? prev.filter((n) => n !== number) : [...prev, number].sort((a, b) => a - b)));
  };

  const winTotalsUrl = season
    ? `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/win_totals${
        winTotalsFormat === "markdown" ? "?format=markdown" : ""
      }`
    : "";

  const weeksUrl = season
    ? (() => {
        const params = new URLSearchParams({ week_numbers: selectedWeeks.join(",") });
        if (weeksFormat === "markdown") params.set("format", "markdown");
        return `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/weeks?${params.toString()}`;
      })()
    : "";

  const teamBreakdownUrl = season
    ? `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/team_breakdown${
        teamBreakdownFormat === "markdown" ? "?format=markdown" : ""
      }`
    : "";

  const midseasonReportCardsUrl = season
    ? `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/midseason_report_cards${
        midseasonReportCardsFormat === "markdown" ? "?format=markdown" : ""
      }`
    : "";

  const endOfSeasonReportCardsUrl = season
    ? `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/end_of_season_report_cards${
        endOfSeasonReportCardsFormat === "markdown" ? "?format=markdown" : ""
      }`
    : "";

  const portalPreviewUrl = season
    ? `${API_BASE_URL}/api/v1/dynasties/${season.dynastyId}/seasons/${season.id}/portal_preview${
        portalPreviewFormat === "markdown" ? "?format=markdown" : ""
      }`
    : "";

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

          {activeTab === "weekly" && (
          <ExportCard
            title="Weekly Recap & Preview"
            description="Results, ranking movement, and next-game previews for our coached teams."
            format={weeksFormat}
            setFormat={setWeeksFormat}
            mode={weeksMode}
            setMode={setWeeksMode}
            url={weeksUrl}
            filename={`${season.year}_week-${selectedWeeks.join("-")}-recap.${weeksFormat === "markdown" ? "md" : "json"}`}
            disabled={selectedWeeks.length === 0}
            extraControls={
              <div className="space-y-1.5">
                <p className="text-xs uppercase tracking-wide text-textSecondary">
                  Week(s) to review
                </p>
                <p className="text-xs text-textSecondary/80">
                  Pick the week(s) you&rsquo;re recapping — each one already includes that week&rsquo;s results plus
                  every team&rsquo;s next scheduled game, so there&rsquo;s no separate &ldquo;preview week&rdquo; to
                  choose.
                </p>
                <div className="flex flex-wrap gap-2 pt-1">
                  {weeks.map((week) => (
                    <button
                      key={week.number}
                      type="button"
                      onClick={() => toggleWeek(week.number)}
                      className={clsx(
                        "rounded-md border px-3 py-1.5 text-sm transition",
                        selectedWeeks.includes(week.number)
                          ? "border-burnt bg-burnt text-white"
                          : "border-border text-charcoal hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10",
                      )}
                    >
                      {week.label}
                    </button>
                  ))}
                </div>
              </div>
            }
          />
          )}

          {activeTab === "win_totals" && (
          <ExportCard
            title="Win Totals: Over/Under"
            description="Projected Vegas-style win totals for our coached teams, with full schedule and opponent detail — hosts debate over/under, then predict each conference champion."
            format={winTotalsFormat}
            setFormat={setWinTotalsFormat}
            mode={winTotalsMode}
            setMode={setWinTotalsMode}
            url={winTotalsUrl}
            filename={`${season.year}_win-totals.${winTotalsFormat === "markdown" ? "md" : "json"}`}
          />
          )}

          {activeTab === "roster_breakdown" && (
          <ExportCard
            title="Roster Breakdown"
            description="Position-group-by-position-group comparison of our coached teams — best players, average ratings, NIL spend, and All-Americans, plus how we stack up against the rest of the conference."
            format={teamBreakdownFormat}
            setFormat={setTeamBreakdownFormat}
            mode={teamBreakdownMode}
            setMode={setTeamBreakdownMode}
            url={teamBreakdownUrl}
            filename={`${season.year}_team-breakdown.${teamBreakdownFormat === "markdown" ? "md" : "json"}`}
          />
          )}

          {activeTab === "midseason_report_cards" && (
          <ExportCard
            title="Midseason Report Cards"
            description="Letter-grade debate for our coached teams — record, pace against the preseason Vegas number, signature wins and bad losses, team stats, and conference standing, ending with what it'll take to improve for the rest of the season."
            format={midseasonReportCardsFormat}
            setFormat={setMidseasonReportCardsFormat}
            mode={midseasonReportCardsMode}
            setMode={setMidseasonReportCardsMode}
            url={midseasonReportCardsUrl}
            filename={`${season.year}_midseason-report-cards.${midseasonReportCardsFormat === "markdown" ? "md" : "json"}`}
          />
          )}

          {activeTab === "end_of_season_report_cards" && (
          <ExportCard
            title="End of Season Report Cards"
            description="Final letter-grade debate for our coached teams — final record, Vegas over/under verdict, signature wins and bad losses, final team stats, and conference standing, ending with season awards and each conference's actual champion vs. our preseason prediction. Run after the bowl games, before the transfer portal."
            format={endOfSeasonReportCardsFormat}
            setFormat={setEndOfSeasonReportCardsFormat}
            mode={endOfSeasonReportCardsMode}
            setMode={setEndOfSeasonReportCardsMode}
            url={endOfSeasonReportCardsUrl}
            filename={`${season.year}_end-of-season-report-cards.${endOfSeasonReportCardsFormat === "markdown" ? "md" : "json"}`}
          />
          )}

          {activeTab === "portal_preview" && (
          <ExportCard
            title="Portal Preview"
            description="Roster-planning preview for our coached teams ahead of the transfer portal — graduating seniors, early draft declarations, live in-portal storylines with a shot at returning, the most important losses, and which position groups need a new starter or more depth."
            format={portalPreviewFormat}
            setFormat={setPortalPreviewFormat}
            mode={portalPreviewMode}
            setMode={setPortalPreviewMode}
            url={portalPreviewUrl}
            filename={`${season.year}_portal-preview.${portalPreviewFormat === "markdown" ? "md" : "json"}`}
          />
          )}
        </>
      )}
    </div>
  );
}

export default ExportPage;
