import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { fetchDynasties } from "./apiClient";

// The first dynasty's newest season, for the Dynasty Update pages that always work on "this season".
export default function useLatestSeason() {
  const navigate = useNavigate();
  const [ids, setIds] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    const load = async () => {
      try {
        const dynasty = (await fetchDynasties())[0];
        if (!dynasty) return setError("No dynasty found yet.");
        const season = [...(dynasty.seasons || [])].sort((a, b) => b.year - a.year)[0];
        if (!season) return setError("This dynasty doesn't have a season yet.");
        setIds({ dynastyId: dynasty.id, seasonId: season.id, year: season.year });
      } catch (err) {
        setError(err.message);
        if (err.message?.toLowerCase().includes("unauthorized")) navigate("/auth/login");
      }
    };
    load();
  }, [navigate]);

  return { ...ids, error };
}
