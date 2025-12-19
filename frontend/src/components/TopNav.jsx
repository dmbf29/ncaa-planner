import { Link, useLocation, useNavigate } from "react-router-dom";
import { useEffect, useState } from "react";
import { clsx } from "clsx";
import avatarImg from "../assets/avatar.png";
import { logout } from "../lib/apiClient";

function TopNav() {
  const location = useLocation();
  const navigate = useNavigate();
   // Track auth based on presence of JWT in localStorage
  const [authed, setAuthed] = useState(() => Boolean(localStorage.getItem("jwt")));
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const syncAuth = () => setAuthed(Boolean(localStorage.getItem("jwt")));
    window.addEventListener("storage", syncAuth);
    return () => window.removeEventListener("storage", syncAuth);
  }, []);

  const handleLogout = async () => {
    try {
      await logout();
    } finally {
      setMenuOpen(false);
      navigate("/auth/login");
    }
  };

  return (
    <header className="border-b border-border bg-charcoal text-white dark:border-darkborder">
      <div className="mx-auto flex items-center justify-between px-4 py-3">
        <Link to="/" className="font-varsity text-xl tracking-[0.08em] uppercase">
          NCAA Planner
        </Link>
        <nav className="flex items-center gap-3 text-sm">
          {authed ? (
            <>
              <Link
                to="/teams"
                className={clsx(
                  "rounded-md px-3 py-2 transition",
                  location.pathname.startsWith("/teams")
                    ? ""
                    : "text-white/80 hover:bg-white/10",
                )}
              >
                Teams
              </Link>
              <div className="relative">
                <button
                  onClick={() => setMenuOpen((v) => !v)}
                  className="flex items-center gap-2 rounded-full border border-border bg-white/10 text-white hover:bg-white/20"
                >
                  <img src={avatarImg} alt="User avatar" className="h-8 w-8 rounded-full object-cover" />
                </button>
                {menuOpen && (
                  <div className="absolute right-0 mt-2 w-40 rounded-lg border border-border bg-surface text-charcoal shadow-card dark:border-darkborder dark:bg-darksurface dark:text-white">
                    <button
                      onClick={handleLogout}
                      className="w-full px-4 py-2 text-left text-sm hover:bg-border/50 dark:hover:bg-white/10"
                    >
                      Sign out
                    </button>
                  </div>
                )}
              </div>
            </>
          ) : (
            <>
              <Link
                to="/auth/login"
                className={clsx(
                  "rounded-md px-3 py-2 transition",
                  location.pathname === "/auth/login"
                    ? ""
                    : "text-white/80 hover:bg-white/10",
                )}
              >
                Log In
              </Link>
              <Link
                to="/auth/signup"
                className={clsx(
                  "rounded-md bg-burnt 0 px-3 py-2 transition",
                  location.pathname === "/auth/signup"
                    ? "bg-burnt text-white font-semibold"
                    : "text-white hover:bg-white/10 font-semibold",
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
