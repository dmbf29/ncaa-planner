#!/usr/bin/env python3
"""Scout a recorded Twitch stream of a Dynasty game: what plays does this coach call? (local only, no AI API)

    backend/tools/roster_video/venv/bin/python tools/scouting/scout.py streams/etothebman/2026-10-31_20-44-37.ts

Writes <stream>.scout.json and <stream>.scout.md next to the recording. How it works:

1. ffmpeg pulls one 1280x720 frame per second.
2. A fast Apple Vision pass over the "SELECT A PLAY" strip finds the play-call screens; consecutive frames form a
   *window* (one window per snap, roughly).
3. An accurate pass reads the scoreboard (quarter, clock, down & distance, score) and the three play cards
   (formation, play, PASS/RUN/MAN/ZONE, "N CALLS | X AVG YDS", "AVAILABLE IN N PLAYS").
4. Calls are attributed to windows two ways: "Available in 2 plays" means that play was called on the previous
   window (1 play = two windows ago), and a card's call count going up between sightings means it was called in
   between. Only plays whose card was on screen can be caught, so the report says how many windows it attributed.
"""
import collections
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import warnings

warnings.filterwarnings("ignore")

from PIL import Image  # noqa: E402

MENU_CROP = (0, 340, 1280, 610)
LABEL_CROP = (100, 340, 900, 395)
BOARD_CROP = (250, 612, 1030, 685)
WINDOW_GAP = 6  # seconds without a play-call screen that ends a window
CARD_X = (50, 460, 870)
OFFENSE_FORMATION = re.compile(r"^(GUN|PISTOL|UNDER CENTER|SINGLEBACK|I FORM|I-FORM|EMPTY|GOAL LINE|WILDCAT|SHOTGUN|FULL HOUSE|SPLIT BACK|TRIPS|BUNCH|SPECIAL TEAMS)", re.I)
# low-resolution streams (480p) turn "SELECT A PLAY" into "SeLECIAt", so "sel...c" counts too
SCREEN_WORDS = re.compile(r"play|concept|formation|coach sugg|personnel|sel[a-z]*c", re.I)


def ocr(img, level):
    from ocrmac import ocrmac
    return ocrmac.OCR(img, recognition_level=level).recognize()


def extract_frames(path, out_dir):
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vf", "fps=1,scale=1280:720:flags=lanczos", "-q:v", "3", os.path.join(out_dir, "%05d.jpg")],
        check=True, stderr=subprocess.DEVNULL,
    )
    return sorted(int(f[:-4]) for f in os.listdir(out_dir) if f.endswith(".jpg"))


def find_play_call_frames(frames_dir, seconds):
    hits = []
    for t in seconds:
        im = Image.open(os.path.join(frames_dir, f"{t:05d}.jpg"))
        text = " ".join(x[0] for x in ocr(im.crop(LABEL_CROP), "fast"))
        if SCREEN_WORDS.search(text):
            hits.append(t)
    return hits


def read_frame(img):
    """Accurate OCR of the menu strip and scoreboard: [{r, t, x, y, h}] with x = left edge, y = centre, in 1280x720 px."""
    items = []
    for region, (x0, y0, x1, y1) in (("menu", MENU_CROP), ("board", BOARD_CROP)):
        crop = img.crop((x0, y0, x1, y1)).resize(((x1 - x0) * 2, (y1 - y0) * 2))
        for text, _conf, (x, y, w, h) in ocr(crop, "accurate"):
            items.append({"r": region, "t": text, "x": x0 + x * (x1 - x0), "y": y0 + (1 - y - h / 2) * (y1 - y0), "h": h * (y1 - y0)})
    return items


def parse_board(items):
    b = [i for i in items if i["r"] == "board"]
    txt = " ".join(i["t"] for i in sorted(b, key=lambda i: (round(i["y"] / 8), i["x"])))
    s = {}
    m = re.search(r"(1st|2nd|3rd|4th)\s*&\s*(\d+|Goal|Inches)", txt, re.I)
    if m:
        s["down"] = int(m.group(1)[0])
        s["dist"] = m.group(2).lower()
    q = [i["t"] for i in b if re.fullmatch(r"(1st|2nd|3rd|4th)\s*\|?", i["t"].strip(), re.I) and i["x"] < 600]
    if q:
        s["qtr"] = int(q[0][0])
    clock = [i["t"] for i in b if re.fullmatch(r"\d{1,2}:\d\d", i["t"])]
    if clock:
        s["clock"] = clock[0]
    scores = sorted((i for i in b if re.fullmatch(r"\d{1,2}", i["t"]) and i["h"] > 14), key=lambda i: i["x"])
    left = [i for i in scores if i["x"] < 580]
    right = [i for i in scores if i["x"] > 700]
    if left:
        s["left_score"] = int(left[-1]["t"])
    if right:
        s["right_score"] = int(right[0]["t"])
    # a ranked team prints as "22 GA SOUTHERN"; the rank is dropped
    def team(lo, hi):
        found = [re.sub(r"^\d{1,2}\s+", "", i["t"].strip()) for i in b if lo < i["x"] < hi]
        return next((n for n in found if re.fullmatch(r"[A-Z][A-Z .&']{3,}", n) and not re.search(r"SPORTS|SOUTHER[NM]?$|GEORG|SUN BELT|^SEC|^ACC", n) or n.startswith("GA ")), None)
    left_name = [team(350, 480)]
    right_name = [team(740, 900)]
    left_name, right_name = [n for n in left_name if n], [n for n in right_name if n]
    if left_name:
        s["left_team"] = left_name[0]
    if right_name:
        s["right_team"] = right_name[0]
    return s


def read_scoreboards(frames_dir, seconds, step=2):
    """{second: board} for every `step`th frame; the scoreboard is on screen in play and on the play-call screens."""
    x0, y0, x1, y1 = BOARD_CROP
    boards = {}
    for t in seconds[::step]:
        crop = Image.open(os.path.join(frames_dir, f"{t:05d}.jpg")).crop(BOARD_CROP).resize(((x1 - x0) * 2, (y1 - y0) * 2))
        items = [{"r": "board", "t": text, "x": x0 + x * (x1 - x0), "y": y0 + (1 - y - h / 2) * (y1 - y0), "h": h * (y1 - y0)}
                 for text, _conf, (x, y, w, h) in ocr(crop, "accurate")]
        boards[t] = parse_board(items)
    return boards


def side_changes(boards, key, confirm=2):
    """[(second, old, new)] for one side's score. A reading counts once enough consecutive readings agree and the jump
    is a real scoring play: 3 (field goal, 3 readings), 6-8 (touchdown, 2), 1 or 2 within 90s of a touchdown (extra point
    / conversion, 2) or a bare 2 (safety, 8 readings). That drops single misreads (63, 88) and a stray 1 or 2. If a jump
    isn't one of those but the new score holds for 8 readings (a missed play in between), it is accepted and split into
    touchdowns and field goals (`approx`). A missing reading is skipped; the game starts 0-0 (Vision skips a lone 0)."""
    cur, changes, last_td = 0, [], None
    run, run_start = [], None
    for t in sorted(boards):
        v = boards[t].get(key)
        if v is None:
            continue
        if run and v == run[-1]:
            run.append(v)
        else:
            run, run_start = [v], t
        delta, n = v - cur, len(run)
        after_td = last_td is not None and run_start - last_td < 90
        ok = (delta == 3 and n >= 3) or (delta in (6, 7, 8) and n >= confirm) or (delta in (1, 2) and after_td and n >= confirm) or (delta == 2 and n >= 8)
        if not ok and delta > 0 and n >= 8:
            changes.append((run_start, cur, v, True))
            cur = v
            continue
        if ok:
            changes.append((run_start, cur, v, False))
            last_td = run_start if delta >= 6 else last_td
            cur = v
    return changes


def scoring_plays(boards, teams):
    left = side_changes(boards, "left_score")
    right = side_changes(boards, "right_score")
    raw = sorted([(t, 0, a, b, ap) for t, a, b, ap in left] + [(t, 1, a, b, ap) for t, a, b, ap in right])
    # fill quarter/clock from the boards (quarter carried forward, clock read at the change)
    qtr_at, q = {}, 1
    for t in sorted(boards):
        q = boards[t].get("qtr") or q
        qtr_at[t] = q
    plays = []
    for t, side, a, b, approx in raw:
        pts = b - a
        if approx:  # a jump we couldn't see play by play: split it into touchdowns (7) and field goals (3)
            n7 = next(n for n in range(pts // 7, -1, -1) if (pts - 7 * n) % 3 == 0) if any((pts - 7 * n) % 3 == 0 for n in range(pts // 7 + 1)) else pts // 7
            kinds = ["Touchdown"] * n7 + ["Field goal"] * ((pts - 7 * n7) // 3) + (["Score"] if (pts - 7 * n7) % 3 else [])
            for kind in kinds:
                p = 7 if kind == "Touchdown" else 3 if kind == "Field goal" else pts - 7 * n7 - 3 * kinds.count("Field goal")
                plays.append({"time": t, "quarter": qtr_at.get(t, 1), "clock": None, "side": side, "team": teams[side] if len(teams) == 2 else None,
                              "kind": kind, "points": p, "approx": True, "extra": "extra point" if kind == "Touchdown" else None})
            continue
        near = min((x for x in boards if x >= t and boards[x].get("clock")), default=None, key=lambda x: x - t)
        clock = boards[near]["clock"] if near is not None and near - t < 30 else None
        last = plays[-1] if plays else None
        if pts in (1, 2) and last and last["side"] == side and last["points"] == 6 and t - last["time"] < 90 and "extra" not in last:
            last["extra"] = "extra point" if pts == 1 else "2-point conversion"
            last["points"] += pts
            continue
        kind = {3: "Field goal", 2: "Safety"}.get(pts) or ("Touchdown" if pts >= 6 else "Score")
        plays.append({"time": t, "quarter": qtr_at.get(t, 1), "clock": clock, "side": side, "team": teams[side] if len(teams) == 2 else None,
                      "kind": kind, "points": pts})
    for p in plays:
        if p["kind"] == "Touchdown" and "extra" not in p:
            p["extra"] = "no extra point" if p["points"] == 6 else None
        if p["kind"] == "Touchdown" and p["points"] == 8:
            p["extra"] = "2-point conversion"
        if p["kind"] == "Touchdown" and p["points"] == 7:
            p["extra"] = "extra point"
    return plays


def norm(s):
    return re.sub(r"[^A-Z0-9 ]", "", (s or "").upper().replace("W/K", "WK")).strip()


def to_float(s):
    try:
        return float(re.sub(r"[^\d.\-]", "", s.replace("=", "-")).strip("."))
    except (ValueError, AttributeError):
        return None


def parse_cards(items):
    menu = [i for i in items if i["r"] == "menu"]
    cards = []
    for x0 in CARD_X:
        col = [i for i in menu if x0 <= i["x"] < x0 + 390 and 400 < i["y"] < 600]
        names = sorted((i for i in col if 400 < i["y"] < 430), key=lambda i: i["y"])
        if len(names) < 2:
            continue
        card = {"formation": names[0]["t"], "play": names[1]["t"], "type": None}
        for i in col:
            if i["y"] > 575 and re.fullmatch(r"PASS|RUN|KICK|MAN|ZONE|PUNT|BLITZ", i["t"]):
                card["type"] = i["t"]
            m = re.search(r"(\d+)\s*CALLS?\s*\|\s*([-=]?\s*[\d.]+)", i["t"])
            if m:
                card["calls"], card["avg"] = int(m.group(1)), to_float(m.group(2))
            m = re.search(r"AVAILABLE IN (\d)", i["t"], re.I)
            if m:
                card["available_in"] = int(m.group(1))
        cards.append(card)
    return cards


def parse_list_rows(items):
    """Formation / Play Type / Concept list: rows like 'Gun   49 GOTO%   7.3 AVG YDS' -> {name: (goto_pct, avg_yds)}."""
    menu = [i for i in items if i["r"] == "menu" and i["x"] < 430 and 400 < i["y"] < 610]
    rows = {}
    for name in (i for i in menu if i["x"] < 200 and re.search(r"[A-Za-z]{3}", i["t"])):
        nums = sorted((i for i in menu if abs(i["y"] - name["y"]) < 16 and i["x"] > 250 and re.fullmatch(r"-?\d+(\.\d+)?", i["t"])), key=lambda i: i["x"])
        if len(nums) >= 2:
            rows[name["t"]] = (float(nums[0]["t"]), float(nums[1]["t"]))
    return rows


def classify(card):
    if card["type"] in ("PASS", "RUN", "KICK", "PUNT"):
        return "offense"
    if card["type"] in ("MAN", "ZONE", "BLITZ"):
        return "defense"
    return "offense" if OFFENSE_FORMATION.match(card["formation"]) else "defense"


class Canon:
    def __init__(self):
        self.keys = []

    def __call__(self, card):
        k = norm(card["formation"]) + "|" + norm(card["play"])
        m = difflib.get_close_matches(k, self.keys, n=1, cutoff=0.88)
        if m:
            return m[0]
        self.keys.append(k)
        return k


def build_windows(hits):
    windows, cur = [], []
    for t in hits:
        if cur and t - cur[-1] > WINDOW_GAP:
            windows.append(cur)
            cur = []
        cur.append(t)
    if cur:
        windows.append(cur)
    return windows


def analyze(path, keep_frames=None):
    tmp = keep_frames or tempfile.mkdtemp(prefix="scout_")
    os.makedirs(tmp, exist_ok=True)
    try:
        seconds = extract_frames(path, tmp)
        hits = find_play_call_frames(tmp, seconds)
        parsed = {}
        for t in hits:
            items = read_frame(Image.open(os.path.join(tmp, f"{t:05d}.jpg")))
            parsed[t] = {"board": parse_board(items), "cards": parse_cards(items), "rows": parse_list_rows(items)}
        boards = read_scoreboards(tmp, seconds)
    finally:
        if not keep_frames:
            shutil.rmtree(tmp, ignore_errors=True)
    report = build_report(path, len(seconds), build_windows(hits), parsed)
    teams = [collections.Counter(b[k] for b in boards.values() if k in b).most_common(1)[0][0] for k in ("left_team", "right_team") if any(k in b for b in boards.values())]
    if len(teams) == 2 and teams[0] == teams[1]:  # e.g. Bulls vs Bulls: the broadcast prints the same name for both
        teams = [f"{teams[0]} (left)", f"{teams[1]} (right)"]
    if len(teams) == 2:
        report["teams"] = teams
    report["scoring"] = scoring_plays(boards, teams)
    totals = [0, 0]
    for p in report["scoring"]:
        totals[p["side"]] += p["points"]
        p["score"] = list(totals)
    return report


def window_situation(window, parsed):
    """Scoreboard state from the window's last readable frame (closest to the snap)."""
    sit = {}
    for t in window:
        for k, v in parsed[t]["board"].items():
            sit[k] = v
    return sit


def build_report(path, duration, windows, parsed):
    canon = Canon()
    info = {}
    series = collections.defaultdict(list)  # key -> [(window index, calls)]
    for wi, win in enumerate(windows):
        for t in win:
            for c in parsed[t]["cards"]:
                if len(norm(c["play"])) < 4:
                    continue
                k = canon(c)
                info.setdefault(k, {"formation": c["formation"], "play": c["play"], "type": c["type"], "side": classify(c)})
                if c["type"]:
                    info[k]["type"] = c["type"]
                if c.get("calls") is not None:
                    series[k].append((wi, c["calls"], c.get("avg"), t))

    situations = [window_situation(w, parsed) for w in windows]
    attributed = {}  # (window, key) -> source

    def credit(wi, k, source):
        if 0 <= wi < len(windows) and not any(kk[0] == wi for kk in attributed):
            attributed[(wi, k)] = source

    # "Available in 2 plays" = called on the previous window, "in 1 play" = two windows ago.
    for wi, win in enumerate(windows):
        seen = {}
        for t in win:
            for c in parsed[t]["cards"]:
                if c.get("available_in") and len(norm(c["play"])) >= 4:
                    seen[canon(c)] = c["available_in"]
        for k, n in seen.items():
            credit(wi - (3 - n), k, "available")
    # A call count that went up between two sightings: the play was called on a window between them.
    for k, s in series.items():
        counts = collections.Counter(x[1] for x in s)
        good = [x for x in s if counts[x[1]] >= 2]
        for a, b in zip(good, good[1:]):
            if 0 < b[1] - a[1] <= 2 and b[0] > a[0]:
                credit(b[0] - 1 if b[0] - a[0] > 1 else a[0], k, "count")

    log = []
    for (wi, k), source in sorted(attributed.items()):
        sit = situations[wi]
        log.append({"time": windows[wi][0], "window": wi, "source": source, **info[k], "key": k,
                    "qtr": sit.get("qtr"), "clock": sit.get("clock"), "down": sit.get("down"), "dist": sit.get("dist")})

    plays = []
    for k, s in series.items():
        counts = collections.Counter(x[1] for x in s)
        good = [x for x in s if counts[x[1]] >= 2] or s
        last = good[-1]
        this_game = sum(1 for e in log if e["key"] == k)
        plays.append({**info[k], "season_calls": last[1], "avg_yds": last[2], "called_this_game": this_game})
    plays.sort(key=lambda p: (-p["season_calls"], p["play"]))

    # Formation / play-type lists the coach scrolled through: keep the last sighting of each row.
    rows = {}
    for t in sorted(parsed):
        rows.update(parsed[t]["rows"])
    lists = {name: {"goto_pct": v[0], "avg_yds": v[1]} for name, v in rows.items()}

    boards = [s for s in situations if "left_team" in s]
    teams = [collections.Counter(s[side] for s in boards if side in s).most_common(1)[0][0] for side in ("left_team", "right_team") if any(side in s for s in boards)]
    final = next(({"left": s["left_score"], "right": s["right_score"]} for s in reversed(situations) if "left_score" in s and "right_score" in s), None)

    return {
        "file": path, "duration_s": duration, "teams": teams, "last_score": final,
        "play_call_windows": len(windows), "attributed_windows": len({w for w, _ in attributed}),
        "plays": plays, "call_log": log, "lists": lists,
        "tendencies": tendencies(log),
    }


def tendencies(log):
    out = {"offense": {}, "defense": {}}
    off = [e for e in log if e["side"] == "offense" and e["type"] in ("PASS", "RUN")]
    by_down = collections.defaultdict(collections.Counter)
    for e in off:
        by_down[e["down"] or 0][e["type"]] += 1
    long_dist = collections.Counter(e["type"] for e in off if e["down"] in (2, 3) and str(e["dist"]).isdigit() and int(e["dist"]) >= 7)
    short = collections.Counter(e["type"] for e in off if e["down"] in (2, 3, 4) and str(e["dist"]).isdigit() and int(e["dist"]) <= 3)
    out["offense"] = {"by_down": {str(d): dict(c) for d, c in sorted(by_down.items())}, "long_yardage": dict(long_dist), "short_yardage": dict(short),
                      "total": dict(collections.Counter(e["type"] for e in off))}
    de = [e for e in log if e["side"] == "defense"]
    out["defense"] = {"total": dict(collections.Counter(e["type"] for e in de))}
    return out


def markdown(r):
    teams = " vs ".join(r["teams"]) or "?"
    lines = [f"# Game tape: {teams}", "", f"`{os.path.basename(r['file'])}` - {r['duration_s'] // 60} min, "
             f"{r['play_call_windows']} play-call screens, {r['attributed_windows']} with an identified call.", ""]
    for side, title in (("offense", "Offense"), ("defense", "Defense")):
        ps = [p for p in r["plays"] if p["side"] == side and p["season_calls"] > 0]
        if not ps:
            continue
        lines += [f"## {title}: go-to calls", "", "| Play | Formation | Type | Calls (cumulative) | Avg yds | Called this game |", "|---|---|---|---|---|---|"]
        for p in ps[:12]:
            lines.append(f"| {p['play']} | {p['formation']} | {p['type'] or ''} | {p['season_calls']} | {p['avg_yds']} | {p['called_this_game']} |")
        lines.append("")
    if r.get("scoring"):
        lines += ["## Scoring summary", ""]
        for q in sorted({p["quarter"] for p in r["scoring"]}):
            lines += [f"Quarter {q}:" if q <= 4 else f"Overtime {q - 4}:", ""]
            for p in (p for p in r["scoring"] if p["quarter"] == q):
                note = f" ({p['extra']})" if p.get("extra") else ""
                lines.append(f"* {p['clock'] or '?'} {p['team'] or ('Left' if p['side'] == 0 else 'Right')} {p['kind']}{note}  [{p['score'][0]}-{p['score'][1]}]")
            lines.append("")
    t = r["tendencies"]["offense"]
    if t.get("total"):
        lines += ["## Run/pass by situation (identified calls only)", "", f"- Overall: {t['total']}"]
        for d, c in t["by_down"].items():
            lines.append(f"- Down {d if d != '0' else '?'}: {c}")
        lines += [f"- 2nd/3rd & 7+: {t['long_yardage']}", f"- 2nd-4th & 3 or less: {t['short_yardage']}", ""]
    if r["lists"]:
        lines += ["## Formation / play-type usage (GOTO% | avg yds)", ""]
        lines += [f"- {n}: {v['goto_pct']:g}% | {v['avg_yds']}" for n, v in r["lists"].items()]
        lines.append("")
    lines += ["## Call log", "", "| Time | Q | Clock | Down & dist | Play | Type | How |", "|---|---|---|---|---|---|---|"]
    for e in r["call_log"]:
        lines.append(f"| {e['time'] // 60}:{e['time'] % 60:02d} | {e['qtr'] or ''} | {e['clock'] or ''} | {e['down'] or ''} & {e['dist'] or ''} | "
                     f"{e['formation']} / {e['play']} | {e['type'] or ''} | {e['source']} |")
    return "\n".join(lines) + "\n"


def scout_file(path, force=False):
    base = os.path.splitext(path)[0]
    if os.path.exists(base + ".scout.json") and not force:
        return base + ".scout.json"
    report = analyze(path)
    with open(base + ".scout.json", "w") as f:
        json.dump(report, f, indent=2)
    with open(base + ".scout.md", "w") as f:
        f.write(markdown(report))
    return base + ".scout.json"


if __name__ == "__main__":
    print(scout_file(sys.argv[1], force="--force" in sys.argv))
