import AddToSquadModal from "./AddToSquadModal";
import { weekLabel } from "./LeagueGameRow";

function importNote(recruit) {
  const parts = [`Signed by ${recruit.collegeName}`];
  if (recruit.transfer) parts.push("portal transfer");
  if (recruit.classYear) parts.push(recruit.classYear);
  if (recruit.state) parts.push(recruit.state);
  if (recruit.nationalRank) parts.push(`#${recruit.nationalRank} national`);
  parts.push(weekLabel(recruit.week));
  return parts.join(" · ");
}

function ImportRecruitModal({ recruit, onClose, onImported }) {
  return (
    <AddToSquadModal
      position={recruit.position}
      name={recruit.name}
      title="Import Recruit"
      doneTitle="Recruit Imported"
      actionLabel="Import"
      summary={
        <>
          <p className="mt-1 text-sm text-textSecondary">
            {recruit.starRating ? `${recruit.starRating}★ ` : ""}
            {recruit.position} · {recruit.name}
            {recruit.transfer ? " · portal transfer" : ""}
          </p>
          <p className="text-xs text-textSecondary">
            Signed by {recruit.collegeName} · {weekLabel(recruit.week)}
          </p>
        </>
      }
      doneMessage={({ name, teamName, boardName }) => (
        <>
          Added <span className="font-semibold">{name}</span> to {teamName}
          {boardName ? ` › ${boardName}` : ""} as a recruit.
        </>
      )}
      buildPayload={() => ({
        name: recruit.name,
        starRating: recruit.starRating || null,
        nilAmount: recruit.nilAmount ?? null,
        classYear: recruit.classYear || null,
        status: "recruit",
        recruitStatus: "normal",
        notes: importNote(recruit),
      })}
      onClose={onClose}
      onAdded={() => onImported?.(recruit)}
    />
  );
}

export default ImportRecruitModal;
