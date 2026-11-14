import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import useLatestSeason from "../lib/useLatestSeason";
import { fetchRecruitPool, fetchSeason, signRecruit } from "../lib/apiClient";

const inputClass =
  "rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const heightLabel = (inches) => (inches ? `${Math.floor(inches / 12)}'${inches % 12}"` : "");

function SignControl({ recruit, teams, onSign }) {
  const [collegeId, setCollegeId] = useState("");
  const [saving, setSaving] = useState(false);

  if (recruit.signedWith) return <span className="rounded-full bg-success/10 px-2 py-0.5 text-xs font-semibold text-success">Signed · {recruit.signedWith}</span>;

  const sign = async () => {
    setSaving(true);
    await onSign(recruit, Number(collegeId));
    setSaving(false);
  };

  return (
    <div className="flex items-center gap-2">
      <select value={collegeId} onChange={(e) => setCollegeId(e.target.value)} className={`${inputClass} w-36`}>
        <option value="">Team…</option>
        {teams.map((team) => (
          <option key={team.collegeId} value={team.collegeId}>{team.name}</option>
        ))}
      </select>
      <button
        type="button"
        onClick={sign}
        disabled={!collegeId || saving}
        className="rounded-md bg-burnt px-3 py-1.5 text-xs font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
      >
        {saving ? "Saving…" : "Sign"}
      </button>
    </div>
  );
}

function RecruitSearchPage() {
  const { dynastyId, seasonId, year, error: seasonError } = useLatestSeason();
  const [filters, setFilters] = useState({ q: "", position: "", stars: "", state: "", archetype: "" });
  const [data, setData] = useState(null);
  const [recruits, setRecruits] = useState([]);
  const [weekNumber, setWeekNumber] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);

  const search = useCallback(
    async (offset = 0) => {
      setLoading(true);
      setError(null);
      try {
        const params = Object.fromEntries(Object.entries({ ...filters, offset }).filter(([, value]) => value !== "" && value !== 0));
        const result = await fetchRecruitPool(dynastyId, seasonId, params);
        setData(result);
        setRecruits((current) => (offset ? [...current, ...result.recruits] : result.recruits));
      } catch (err) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    },
    [dynastyId, seasonId, filters],
  );

  useEffect(() => {
    if (!dynastyId) return undefined;
    const timer = setTimeout(() => search(0), 250);
    return () => clearTimeout(timer);
  }, [dynastyId, search]);

  useEffect(() => {
    if (!dynastyId) return;
    fetchSeason(dynastyId, seasonId)
      .then((season) => setWeekNumber(season.currentWeekNumber))
      .catch((err) => setError(err.message));
  }, [dynastyId, seasonId]);

  const sign = async (recruit, collegeId) => {
    setNotice(null);
    try {
      const result = await signRecruit(dynastyId, seasonId, recruit.rank, collegeId, weekNumber);
      setRecruits((current) => current.map((item) => (item.rank === recruit.rank ? { ...item, signedWith: result.signedWith } : item)));
      setNotice(`${recruit.name} signed with ${result.signedWith}.`);
    } catch (err) {
      setError(err.message);
    }
  };

  const setFilter = (key) => (event) => setFilters((current) => ({ ...current, [key]: event.target.value }));

  return (
    <div className="mx-auto max-w-6xl space-y-6 px-4">
      <PageHeader
        title="Recruits"
        eyebrow="Dynasty Updates"
        actions={
          <Link to="/dynasty/updates" className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10">
            Back
          </Link>
        }
      />

      <p className="text-sm text-textSecondary">
        The {year} recruit pool from Dynasty Rewired. Search it, then pick a team and press Sign to record a signing
        {weekNumber != null ? ` for Week ${weekNumber}` : ""}. Position stays ATH until the signing screen shows where the coach placed them.
      </p>

      <Card>
        <div className="flex flex-wrap gap-2 p-4">
          <input type="text" value={filters.q} onChange={setFilter("q")} placeholder="Search name…" autoComplete="off" data-1p-ignore className={`${inputClass} w-56`} />
          <select value={filters.position} onChange={setFilter("position")} className={inputClass}>
            <option value="">All positions</option>
            {(data?.filters.positions || []).map((value) => <option key={value} value={value}>{value}</option>)}
          </select>
          <select value={filters.stars} onChange={setFilter("stars")} className={inputClass}>
            <option value="">All stars</option>
            {[5, 4, 3, 2, 1].map((value) => <option key={value} value={value}>{value}★</option>)}
          </select>
          <select value={filters.state} onChange={setFilter("state")} className={inputClass}>
            <option value="">All states</option>
            {(data?.filters.states || []).map((value) => <option key={value} value={value}>{value}</option>)}
          </select>
          <select value={filters.archetype} onChange={setFilter("archetype")} className={inputClass}>
            <option value="">All archetypes</option>
            {(data?.filters.archetypes || []).map((value) => <option key={value} value={value}>{value}</option>)}
          </select>
        </div>
      </Card>

      {(seasonError || error) && <p className="text-sm text-danger">{seasonError || error}</p>}
      {notice && <p className="rounded-md bg-success/10 px-3 py-2 text-sm text-success">{notice}</p>}

      <Card>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase tracking-wide text-textSecondary">
              <tr>
                <th className="px-3 py-2">Nat</th>
                <th className="px-3 py-2">Name</th>
                <th className="px-3 py-2">Pos</th>
                <th className="px-3 py-2">Stars</th>
                <th className="px-3 py-2">Archetype</th>
                <th className="px-3 py-2">Hometown</th>
                <th className="px-3 py-2">Ht / Wt</th>
                <th className="px-3 py-2">Pipeline</th>
                <th className="px-3 py-2">St / Pos rank</th>
                <th className="px-3 py-2">Signing</th>
              </tr>
            </thead>
            <tbody className="text-textPrimary dark:text-white">
              {recruits.map((recruit) => (
                <tr key={recruit.rank} className="border-t border-border dark:border-darkborder">
                  <td className="px-3 py-2 font-semibold">{recruit.rank}</td>
                  <td className="px-3 py-2">{recruit.name}</td>
                  <td className="px-3 py-2">{recruit.position}</td>
                  <td className="px-3 py-2">{recruit.stars}★</td>
                  <td className="px-3 py-2">{recruit.archetype}</td>
                  <td className="px-3 py-2">{recruit.hometown}, {recruit.state}</td>
                  <td className="px-3 py-2">{heightLabel(recruit.heightInches)} {recruit.weightLbs}</td>
                  <td className="px-3 py-2">{recruit.pipeline}</td>
                  <td className="px-3 py-2">{recruit.stateRank} / {recruit.positionRank}</td>
                  <td className="px-3 py-2"><SignControl recruit={recruit} teams={data.teams} onSign={sign} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {loading && recruits.length === 0 && <p className="p-4 text-sm text-textSecondary">Loading the recruit pool (the first load takes a few seconds)…</p>}
        {data && !loading && recruits.length === 0 && <p className="p-4 text-sm text-textSecondary">No recruits match.</p>}
        {data && (
          <div className="flex items-center justify-between p-4 text-sm text-textSecondary">
            <span>Showing {recruits.length} of {data.total}</span>
            {recruits.length < data.total && (
              <button type="button" onClick={() => search(recruits.length)} disabled={loading} className="rounded-md border border-border px-3 py-1.5 text-charcoal disabled:opacity-60 dark:border-darkborder dark:text-white">
                Show more
              </button>
            )}
          </div>
        )}
      </Card>
    </div>
  );
}

export default RecruitSearchPage;
