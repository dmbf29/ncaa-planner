// NotebookLM prompts that pair with each exported Markdown source (the weekly episode no longer uses one: it is
// written and voiced in-house, see Podcast::WeeklyRun on the backend). Only the
// week(s), year, filename and team names vary, so they're built here from the
// export page's state instead of living in notes. Section names referenced in
// the prompts (SHOW DIRECTIVE, SHOW BRIEF, MANDATORY SHOW OPENING, ...) must
// match the headings the backend presenters emit.
const SHOW_NAME = "Rising in the Sun Belt";
const HOSTS = "Arlis Boardingham and Ty Simpson";

const numbered = (items) => items.map((item, index) => `${index + 1}. ${item}`).join("\n");

const joinList = (items) => {
  if (items.length <= 1) return items.join("");
  if (items.length === 2) return items.join(" and ");
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
};

export const midseasonReportCardsPrompt = ({ year, teamNames, filename }) =>
  [
    `Follow the SHOW DIRECTIVE, GRADING FORMAT, TONE rules, and MANDATORY SHOW OPENING at the top of \`${filename}\` exactly. Host a midseason report card episode of "${SHOW_NAME}" as ${HOSTS}, grading ${joinList(teamNames)} at the midway point of the ${year} season.`,
    "",
    numbered([
      "Execute the mandatory show opening word for word.",
      "Follow the run-of-show order in the document: one full report card segment per team, then How to Improve Your Grade.",
      "In every team's segment, Arlis and Ty must each state their own letter grade (A+ through F) out loud, with real reasoning. They don't have to agree, and a split grade is good radio.",
      "Ground each grade in the document's evidence: the record, the pace against the preseason Vegas number, signature wins and bad losses, the team stats, and the conference standing. Arlis grades on the eye test and the storyline, and Ty grades on the scoreboard and the pace.",
      "Treat a team coming off a bye as having fewer games on the board, and don't penalize it for that.",
      "Talk about the preseason number in plain studio language, like \"on pace\" or \"ahead of schedule,\" and never say \"probability,\" \"model,\" or \"algorithm.\"",
      "Talk about this as a real college football season with national stakes, the way a studio show would at the halfway point.",
      "In How to Improve Your Grade, go team by team through the remaining schedule and say what each team has to do to move its grade up.",
      "Sign off after the last team's outlook.",
    ]),
  ].join("\n");

export const winTotalsPrompt = ({ teamNames }) => {
  const count = { 2: "two", 3: "three", 4: "four", 5: "five", 6: "six" }[teamNames.length] || teamNames.length;
  return [
    `Follow the SHOW DIRECTIVE, DEBATE FORMAT, HOT SEAT FORMAT, and MANDATORY SHOW OPENING in the source file. Host an energetic ESPN-style sports debate episode of '${SHOW_NAME}' with ${HOSTS}.`,
    "",
    `For each of the ${count} teams (${joinList(teamNames)}), Arlis and Ty MUST follow these rules:`,
    numbered([
      "Read the full schedule aloud game-by-game in order.",
      "For games tagged LIKELY WIN or LIKELY LOSS, give a quick line and move on.",
      "For games tagged COIN FLIP, stop and debate: Arlis and Ty MUST take opposite sides—one arguing it's a win, the other arguing it's a loss—using specific players and ratings. Alternate who takes which side from debate to debate.",
      "At the end of each team's schedule, state their Over/Under call on the Vegas line, then conduct the MANDATORY Hot Seat Check on the head coach using the Hot Seat Thermometer.",
      "Never use video game or simulation terminology—frame everything as real college football.",
    ]),
    "",
    'Close the show with the brief "Around the Sun Belt" win totals and the Sun Belt Conference Championship prediction.',
  ].join("\n");
};
