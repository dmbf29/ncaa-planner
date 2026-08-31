import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { fetchDynasties } from "../lib/apiClient";

// Resolves the logged-in user's dynasty and redirects to its shareable,
// ID-addressed show page — /dynasty stays as a convenience entry point for
// signed-in coaches, but /dynasty/:dynastyId is the real, linkable page.
function DynastyDashboardPage() {
  const navigate = useNavigate();
  const [error, setError] = useState(null);

  useEffect(() => {
    const resolve = async () => {
      try {
        const dynasties = await fetchDynasties();
        const dynasty = dynasties[0];
        if (!dynasty) {
          setError("No dynasty found yet.");
          return;
        }
        navigate(`/dynasty/${dynasty.id}`, { replace: true });
      } catch (err) {
        if (err.message?.toLowerCase().includes("unauthorized")) {
          navigate("/auth/login");
        } else {
          setError(err.message);
        }
      }
    };
    resolve();
  }, [navigate]);

  return (
    <p className="max-w-7xl mx-auto px-4 text-sm text-textSecondary">
      {error ? <span className="text-danger">{error}</span> : "Loading dynasty..."}
    </p>
  );
}

export default DynastyDashboardPage;
