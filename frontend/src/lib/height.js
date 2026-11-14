// Accepts 6'2, 6'2", 6-2, 6 2 or plain inches (74); returns inches or null when blank/unparseable.
export function parseHeight(text) {
  const t = text.trim();
  if (!t) return null;
  const ftIn = t.match(/^(\d)\s*['\-\s]\s*(\d{1,2})?\s*"?$/);
  if (ftIn) return Number(ftIn[1]) * 12 + Number(ftIn[2] ?? 0);
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

export const formatHeight = (inches) => (inches == null ? "—" : `${Math.floor(inches / 12)}'${inches % 12}"`);
