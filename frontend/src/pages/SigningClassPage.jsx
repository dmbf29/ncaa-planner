import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import OverallBadge from "../components/OverallBadge";
import { fetchSigningClass } from "../lib/apiClient";

const FILTERS = [
  { id: "all", label: "All" },
  { id: "transfer", label: "Transfers" },
  { id: "high_school", label: "HS" },
  { id: "juco", label: "JUCO" },
];

const TYPE_LABELS = { transfer: "Transfer", high_school: "HS", juco: "JUCO" };

const linkClass =
  "rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10";

function SigneeRow({ signee }) {
  const isTransfer = signee.type === "transfer";

  return (
    <tr className="border-b border-border dark:border-darkborder">
      <td className="px-3 py-2 font-medium text-charcoal dark:text-white">{signee.name}</td>
      <td className="px-3 py-2 text-textSecondary">{signee.position}</td>
      <td className="px-3 py-2 text-textSecondary">{TYPE_LABELS[signee.type]}</td>
      <td className="px-3 py-2 text-textSecondary">{signee.starRating ? `${signee.starRating}★` : "—"}</td>
      <td className="px-3 py-2 text-textSecondary">{signee.classYear || "—"}</td>
      <td className="px-3 py-2 text-center">
        {signee.overall != null ? <OverallBadge value={signee.overall} /> : <span className="text-textSecondary">—</span>}
      </td>
      <td className="px-3 py-2 text-textSecondary">
        {isTransfer ? (
          signee.matched ? (
            signee.fromCollege
          ) : (
            <span className="italic" title="Not linked to a player on a previous roster">
              unlinked
            </span>
          )
        ) : (
          signee.state || "—"
        )}
      </td>
      <td className="px-3 py-2 text-right tabular-nums text-textSecondary">
        {signee.nilAmount != null ? signee.nilAmount.toLocaleString() : "—"}
      </td>
    </tr>
  );
}

function SigningClassPage() {
  const { dynastyId, seasonId, collegeSeasonId } = useParams();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);
  const [filter, setFilter] = useState("all");

  useEffect(() => {
    setData(null);
    setError(null);
    fetchSigningClass(dynastyId, seasonId, collegeSeasonId)
      .then(setData)
      .catch(() => setError("Couldn't load the signing class."));
  }, [dynastyId, seasonId, collegeSeasonId]);

  const classPath = (target) =>
    `/dynasty/${dynastyId}/seasons/${target.seasonId}/college_seasons/${target.collegeSeasonId}/signing-class`;

  const signees = data ? data.signees.filter((s) => filter === "all" || s.type === filter) : [];
  const countFor = (id) => (data ? data.signees.filter((s) => id === "all" || s.type === id).length : 0);

  return (
    <div className="max-w-5xl mx-auto px-4 space-y-4">
      <PageHeader
        title={data ? `${data.college.name} Signing Class` : "Signing Class"}
        eyebrow={data ? `Signed in ${data.season.year}` : undefined}
        actions={
          <>
            {data?.previousSeason && (
              <Link to={classPath(data.previousSeason)} className={linkClass}>
                &larr; {data.previousSeason.year}
              </Link>
            )}
            {data?.nextSeason && (
              <Link to={classPath(data.nextSeason)} className={linkClass}>
                {data.nextSeason.year} &rarr;
              </Link>
            )}
            <Link to="/dynasty" className={linkClass}>
              Back to Dashboard
            </Link>
          </>
        }
      />

      {error && <p className="text-sm text-danger">{error}</p>}
      {!data && !error && <p className="text-sm text-textSecondary">Loading…</p>}

      {data && (
        <>
          <div className="flex flex-wrap gap-2">
            {FILTERS.map(({ id, label }) => (
              <button
                key={id}
                type="button"
                onClick={() => setFilter(id)}
                className={
                  filter === id
                    ? "rounded-full bg-burnt px-3 py-1 text-xs font-semibold uppercase tracking-wide text-white"
                    : "rounded-full border border-border px-3 py-1 text-xs font-semibold uppercase tracking-wide text-textSecondary hover:bg-border/30 dark:border-darkborder"
                }
              >
                {label} ({countFor(id)})
              </button>
            ))}
          </div>

          <Card className="overflow-x-auto">
            {signees.length === 0 ? (
              <p className="p-4 text-sm text-textSecondary">No signees recorded.</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                    <th className="px-3 py-2">Player</th>
                    <th className="px-3 py-2">Pos</th>
                    <th className="px-3 py-2">Type</th>
                    <th className="px-3 py-2">Stars</th>
                    <th className="px-3 py-2">Class</th>
                    <th className="px-3 py-2 text-center">OVR</th>
                    <th className="px-3 py-2">From</th>
                    <th className="px-3 py-2 text-right">NIL</th>
                  </tr>
                </thead>
                <tbody>
                  {signees.map((signee) => (
                    <SigneeRow key={signee.id} signee={signee} />
                  ))}
                </tbody>
              </table>
            )}
          </Card>
        </>
      )}
    </div>
  );
}

export default SigningClassPage;
