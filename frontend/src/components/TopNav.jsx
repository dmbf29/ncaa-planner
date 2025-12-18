import { Link, useLocation } from "react-router-dom";
import { useEffect, useState } from "react";
import { clsx } from "clsx";

function TopNav() {
  const location = useLocation();
   // Track auth based on presence of JWT in localStorage
  const [authed, setAuthed] = useState(() => Boolean(localStorage.getItem("jwt")));

  useEffect(() => {
    const syncAuth = () => setAuthed(Boolean(localStorage.getItem("jwt")));
    window.addEventListener("storage", syncAuth);
    return () => window.removeEventListener("storage", syncAuth);
  }, []);

  return (
    <header className="border-b border-border bg-charcoal text-white dark:border-darkborder">
      <div className="mx-auto flex items-center justify-between px-4 py-3">
        <Link to="/" className="font-varsity text-xl tracking-[0.08em] uppercase">
          NCAA Planner
        </Link>
        <nav className="flex items-center gap-3 text-sm">
          <Link
            to="/"
            className={clsx(
              "rounded-md px-3 py-2 transition",
              location.pathname === "/" ? "bg-burnt text-charcoal font-semibold" : "text-white/80 hover:bg-white/10",
            )}
          >
            Home
          </Link>
          {authed ? (
            <Link
              to="/teams"
              className={clsx(
                "rounded-md px-3 py-2 transition",
                location.pathname.startsWith("/teams")
                  ? "bg-burnt text-charcoal font-semibold"
                  : "text-white/80 hover:bg-white/10",
              )}
            >
              Teams
            </Link>
          ) : (
            <>
              <Link
                to="/auth/login"
                className={clsx(
                  "rounded-md px-3 py-2 transition",
                  location.pathname === "/auth/login"
                    ? "bg-white text-charcoal font-semibold"
                    : "text-white/80 hover:bg-white/10",
                )}
              >
                Log In
              </Link>
              <Link
                to="/auth/signup"
                className={clsx(
                  "rounded-md border border-white/40 px-3 py-2 transition",
                  location.pathname === "/auth/signup"
                    ? "bg-white text-charcoal font-semibold"
                    : "text-white hover:bg-white/10",
                )}
              >
                Sign Up
              </Link>
            </>
          )}
        </nav>
      </div>
    </header>
  );
}

export default TopNav;
