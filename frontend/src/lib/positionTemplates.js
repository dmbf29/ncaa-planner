export const offenseTemplate = [
  { name: "QB", slotsCount: 4, sortOrder: 1 },
  { name: "HB", slotsCount: 6, sortOrder: 2 },
  { name: "WR", slotsCount: 9, sortOrder: 3 },
  { name: "TE", slotsCount: 3, sortOrder: 4 },
  { name: "LT", slotsCount: 4, sortOrder: 5 },
  { name: "RT", slotsCount: 4, sortOrder: 6 },
  { name: "LG", slotsCount: 4, sortOrder: 7 },
  { name: "RG", slotsCount: 4, sortOrder: 8 },
  { name: "C", slotsCount: 4, sortOrder: 9 },
  { name: "K", slotsCount: 1, sortOrder: 10 },
  { name: "P", slotsCount: 1, sortOrder: 11 },
];

export const defenseTemplate = [
  { name: "LE", slotsCount: 4, sortOrder: 1 },
  { name: "RE", slotsCount: 4, sortOrder: 2 },
  { name: "DT", slotsCount: 6, sortOrder: 3 },
  { name: "WILL", slotsCount: 3, sortOrder: 4 },
  { name: "SAM", slotsCount: 4, sortOrder: 5 },
  { name: "MIKE", slotsCount: 4, sortOrder: 6 },
  { name: "CB", slotsCount: 8, sortOrder: 7 },
  { name: "FS", slotsCount: 4, sortOrder: 8 },
  { name: "SS", slotsCount: 4, sortOrder: 9 },
];

export const offenseOptionalPositions = ["FB", "OT", "OG", "OL", "K/P", "OTHER"];
export const defenseOptionalPositions = ["DE", "OLB", "LB", "DB", "NICKEL", "OTHER"];

export const offensePositionNames = offenseTemplate.map((pos) => pos.name);
export const defensePositionNames = defenseTemplate.map((pos) => pos.name);

export const uniqueOrdered = (list) => {
  const seen = new Set();
  const ordered = [];
  list.forEach((item) => {
    if (!seen.has(item)) {
      seen.add(item);
      ordered.push(item);
    }
  });
  return ordered;
};

export const isOffenseSquad = (squad) => squad?.name?.toLowerCase()?.includes("off");

export const getAvailablePositions = (squad) => {
  const base = isOffenseSquad(squad) ? offensePositionNames : defensePositionNames;
  const optional = isOffenseSquad(squad) ? offenseOptionalPositions : defenseOptionalPositions;
  return uniqueOrdered([...base, ...optional]);
};

export const getDefaultSelection = (squad) =>
  isOffenseSquad(squad) ? offensePositionNames : defensePositionNames;

export const getDefaultSlotsCount = (squad, name) => {
  const template = (isOffenseSquad(squad) ? offenseTemplate : defenseTemplate).find(
    (pos) => pos.name === name,
  );
  return template?.slotsCount ?? 1;
};

// Derived from the same order used for display, so saved sort_order always matches
// what the user sees rather than depending on server-side insertion order (which can
// race when boards are created concurrently).
export const getDefaultSortOrder = (squad, name) => {
  const order = getAvailablePositions(squad);
  const index = order.indexOf(name);
  return index === -1 ? order.length + 1 : index + 1;
};

export const sortByPositionOrder = (names, squad) => {
  const order = getAvailablePositions(squad);
  const orderMap = new Map(order.map((name, index) => [name, index]));
  return [...names].sort((a, b) => {
    const ai = orderMap.has(a) ? orderMap.get(a) : Number.MAX_SAFE_INTEGER;
    const bi = orderMap.has(b) ? orderMap.get(b) : Number.MAX_SAFE_INTEGER;
    if (ai !== bi) return ai - bi;
    return a.localeCompare(b);
  });
};
