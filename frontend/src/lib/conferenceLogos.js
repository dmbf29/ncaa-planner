import sunBelt from "../assets/conferences/sun-belt.png";

// Keyed by the college_seasons.conference string. Conferences without an
// entry simply render no logo — add a file to assets/conferences/ and a line
// here to light one up.
const CONFERENCE_LOGOS = {
  "Sun Belt": sunBelt,
};

export function conferenceLogo(conference) {
  return CONFERENCE_LOGOS[conference] ?? null;
}
