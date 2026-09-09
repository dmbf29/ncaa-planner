import { useEffect, useMemo, useRef, useState } from "react";

// Checkbox dropdown for filtering a list down to several values at once.
// `options` is [{ value, label, group? }]; `selected`/`onChange` deal in
// plain arrays of `value` strings. Pass `searchable` when the option list is
// long enough to need a filter box (teams).
function MultiSelect({ label, options, selected, onChange, searchable = false }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const rootRef = useRef(null);

  useEffect(() => {
    if (!open) return undefined;
    const onDocClick = (e) => {
      if (rootRef.current && !rootRef.current.contains(e.target)) setOpen(false);
    };
    const onKey = (e) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const labelFor = useMemo(() => {
    const map = new Map(options.map((o) => [o.value, o.label]));
    return (value) => map.get(value) ?? value;
  }, [options]);

  const summary =
    selected.length === 0
      ? "All"
      : selected.length <= 2
        ? selected.map(labelFor).join(", ")
        : `${selected.length} selected`;

  const visibleOptions = useMemo(() => {
    const q = query.trim().toLowerCase();
    return q ? options.filter((o) => o.label.toLowerCase().includes(q)) : options;
  }, [options, query]);

  // Group options under their first-seen group heading, preserving order.
  const groups = useMemo(() => {
    const order = [];
    const byGroup = new Map();
    visibleOptions.forEach((o) => {
      const key = o.group ?? "";
      if (!byGroup.has(key)) {
        byGroup.set(key, []);
        order.push(key);
      }
      byGroup.get(key).push(o);
    });
    return order.map((key) => [key, byGroup.get(key)]);
  }, [visibleOptions]);

  const toggle = (value) =>
    onChange(selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value]);

  return (
    <div ref={rootRef} className="relative">
      <span className="mb-1 block text-xs font-semibold uppercase tracking-wide text-textSecondary">{label}</span>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center justify-between gap-2 rounded-md border border-border bg-white px-2 py-1.5 text-left text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darksurface dark:text-white"
      >
        <span className={`truncate ${selected.length === 0 ? "text-textSecondary" : "text-textPrimary dark:text-white"}`}>
          {summary}
        </span>
        <i className={`fa-solid fa-chevron-down text-[10px] text-textSecondary transition ${open ? "rotate-180" : ""}`} />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-20 mt-1 max-h-72 w-full min-w-[220px] overflow-auto rounded-md border border-border bg-white p-1 shadow-card dark:border-darkborder dark:bg-darksurface">
          {searchable && (
            <input
              type="text"
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={`Search ${label.toLowerCase()}`}
              className="mb-1 w-full rounded border border-border bg-white px-2 py-1 text-sm focus:border-burnt focus:outline-none dark:border-darkborder dark:bg-darkbg dark:text-white"
            />
          )}
          {selected.length > 0 && (
            <button
              type="button"
              onClick={() => onChange([])}
              className="mb-1 w-full rounded px-2 py-1 text-left text-xs text-burnt hover:bg-burnt/10"
            >
              Clear {label.toLowerCase()}
            </button>
          )}
          {groups.map(([group, opts]) => (
            <div key={group || "_ungrouped"}>
              {group && (
                <p className="px-2 pb-0.5 pt-1.5 text-[10px] font-semibold uppercase tracking-wide text-textSecondary">
                  {group}
                </p>
              )}
              {opts.map((o) => (
                <label
                  key={o.value}
                  className="flex cursor-pointer items-center gap-2 rounded px-2 py-1 text-sm hover:bg-charcoal/5 dark:hover:bg-white/10"
                >
                  <input
                    type="checkbox"
                    checked={selected.includes(o.value)}
                    onChange={() => toggle(o.value)}
                    className="accent-burnt"
                  />
                  <span className="truncate text-textPrimary dark:text-white">{o.label}</span>
                </label>
              ))}
            </div>
          ))}
          {visibleOptions.length === 0 && (
            <p className="px-2 py-2 text-center text-xs text-textSecondary">No matches</p>
          )}
        </div>
      )}
    </div>
  );
}

export default MultiSelect;
