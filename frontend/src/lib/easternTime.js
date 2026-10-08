// Game and bowl kickoff times all come from schedule screenshots, which show
// Eastern time, and the API stores them as real instants. Always render them
// in Eastern so they read the same wherever the browser happens to be.
export const EASTERN_TIME_ZONE = "America/New_York";

// "Fri, Dec 26, 7:30 PM", mirroring the screenshots' own format.
export const formatEasternDateTime = (isoString) =>
  new Date(isoString).toLocaleString("en-US", {
    timeZone: EASTERN_TIME_ZONE,
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

// "Sep 4"
export const formatEasternDate = (isoString) =>
  new Date(isoString).toLocaleDateString("en-US", { timeZone: EASTERN_TIME_ZONE, month: "short", day: "numeric" });

// The "YYYY-MM-DDTHH:mm" Eastern wall-clock a datetime-local input needs.
export const toEasternDateTimeLocal = (isoString) => {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: EASTERN_TIME_ZONE,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    })
      .formatToParts(new Date(isoString))
      .map(({ type, value }) => [type, value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
};
