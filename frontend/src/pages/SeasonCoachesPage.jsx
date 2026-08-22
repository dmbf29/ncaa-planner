import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import Card from "../components/Card";
import { fetchCoachAssignments, commitCoachAssignments } from "../lib/apiClient";

const inputClass =
  "w-full rounded-md border border-border bg-white px-2 py-1.5 text-sm text-textPrimary focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white";

function CollegeSelect({ value, onChange, colleges }) {
  return (
    <select value={value ?? ""} onChange={(e) => onChange(e.target.value ? Number(e.target.value) : null)} className={inputClass}>
      <option value="">— no team this season —</option>
      {colleges.map((college) => (
        <option key={college.id} value={college.id}>
          {college.name}
        </option>
      ))}
    </select>
  );
}

function CoachRow({ assignment, collegeId, colleges, onChange }) {
  return (
    <tr className="border-b border-border align-top dark:border-darkborder">
      <td className="p-2">
        <p className="text-sm font-semibold text-charcoal dark:text-white">{assignment.coachName}</p>
        <p className="text-xs text-textSecondary">Last season: {assignment.previousCollegeName}</p>
      </td>
      <td className="p-2">
        <CollegeSelect value={collegeId} onChange={onChange} colleges={colleges} />
      </td>
    </tr>
  );
}

function CoachAssignmentsReview({ assignments, colleges, selections, onSelectionChange, onCommit, committing, error }) {
  return (
    <Card>
      <div className="p-5 space-y-4">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Coach Assignments</h3>
        <p className="text-sm text-textSecondary">
          Confirm each coach is still at the same school, move them to a different one, or leave them without a
          team this season.
        </p>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[500px] border-collapse text-left">
            <thead>
              <tr className="border-b border-border text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
                <th className="p-2">Coach</th>
                <th className="p-2">This Season</th>
              </tr>
            </thead>
            <tbody>
              {assignments.map((assignment) => (
                <CoachRow
                  key={assignment.coachId}
                  assignment={assignment}
                  colleges={colleges}
                  collegeId={selections[assignment.coachId] ?? null}
                  onChange={(collegeId) => onSelectionChange(assignment.coachId, collegeId)}
                />
              ))}
            </tbody>
          </table>
        </div>

        {error && <p className="text-sm text-danger">{error}</p>}

        <button
          type="button"
          onClick={onCommit}
          disabled={committing}
          className="rounded-md bg-burnt px-4 py-2 text-sm font-semibold text-white shadow-card transition hover:-translate-y-0.5 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {committing ? "Saving..." : "Save Coach Assignments"}
        </button>
      </div>
    </Card>
  );
}

function SeasonCoachesPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const dynastyId = searchParams.get("dynastyId");
  const seasonId = searchParams.get("seasonId");

  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(null);

  const [assignments, setAssignments] = useState([]);
  const [colleges, setColleges] = useState([]);
  const [selections, setSelections] = useState({});

  const [committing, setCommitting] = useState(false);
  const [commitError, setCommitError] = useState(null);
  const [saved, setSaved] = useState(false);
  const [warnings, setWarnings] = useState([]);

  useEffect(() => {
    const load = async () => {
      if (!dynastyId || !seasonId) {
        setLoadError("Missing dynasty or season.");
        setLoading(false);
        return;
      }
      setLoading(true);
      try {
        const result = await fetchCoachAssignments(dynastyId, seasonId);
        setAssignments(result.assignments || []);
        setColleges(result.colleges || []);
        setSelections(
          Object.fromEntries(
            (result.assignments || []).map((assignment) => [
              assignment.coachId,
              assignment.currentCollegeId ?? assignment.previousCollegeId ?? null,
            ]),
          ),
        );
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
  }, [dynastyId, seasonId, navigate]);

  const handleSelectionChange = (coachId, collegeId) => {
    setSelections((prev) => ({ ...prev, [coachId]: collegeId }));
  };

  const handleCommit = async () => {
    setCommitting(true);
    setCommitError(null);
    try {
      const payload = assignments.map((assignment) => ({
        coachId: assignment.coachId,
        collegeId: selections[assignment.coachId] ?? null,
      }));
      const result = await commitCoachAssignments(dynastyId, seasonId, payload);
      setWarnings(result.warnings || []);
      setSaved(true);
    } catch (err) {
      setCommitError(err.message);
    } finally {
      setCommitting(false);
    }
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
        title="Coach Assignments"
        eyebrow="New Season"
        actions={
          <Link
            to="/dynasty"
            className="rounded-md border border-border px-3 py-2 text-sm text-charcoal transition hover:bg-border/30 dark:border-darkborder dark:text-white dark:hover:bg-white/10"
          >
            Back to Dashboard
          </Link>
        }
      />

      {saved ? (
        <Card>
          <div className="p-5 space-y-2">
            <p className="text-sm font-semibold text-success">Saved! Coach assignments have been updated.</p>
            {warnings.length > 0 && (
              <div className="rounded-md border border-warning/40 bg-warning/10 p-3 text-sm text-textPrimary dark:text-white">
                <p className="font-semibold">{warnings.length} coach{warnings.length === 1 ? "" : "es"} couldn&rsquo;t be saved:</p>
                <ul className="mt-1 list-disc pl-5">
                  {warnings.map((warning, index) => (
                    <li key={index}>
                      {warning.coach}: {warning.error}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <Link to="/dynasty" className="text-sm text-burnt hover:underline">
              Back to Dashboard
            </Link>
          </div>
        </Card>
      ) : assignments.length === 0 ? (
        <Card>
          <div className="p-5 space-y-2">
            <p className="text-sm text-textPrimary dark:text-white">No coach reassignments needed.</p>
            <p className="text-sm text-textSecondary">
              This is likely your dynasty&rsquo;s first season, or no coaches were assigned last season.
            </p>
            <Link to="/dynasty" className="text-sm text-burnt hover:underline">
              Back to Dashboard
            </Link>
          </div>
        </Card>
      ) : (
        <>
          <Link to="/dynasty" className="inline-block text-sm text-burnt hover:underline">
            Skip — I&rsquo;ll do this later
          </Link>
          <CoachAssignmentsReview
            assignments={assignments}
            colleges={colleges}
            selections={selections}
            onSelectionChange={handleSelectionChange}
            onCommit={handleCommit}
            committing={committing}
            error={commitError}
          />
        </>
      )}
    </div>
  );
}

export default SeasonCoachesPage;
