import { forwardRef } from "react";

const Card = forwardRef(function Card({ children, className = "", ...rest }, ref) {
  return (
    <div
      ref={ref}
      className={`rounded-xl border border-border bg-surface shadow-card dark:border-darkborder dark:bg-darksurface ${className}`}
      {...rest}
    >
      {children}
    </div>
  );
});

export default Card;
