import Card from "./Card";
import ExistingScreenshotsGallery from "./ExistingScreenshotsGallery";
import { TEAM_STAT_GROUPS, FIELD_LABELS, CATEGORY_FIELDS, PLAYER_FIELD_LABELS } from "../lib/gameStatFields";

function ScoreHeader({ game, collegeStats }) {
  const findEntry = (name) => collegeStats?.find((row) => row.team === name);
  const awayScore = findEntry(game.awayCollege.name)?.fields?.finalScore;
  const homeScore = findEntry(game.homeCollege.name)?.fields?.finalScore;

  if (awayScore == null || homeScore == null) return null;

  return (
    <Card>
      <div className="flex items-center justify-center gap-6 p-6">
        <div className="text-center">
          <p className="text-sm text-textSecondary">{game.awayCollege.name}</p>
          <p className="font-varsity text-4xl text-textPrimary dark:text-white">{awayScore}</p>
        </div>
        <span className="text-xl text-textSecondary">&ndash;</span>
        <div className="text-center">
          <p className="text-sm text-textSecondary">{game.homeCollege.name}</p>
          <p className="font-varsity text-4xl text-textPrimary dark:text-white">{homeScore}</p>
        </div>
      </div>
    </Card>
  );
}

function NarrativeCard({ narrative }) {
  if (!narrative?.narrativeSummary) return null;

  return (
    <Card>
      <div className="p-5 space-y-2">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Game Recap</h3>
        <p className="text-sm text-textPrimary dark:text-white">{narrative.narrativeSummary}</p>
        {(narrative.offensePlayerStatLine || narrative.defensePlayerStatLine) && (
          <div className="grid gap-2 pt-2 text-xs text-textSecondary sm:grid-cols-2">
            {narrative.offensePlayerStatLine && (
              <p>
                <span className="font-semibold">Offense POTG:</span> {narrative.offensePlayerStatLine}
              </p>
            )}
            {narrative.defensePlayerStatLine && (
              <p>
                <span className="font-semibold">Defense POTG:</span> {narrative.defensePlayerStatLine}
              </p>
            )}
          </div>
        )}
      </div>
    </Card>
  );
}

function TeamStatsTable({ collegeStats, awayCollege, homeCollege }) {
  const findEntry = (name) => collegeStats?.find((row) => row.team === name);
  const away = findEntry(awayCollege.name);
  const home = findEntry(homeCollege.name);
  const fields = TEAM_STAT_GROUPS.flatMap((group) => group.fields).filter(
    (field) => away?.fields?.[field] != null || home?.fields?.[field] != null,
  );

  if (fields.length === 0) return null;

  return (
    <Card className="overflow-hidden">
      <div className="border-b border-border bg-charcoal px-4 py-3 text-white dark:border-darkborder">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em]">Team Stats</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-textSecondary dark:border-darkborder">
              <th className="px-4 py-2 font-semibold" />
              <th className="px-2 py-2 font-semibold text-right">{awayCollege.name}</th>
              <th className="px-4 py-2 font-semibold text-right">{homeCollege.name}</th>
            </tr>
          </thead>
          <tbody>
            {fields.map((field) => (
              <tr key={field} className="border-b border-border/60 last:border-0 dark:border-darkborder/60">
                <td className="px-4 py-1.5 text-textSecondary">{FIELD_LABELS[field]}</td>
                <td className="px-2 py-1.5 text-right">{away?.fields?.[field] ?? "—"}</td>
                <td className="px-4 py-1.5 text-right">{home?.fields?.[field] ?? "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function PlayerStatRow({ row }) {
  const fields = (CATEGORY_FIELDS[row.category] || []).filter((field) => row.fields?.[field] != null);

  return (
    <div className="rounded-md border border-border p-3 dark:border-darkborder">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-semibold text-textPrimary dark:text-white">{row.displayName}</span>
        <span className="rounded-full bg-charcoal/5 px-2 py-1 text-xs uppercase dark:bg-white/10">{row.team}</span>
        <span className="rounded-full bg-burnt/10 px-2 py-1 text-xs uppercase text-burnt">{row.category}</span>
      </div>
      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-textSecondary">
        {fields.map((field) => (
          <span key={field}>
            {PLAYER_FIELD_LABELS[field]}:{" "}
            <span className="font-semibold text-textPrimary dark:text-white">{row.fields[field]}</span>
          </span>
        ))}
      </div>
    </div>
  );
}

function PlayerStatsCard({ playerStats }) {
  if (!playerStats || playerStats.length === 0) return null;

  return (
    <Card>
      <div className="p-5 space-y-3">
        <h3 className="font-varsity text-lg uppercase tracking-[0.06em] text-charcoal dark:text-white">Player Stats</h3>
        <div className="space-y-2">
          {playerStats.map((row, index) => (
            <PlayerStatRow key={index} row={row} />
          ))}
        </div>
      </div>
    </Card>
  );
}

function GameSummary({ game }) {
  const analysis = game.existingAnalysis;

  if (!analysis) {
    return (
      <Card>
        <div className="p-5">
          <p className="text-sm text-textSecondary">
            This game hasn&rsquo;t been played yet — check back after it&rsquo;s recorded.
          </p>
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-6">
      <ScoreHeader game={game} collegeStats={analysis.collegeStats} />
      <ExistingScreenshotsGallery screenshots={game.statScreenshots} />
      <NarrativeCard narrative={analysis.narrative} />
      <TeamStatsTable collegeStats={analysis.collegeStats} awayCollege={game.awayCollege} homeCollege={game.homeCollege} />
      <PlayerStatsCard playerStats={analysis.playerStats} />
    </div>
  );
}

export default GameSummary;
