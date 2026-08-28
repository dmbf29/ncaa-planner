import { useEffect, useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import FileDropZone from "../components/FileDropZone";
import {
  fetchDynasties,
  fetchSeason,
  fetchColleges,
  fetchBowlProjections,
  createBowlProjection,
  updateBowlProjection,
  deleteBowlProjection,
  analyzeBowlProjections,
  commitBowlProjections,
} from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

const CFP_ROUND_OPTIONS = [
  { value: "", label: "Not a CFP game" },
  { value: "first_round", label: "First Round" },
  { value: "quarterfinal", label: "Quarterfinal" },
  { value: "semifinal", label: "Semifinal" },
  { value: "championship", label: "National Championship" },
];

const CFP_ROUND_LABELS = CFP_ROUND_OPTIONS.reduce((acc, opt) => (opt.value ? { ...acc, [opt.value]: opt.label } : acc), {});

const emptyForm = { bowlName: "", cfpRound: "", projectedHomeCollegeId: null, projectedAwayCollegeId: null };

// Bowl projections are revealed all at once, in a single screenshot, only
// during the season's last two regular-season weeks and the conference
// championship week — never spread across the post-season bowl weeks the
// games themselves will eventually be played in.
const isProjectionWeek = (week) => week.conferenceChampionship || week.number === 13 || week.number === 14;

const weekLabel = (week) => {
  if (week.name) return week.name;
  if (week.conferenceChampionship) return "Conference Championship";
  return `Week ${week.number}`;
};

const isUnmatched = (rawName, collegeId) => rawName && collegeId == null && rawName.trim().toUpperCase() !== "TBD";

function CollegeSelect({ value, onChange, colleges }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} className={inputClass}>
      <option value="">TBD</option>
      {colleges.map((college) => (
        <option key={college.id} value={college.id}>
          {college.name}
        </option>
      ))}
    </select>
  );
}

function CfpRoundSelect({ value, onChange }) {
  return (
    <select value={value || ""} onChange={(e) => onChange(e.target.value || null)} className={inputClass}>
      {CFP_ROUND_OPTIONS.map((opt) => (
        <option key={opt.value} value={opt.value}>
          {opt.label}
        </option>
      ))}
    </select>
  );
}

function ReviewRow({ row, colleges, onChange }) {
  const update = (patch) => onChange({ ...row, ...patch });

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <input type="text" value={row.bowlName || ""} onChange={(e) => update({ bowlName: e.target.value })} className={inputClass} />
      </td>
      <td className="p-2">
        <CfpRoundSelect value={row.cfpRound} onChange={(cfpRound) => update({ cfpRound })} />
      </td>
      <td className="p-2">
        <CollegeSelect value={row.awayCollegeId} onChange={(awayCollegeId) => update({ awayCollegeId })} colleges={colleges} />
        {isUnmatched(row.awayRawName, row.awayCollegeId) && (
          <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.awayRawName}&rdquo;</p>
        )}
      </td>
      <td className="p-2">
        <CollegeSelect value={row.homeCollegeId} onChange={(homeCollegeId) => update({ homeCollegeId })} colleges={colleges} />
        {isUnmatched(row.homeRawName, row.homeCollegeId) && (
          <p className="mt-1 text-xs text-danger">Unmatched: &ldquo;{row.homeRawName}&rdquo;</p>
        )}
      </td>
      <td className="p-2">
        <button type="button" onClick={() => onChange(null)} className="text-xs text-danger hover:underline">
          Remove
        </button>
      </td>
    </tr>
  );
}

function ReviewTable({ rows, colleges, onChange, onCommit, onDiscard, committing, error }) {
  const updateRow = (index, nextRow) => {
    if (nextRow === null) {
      onChange(rows.filter((_, i) => i !== index));
      return;
    }
    onChange(rows.map((row, i) => (i === index ? nextRow : row)));
  };

  return (
    <div className="space-y-3 border-t border-border pt-4 dark:border-darkborder">
      <p className="text-sm text-textSecondary">
        Confirm every row below — fix any unmatched colleges and set the CFP round for playoff bowls (it can&rsquo;t
        always be read off the bowl&rsquo;s sponsor name) — then save.
      </p>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[700px] border-collapse text-left">
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="p-2">Bowl</th>
              <th className="p-2">CFP Round</th>
              <th className="p-2">Away</th>
              <th className="p-2">Home</th>
              <th className="p-2"></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, index) => (
              <ReviewRow key={index} row={row} colleges={colleges} onChange={(next) => updateRow(index, next)} />
            ))}
          </tbody>
        </table>
      </div>

      {error && <p className="text-sm text-danger">{error}</p>}

      <div className="flex gap-2">
        <button
          type="button"
          onClick={onCommit}
          disabled={committing || rows.length === 0}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : `Save ${rows.length} Projection${rows.length === 1 ? "" : "s"}`}
        </button>
        <button
          type="button"
          onClick={onDiscard}
          className="rounded-md border border-border px-4 py-2 text-sm text-textSecondary hover:bg-border/40 dark:border-darkborder dark:hover:bg-white/10"
        >
          Discard
        </button>
      </div>
    </div>
  );
}

function ProjectionForm({ form, onChange, colleges, onSubmit, onCancel, editing, saving, error }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Bowl / Game Name</span>
        <input
          type="text"
          placeholder="e.g. Alamo Bowl"
          value={form.bowlName}
          onChange={(e) => onChange({ ...form, bowlName: e.target.value })}
          className={inputClass}
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">CFP Round</span>
        <CfpRoundSelect value={form.cfpRound} onChange={(cfpRound) => onChange({ ...form, cfpRound: cfpRound || "" })} />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Projected Away</span>
        <CollegeSelect
          value={form.projectedAwayCollegeId}
          onChange={(id) => onChange({ ...form, projectedAwayCollegeId: id })}
          colleges={colleges}
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-xs uppercase tracking-wide text-textSecondary">Projected Home</span>
        <CollegeSelect
          value={form.projectedHomeCollegeId}
          onChange={(id) => onChange({ ...form, projectedHomeCollegeId: id })}
          colleges={colleges}
        />
      </label>

      {error && <p className="sm:col-span-2 text-sm text-danger">{error}</p>}

      <div className="sm:col-span-2 flex gap-2">
        <button
          type="button"
          onClick={onSubmit}
          disabled={saving || !form.bowlName}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {saving ? "Saving..." : editing ? "Save Changes" : "Add Projection"}
        </button>
        {editing && (
          <button
            type="button"
            onClick={onCancel}
            className="rounded-md border border-border px-4 py-2 text-sm text-textSecondary hover:bg-border/40 dark:border-darkborder dark:hover:bg-white/10"
          >
            Cancel
          </button>
        )}
      </div>
    </div>
  );
}

function WeekStatusBadge({ week, count, active, onClick }) {
  const uploaded = count > 0;
  const tone = uploaded ? "bg-success/10 text-success" : "bg-textSecondary/10 text-textSecondary";

  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-full px-3 py-1 text-xs font-semibold transition ${tone} ${active ? "ring-2 ring-burnt" : ""}`}
    >
      {weekLabel(week)} · {uploaded ? `${count} saved` : "not uploaded"}
    </button>
  );
}

function ProjectionRow({ projection, colleges, onEdit, onDelete }) {
  const collegeName = (id) => colleges.find((c) => c.id === id)?.name || "TBD";

  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2 text-sm text-textPrimary dark:text-white">{projection.bowlName}</td>
      <td className="p-2 text-sm text-textSecondary">{CFP_ROUND_LABELS[projection.cfpRound] || "—"}</td>
      <td className="p-2 text-sm text-textPrimary dark:text-white">
        {collegeName(projection.projectedAwayCollegeId)} @ {collegeName(projection.projectedHomeCollegeId)}
      </td>
      <td className="p-2 text-right">
        <button type="button" onClick={() => onEdit(projection)} className="mr-3 text-xs text-burnt hover:underline">
          Edit
        </button>
        <button type="button" onClick={() => onDelete(projection)} className="text-xs text-danger hover:underline">
          Delete
        </button>
      </td>
    </tr>
  );
}

function BowlProjectionsUpdatePage() {
  const navigate = useNavigate();

  const [weeks, setWeeks] = useState([]);
  const [colleges, setColleges] = useState([]);
  const [selectedWeekId, setSelectedWeekId] = useState("");
  const [projections, setProjections] = useState([]);
  const [weekSummaries, setWeekSummaries] = useState({});
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);
  const [listLoading, setListLoading] = useState(false);

  const [files, setFiles] = useState([]);
  const [analyzing, setAnalyzing] = useState(false);
  const [analyzeError, setAnalyzeError] = useState(null);
  const [reviewRows, setReviewRows] = useState(null);
  const [committingReview, setCommittingReview] = useState(false);
  const [reviewError, setReviewError] = useState(null);
  const [reviewWarnings, setReviewWarnings] = useState([]);

  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [formError, setFormError] = useState(null);

  useEffect(() => {
    const load = async () => {
      setLoading(true);
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setLoadError("No dynasty found yet.");
          return;
        }
        const latestSeason = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!latestSeason) {
          setLoadError("This dynasty doesn't have a season yet.");
          return;
        }
        const [season, collegeList] = await Promise.all([fetchSeason(dynasty.id, latestSeason.id), fetchColleges()]);
        const projectionWeeks = (season.teams?.[0]?.weeks || []).filter(isProjectionWeek);
        setWeeks(projectionWeeks);
        setColleges(collegeList);
        setSelectedWeekId(projectionWeeks[0]?.id || "");

        const counts = await Promise.all(
          projectionWeeks.map((week) => fetchBowlProjections(week.id).then((rows) => [ week.id, rows.length ]))
        );
        setWeekSummaries(Object.fromEntries(counts));
      } catch (err) {
        setLoadError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        }
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [navigate]);

  const refreshProjections = () => {
    if (!selectedWeekId) return;
    setListLoading(true);
    return fetchBowlProjections(selectedWeekId)
      .then((rows) => {
        setProjections(rows);
        setWeekSummaries((prev) => ({ ...prev, [selectedWeekId]: rows.length }));
      })
      .catch((err) => setLoadError(err.message))
      .finally(() => setListLoading(false));
  };

  useEffect(() => {
    refreshProjections();
    setFiles([]);
    setReviewRows(null);
    setReviewWarnings([]);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedWeekId]);

  const resetForm = () => {
    setForm(emptyForm);
    setEditingId(null);
    setFormError(null);
  };

  const handleEdit = (projection) => {
    setForm({
      bowlName: projection.bowlName,
      cfpRound: projection.cfpRound || "",
      projectedHomeCollegeId: projection.projectedHomeCollegeId,
      projectedAwayCollegeId: projection.projectedAwayCollegeId,
    });
    setEditingId(projection.id);
    setFormError(null);
  };

  const handleDelete = async (projection) => {
    try {
      await deleteBowlProjection(selectedWeekId, projection.id);
      setProjections((prev) => {
        const next = prev.filter((p) => p.id !== projection.id);
        setWeekSummaries((summaries) => ({ ...summaries, [selectedWeekId]: next.length }));
        return next;
      });
      if (editingId === projection.id) resetForm();
    } catch (err) {
      setLoadError(err.message);
    }
  };

  const handleFormSubmit = async () => {
    setSaving(true);
    setFormError(null);
    const payload = { ...form, cfpRound: form.cfpRound || null };
    try {
      if (editingId) {
        const updated = await updateBowlProjection(selectedWeekId, editingId, payload);
        setProjections((prev) => prev.map((p) => (p.id === editingId ? updated : p)));
      } else {
        const created = await createBowlProjection(selectedWeekId, payload);
        setProjections((prev) => {
          const next = [ ...prev, created ];
          setWeekSummaries((summaries) => ({ ...summaries, [selectedWeekId]: next.length }));
          return next;
        });
      }
      resetForm();
    } catch (err) {
      setFormError(err.message);
    } finally {
      setSaving(false);
    }
  };

  const handleAnalyze = async () => {
    setAnalyzing(true);
    setAnalyzeError(null);
    try {
      const result = await analyzeBowlProjections(selectedWeekId, files);
      setReviewRows(result.rows);
    } catch (err) {
      setAnalyzeError(err.message);
    } finally {
      setAnalyzing(false);
    }
  };

  const handleReviewCommit = async () => {
    setCommittingReview(true);
    setReviewError(null);
    try {
      const result = await commitBowlProjections(selectedWeekId, reviewRows);
      setReviewWarnings(result.warnings || []);
      setReviewRows(null);
      setFiles([]);
      await refreshProjections();
    } catch (err) {
      setReviewError(err.message);
    } finally {
      setCommittingReview(false);
    }
  };

  const handleReviewDiscard = () => {
    setReviewRows(null);
    setReviewError(null);
  };

  if (loading) {
    return (
      <div className="max-w-4xl mx-auto px-4">
        <p className="text-sm text-textSecondary">Loading...</p>
      </div>
    );
  }

  if (loadError) {
    return (
      <div className="max-w-4xl mx-auto px-4">
        <p className="text-sm text-danger">{loadError}</p>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto px-4 space-y-6">
      <PageHeader
        title="Bowl Projections"
        eyebrow="Dynasty Updates"
        actions={
          <Link
            to="/dynasty/updates"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Updates
          </Link>
        }
      />

      <Card>
        <div className="p-5 space-y-4">
          <p className="text-sm text-textSecondary">
            Track who&rsquo;s projected to play in each bowl/CFP game before it&rsquo;s official — these are separate
            from the real scheduled games, so they can be updated freely as picks shift. Projections are usually
            revealed all at once on Week 13, Week 14, or the Conference Championship week — pick whichever week
            this screenshot was taken on, not the week the bowl will actually be played.
          </p>

          {weeks.length === 0 ? (
            <p className="text-sm text-textSecondary">No eligible weeks found for this season.</p>
          ) : (
            <>
              <label className="flex flex-col gap-1 text-sm">
                <span className="text-xs uppercase tracking-wide text-textSecondary">Observed In Week</span>
                <select
                  value={selectedWeekId}
                  onChange={(e) => setSelectedWeekId(Number(e.target.value))}
                  className={`${inputClass} max-w-xs`}
                >
                  {weeks.map((week) => (
                    <option key={week.id} value={week.id}>
                      {weekLabel(week)}
                    </option>
                  ))}
                </select>
              </label>

              <div className="flex flex-wrap gap-2">
                {weeks.map((week) => (
                  <WeekStatusBadge
                    key={week.id}
                    week={week}
                    count={weekSummaries[week.id] ?? 0}
                    active={week.id === selectedWeekId}
                    onClick={() => setSelectedWeekId(week.id)}
                  />
                ))}
              </div>

              {reviewWarnings.length > 0 && (
                <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                  <p className="font-semibold">{reviewWarnings.length} row{reviewWarnings.length === 1 ? "" : "s"} couldn&rsquo;t be saved:</p>
                  <ul className="mt-1 list-disc pl-5">
                    {reviewWarnings.map((warning, index) => (
                      <li key={index}>
                        {warning.bowlName}: {warning.error}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {listLoading ? (
                <p className="text-sm text-textSecondary">Loading projections...</p>
              ) : (
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[600px] border-collapse text-left">
                    <thead>
                      <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                        <th className="p-2">Bowl</th>
                        <th className="p-2">Round</th>
                        <th className="p-2">Projected Matchup</th>
                        <th className="p-2"></th>
                      </tr>
                    </thead>
                    <tbody>
                      {projections.map((projection) => (
                        <ProjectionRow
                          key={projection.id}
                          projection={projection}
                          colleges={colleges}
                          onEdit={handleEdit}
                          onDelete={handleDelete}
                        />
                      ))}
                      {projections.length === 0 && (
                        <tr>
                          <td colSpan={4} className="p-2 text-sm text-textSecondary">
                            No projections yet for this week.
                          </td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </div>
              )}

              <div className="border-t border-border pt-4 dark:border-darkborder">
                <h3 className="mb-3 font-varsity text-sm uppercase tracking-[0.06em] text-charcoal dark:text-white">
                  Upload Screenshots
                </h3>
                <div className="space-y-3">
                  <FileDropZone
                    title="Bowl Projection Screenshots"
                    hint="Upload as many screenshots as it takes to cover the full bowl list."
                    files={files}
                    onFilesChange={setFiles}
                  />
                  {analyzeError && <p className="text-sm text-danger">{analyzeError}</p>}
                  <button
                    type="button"
                    onClick={handleAnalyze}
                    disabled={files.length === 0 || analyzing}
                    className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {analyzing ? "Analyzing... this can take a minute" : `Analyze ${files.length || ""} Photo${files.length === 1 ? "" : "s"}`}
                  </button>
                </div>

                {reviewRows && (
                  <ReviewTable
                    rows={reviewRows}
                    colleges={colleges}
                    onChange={setReviewRows}
                    onCommit={handleReviewCommit}
                    onDiscard={handleReviewDiscard}
                    committing={committingReview}
                    error={reviewError}
                  />
                )}
              </div>

              <div className="border-t border-border pt-4 dark:border-darkborder">
                <h3 className="mb-3 font-varsity text-sm uppercase tracking-[0.06em] text-charcoal dark:text-white">
                  {editingId ? "Edit Projection" : "Add a Single Projection Manually"}
                </h3>
                <ProjectionForm
                  form={form}
                  onChange={setForm}
                  colleges={colleges}
                  onSubmit={handleFormSubmit}
                  onCancel={resetForm}
                  editing={!!editingId}
                  saving={saving}
                  error={formError}
                />
              </div>
            </>
          )}
        </div>
      </Card>
    </div>
  );
}

export default BowlProjectionsUpdatePage;
