import { Link, matchPath, useLocation, useNavigate } from "react-router-dom";
import { useEffect, useState } from "react";
import { clsx } from "clsx";
import avatarImg from "../assets/avatar.png";
import { logout, fetchDynasties, fetchDynastyPortal } from "../lib/apiClient";

function navLinkClass(active) {
  return clsx("rounded-md px-3 py-2 transition", active ? "bg-white/10" : "text-white/80 hover:bg-white/10");
}

function TopNav() {
  const location = useLocation();
  const navigate = useNavigate();
  // Track auth based on presence of JWT in localStorage
  const [authed, setAuthed] = useState(() => Boolean(localStorage.getItem("jwt")));
  const [menuOpen, setMenuOpen] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [myDynastyIds, setMyDynastyIds] = useState([]);
  const [portal, setPortal] = useState(null);

  useEffect(() => {
    const syncAuth = () => setAuthed(Boolean(localStorage.getItem("jwt")));
    window.addEventListener("storage", syncAuth);
    return () => window.removeEventListener("storage", syncAuth);
  }, []);

  // Login/logout happen in this tab, where "storage" doesn't fire; re-check on navigation.
  useEffect(() => {
    setAuthed(Boolean(localStorage.getItem("jwt")));
    setMenuOpen(false);
    setMoreOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!authed) {
      setMyDynastyIds([]);
      return;
    }
    let cancelled = false;
    fetchDynasties()
      .then((dynasties) => !cancelled && setMyDynastyIds(dynasties.map((d) => String(d.id))))
      .catch(() => !cancelled && setMyDynastyIds([]));
    return () => {
      cancelled = true;
    };
  }, [authed]);

  // /dynasty/updates, /dynasty/export and /dynasty/games/:id carry no dynasty id,
  // so they fall back to the signed-in user's own dynasty.
  const routeDynastyId = matchPath("/dynasty/:dynastyId/*", location.pathname)?.params.dynastyId;
  const routeSeasonId = matchPath("/dynasty/:dynastyId/seasons/:seasonId/*", location.pathname)?.params.seasonId;
  const dynastyId = /^\d+$/.test(routeDynastyId || "")
    ? routeDynastyId
    : location.pathname.startsWith("/dynasty")
      ? myDynastyIds[0]
      : undefined;

  useEffect(() => {
    if (!dynastyId) {
      setPortal(null);
      return;
    }
    let cancelled = false;
    fetchDynastyPortal(dynastyId)
      .then((data) => !cancelled && setPortal(data))
      .catch(() => !cancelled && setPortal(null));
    return () => {
      cancelled = true;
    };
  }, [dynastyId]);

  const inDynasty = Boolean(dynastyId && portal && String(portal.id) === String(dynastyId));
  const isOwner = inDynasty && myDynastyIds.includes(String(dynastyId));
  const latestSeasonId = [...(portal?.seasons || [])].sort((a, b) => b.year - a.year)[0]?.id;
  const seasonId = routeSeasonId || latestSeasonId;
  const dynastyPath = `/dynasty/${dynastyId}`;
  const seasonPath = seasonId ? `${dynastyPath}/seasons/${seasonId}` : null;

  const dynastyLinks = inDynasty
    ? [
      { label: "Watch", to: `${dynastyPath}/watch` },
      { label: "Rivals", to: `${dynastyPath}/rivals` },
        seasonPath && { label: "Team Ratings", to: `${seasonPath}/team-ratings` },
        seasonPath && { label: "All Players", to: `${seasonPath}/players` },
        seasonPath && { label: "Recruits", to: `${seasonPath}/recruits` },
        isOwner && { label: "Dynasty Updates", to: "/dynasty/updates" },
        isOwner && { label: "Export", to: "/dynasty/export" },
      ].filter(Boolean)
    : [];

  // Phone tab bar: the main pages get a tab, the rest live behind "More".
  const tabs = inDynasty
    ? [
        { label: "Home", icon: "fa-house", to: seasonPath ?? dynastyPath, match: (p) => p === dynastyPath || p === seasonPath },
        { label: "Watch", icon: "fa-circle-play", to: `${dynastyPath}/watch` },
        seasonPath && { label: "Ratings", icon: "fa-ranking-star", to: `${seasonPath}/team-ratings` },
        seasonPath && { label: "Players", icon: "fa-users", to: `${seasonPath}/players` },
        seasonPath && { label: "Recruits", icon: "fa-user-plus", to: `${seasonPath}/recruits` },
      ].filter(Boolean)
    : [];
  const moreLinks = inDynasty
    ? [
        { label: "Rivals", icon: "fa-fire", to: `${dynastyPath}/rivals` },
        isOwner && { label: "Dynasty Updates", icon: "fa-pen-to-square", to: "/dynasty/updates" },
        isOwner && { label: "Export", icon: "fa-file-export", to: "/dynasty/export" },
      ].filter(Boolean)
    : [];
  // A lone extra link (everyone but the owner) gets its own tab rather than a "More" menu for one item.
  const tabItems = moreLinks.length === 1 ? [...tabs, ...moreLinks] : tabs;
  const showMore = moreLinks.length > 1;
  const tabClass = (active) =>
    clsx("flex flex-1 flex-col items-center gap-0.5 py-2 text-[10px] font-semibold", active ? "text-burnt" : "text-textSecondary");

  const handleLogout = async () => {
    try {
      await logout();
    } finally {
      setMenuOpen(false);
      setAuthed(false);
      navigate("/auth/login");
    }
  };

  return (
    <header className="border-b border-border bg-charcoal text-white dark:border-darkborder">
      <div className="mx-auto flex items-center justify-between gap-3 px-4 py-3">
        <Link
          to={inDynasty ? dynastyPath : "/"}
          className="truncate font-varsity text-xl tracking-[0.08em] uppercase"
        >
          {inDynasty ? portal.name : "NCAA Planner"}
        </Link>
        <nav className="flex items-center gap-2 text-sm sm:gap-3">
          {dynastyLinks.map((link) => (
            <Link
              key={link.to}
              to={link.to}
              className={clsx("hidden md:block", navLinkClass(location.pathname === link.to))}
            >
              {link.label}
            </Link>
          ))}
          {authed ? (
            <div className="relative">
              <button
                onClick={() => {
                  setMenuOpen((v) => !v);
                }}
                className="flex items-center gap-2 rounded-full border border-border bg-white/10 text-white hover:bg-white/20"
              >
                <img src={avatarImg} alt="User avatar" className="h-8 w-8 rounded-full object-cover" />
              </button>
              {menuOpen && (
                <div className="absolute right-0 z-50 mt-2 w-40 rounded-lg border border-border bg-surface text-charcoal shadow-card dark:border-darkborder dark:bg-darksurface dark:text-white">
                  <Link to="/teams" className="block px-4 py-2 text-sm hover:bg-border/50 dark:hover:bg-white/10">
                    Teams
                  </Link>
                  <Link to="/dynasty" className="block px-4 py-2 text-sm hover:bg-border/50 dark:hover:bg-white/10">
                    Dynasty
                  </Link>
                  <button
                    onClick={handleLogout}
                    className="w-full px-4 py-2 text-left text-sm hover:bg-border/50 dark:hover:bg-white/10"
                  >
                    Sign out
                  </button>
                </div>
              )}
            </div>
          ) : (
            <>
              <Link
                to="/auth/login"
                className={clsx(
                  "whitespace-nowrap rounded-md px-3 py-2 transition",
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
                  "hidden whitespace-nowrap rounded-md bg-burnt px-3 py-2 transition sm:block",
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
      {inDynasty && (
        <>
          {showMore && moreOpen && (
            <div className="fixed inset-0 z-40 md:hidden" onClick={() => setMoreOpen(false)}>
              <div className="absolute bottom-[calc(3.5rem+env(safe-area-inset-bottom))] right-2 w-48 rounded-lg border border-border bg-surface text-charcoal shadow-card dark:border-darkborder dark:bg-darksurface dark:text-white">
                {moreLinks.map((link) => (
                  <Link key={link.to} to={link.to} className="flex items-center gap-3 px-4 py-3 text-sm hover:bg-border/50 dark:hover:bg-white/10">
                    <i className={clsx("fa-solid w-4 text-center", link.icon)} />
                    {link.label}
                  </Link>
                ))}
              </div>
            </div>
          )}
          <nav
            aria-label="Dynasty"
            className="fixed inset-x-0 bottom-0 z-50 flex border-t border-border bg-surface pb-[env(safe-area-inset-bottom)] dark:border-darkborder dark:bg-darksurface md:hidden"
          >
            {tabItems.map((tab) => {
              const active = tab.match ? tab.match(location.pathname) : location.pathname === tab.to;
              return (
                <Link key={tab.to} to={tab.to} className={tabClass(active)} aria-current={active ? "page" : undefined}>
                  <i className={clsx("fa-solid text-lg", tab.icon)} />
                  {tab.label}
                </Link>
              );
            })}
            {showMore && (
              <button type="button" onClick={() => setMoreOpen((v) => !v)} aria-expanded={moreOpen} className={tabClass(moreOpen || moreLinks.some((l) => l.to === location.pathname))}>
                <i className="fa-solid fa-ellipsis text-lg" />
                More
              </button>
            )}
          </nav>
        </>
      )}
    </header>
  );
}

export default TopNav;
