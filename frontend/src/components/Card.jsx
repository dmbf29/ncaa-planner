function Card({ children }) {
  return (
    <div className="rounded-xl border border-border bg-surface shadow-card dark:border-darkborder dark:bg-darksurface">
      {children}
    </div>
  );
}

export default Card;
