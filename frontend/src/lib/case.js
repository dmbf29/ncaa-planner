const toCamel = (str) =>
  str.replace(/[_-](\w)/g, (_, c) => c.toUpperCase());

export const keysToCamel = (obj) => {
  if (Array.isArray(obj)) return obj.map((v) => keysToCamel(v));
  if (obj && typeof obj === "object") {
    return Object.fromEntries(
      Object.entries(obj).map(([k, v]) => [toCamel(k), keysToCamel(v)]),
    );
  }
  return obj;
};

const toSnake = (str) =>
  str
    .replace(/([A-Z])/g, "_$1")
    .replace(/-/g, "_")
    .toLowerCase();

export const keysToSnake = (obj) => {
  if (Array.isArray(obj)) return obj.map((v) => keysToSnake(v));
  if (obj && typeof obj === "object") {
    return Object.fromEntries(
      Object.entries(obj).map(([k, v]) => [toSnake(k), keysToSnake(v)]),
    );
  }
  return obj;
};
