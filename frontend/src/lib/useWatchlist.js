import { useEffect, useState } from "react";

// Watched ids live in this browser only (no login), under the given localStorage key.
export default function useWatchlist(key) {
  const [ids, setIds] = useState(() => new Set());

  useEffect(() => {
    try {
      setIds(new Set(JSON.parse(localStorage.getItem(key) ?? "[]")));
    } catch {
      setIds(new Set());
    }
  }, [key]);

  const toggle = (id) =>
    setIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      try {
        localStorage.setItem(key, JSON.stringify([...next]));
      } catch {
        // storage unavailable: the star still works for this visit
      }
      return next;
    });

  return [ids, toggle];
}
