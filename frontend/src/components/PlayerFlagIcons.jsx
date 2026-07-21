function PlayerFlagIcons({ flags, className = "" }) {
  if (!flags?.length) return null;

  return (
    <span className={`inline-flex items-center gap-1 ${className}`}>
      {flags.map((flag) => (
        <i key={flag.id} className={`${flag.icon} text-xs`} style={{ color: flag.color }} title={flag.name}></i>
      ))}
    </span>
  );
}

export default PlayerFlagIcons;
