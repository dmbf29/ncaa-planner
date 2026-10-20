// NotebookLM prompts that pair with each exported Markdown source. Only the
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

export const weeklyReviewPrompt = ({ year, weekNumbers, filename }) => {
  const label = weekNumbers.length === 1 ? `Week ${weekNumbers[0]}` : `Weeks ${joinList(weekNumbers)}`;
  const earlier = weekNumbers.length === 1 ? "earlier weeks" : "weeks outside this recap";
  return [
    `Follow the SHOW DIRECTIVE and MANDATORY SHOW OPENING at the top of \`${filename}\` exactly. Host an episode of "${SHOW_NAME}" as ${HOSTS}, recapping ${label} of the ${year} season.`,
    "",
    numbered([
      "Execute the mandatory show opening word for word.",
      "Follow the run-of-show order in the document, segment by segment.",
      "When a segment lists a Defining Storyline, make it the centerpiece of that segment: tell how the game unfolded, build up to its biggest turning points, and give your own take on them.",
      `Cover only ${label} results as the main story. Use ${earlier} and preseason sources only for quick historical callouts and team trends.`,
      "Talk about this as a real college football season with national stakes, the way a studio show would on a Monday after the games.",
      "Close with the Next Episode tease from the document as the last thing the hosts say, then sign off.",
    ]),
  ].join("\n");
};

export const bigGameBreakdownPrompt = ({ weekNumber }) =>
  [
    `Follow the SHOW BRIEF at the top of the source document exactly. Host an episode of "Big Game Breakdown" covering Week ${weekNumber}.`,
    "",
    numbered([
      "Execute the mandatory show opening word for word.",
      "Follow the brief's order exactly: the card, the scoreboard (if the brief lists one), then every game in the listed sequence, using the 4-beat format (Stakes, Film Room, Quarterback Duel, The Pick).",
      "At the end of each game, both hosts must say their exact bet out loud before moving on to the next game.",
      "Build the runtime and intensity toward the finale, the last of the games with picks.",
      "After the finale, give the quick Also on the Board heads-up if the brief lists one: name each game, say when and where it's on, and mention the line casually. No picks, no predictions and no analysis, about ten seconds a game.",
      "Follow all betting-language rules and forbidden terms in the document.",
      "Close with the Next Episode tease, with no recap of the picks.",
    ]),
  ].join("\n");

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
