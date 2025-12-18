function Card({ children, className = "", ...rest }) {
  return (
    <div
      className={`rounded-xl border border-border bg-surface shadow-card dark:border-darkborder dark:bg-darksurface ${className}`}
      {...rest}
    >
      {children}
    </div>
  );
}

export default Card;
