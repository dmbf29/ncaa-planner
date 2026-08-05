import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";

const UPDATE_TYPES = [
  { key: "top25", label: "Update Top 25", description: "Upload the weekly AP-style poll screenshots.", to: "/dynasty/updates/top25" },
  { key: "games", label: "Add Games/Results", description: "Coming soon." },
  { key: "heisman", label: "Add Heisman Candidates", description: "Coming soon." },
  { key: "standings", label: "Update Conference Standings", description: "Coming soon." },
  { key: "team-stats", label: "Update Team Stats", description: "Coming soon." },
  { key: "player-stats", label: "Update Player Stats", description: "Coming soon." },
  { key: "all-americans", label: "Add All-Americans", description: "Coming soon." },
];

function UpdateCard({ update }) {
  const content = (
    <div className="p-5 space-y-1">
      <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">{update.label}</h3>
      <p className="text-sm text-textSecondary">{update.description}</p>
    </div>
  );

  if (!update.to) {
    return <Card className="opacity-50">{content}</Card>;
  }

  return (
    <Link to={update.to}>
      <Card className="transition hover:-translate-y-0.5">{content}</Card>
    </Link>
  );
}

function DynastyUpdatesPage() {
  return (
    <div className="max-w-5xl mx-auto px-4">
      <PageHeader
        title="Dynasty Updates"
        eyebrow="Upload screenshots to update your dynasty"
        actions={
          <Link
            to="/dynasty"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dashboard
          </Link>
        }
      />
      <div className="grid gap-4 pb-8 sm:grid-cols-2">
        {UPDATE_TYPES.map((update) => (
          <UpdateCard key={update.key} update={update} />
        ))}
      </div>
    </div>
  );
}

export default DynastyUpdatesPage;
