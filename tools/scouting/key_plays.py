"""Finds fumbles, sacks and possession changes in a stream recording from the scoreboard bar, with a cheap 1 fps read of
just the bar. Writes <recording>.keyplays.json next to the recording:

  plays: [{time, kind, side, ...}]  the bar's centre slot flashes a label for a couple of seconds when something happens
                         (a red "FUMBLE"), and a sack shows in the player ticker beside it; time = first second it is on
                         screen, side = "L"/"R" scoreboard side that had the ball.
  possession_changes: [{time, to, down, kickoff, break, ...}]  the small ball-spot marker above the clock box sits on the side of the team
                         with the ball, so it jumps from one side to the other when possession changes. `down` is the last
                         down read in the 20 s before (4 = punt / field goal / turnover on downs), `kickoff` says a KICKOFF
                         label was up in the 45 s before and `break` that a halftime or end-of-quarter label was up around it.
                         `to` is the side that has the ball afterwards. A turnover is a change on down 1-3 with neither; the
                         caller also drops changes next to scoring plays.

Fumbles and turnover candidates also carry quarter, clock, left_score and right_score, read from the bar just before the
event (the bar is also readable in play, unlike most of the screen).

    backend/tools/roster_video/venv/bin/python tools/scouting/key_plays.py streams/etothebman/2026-11-08_22-01-30.ts
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings

warnings.filterwarnings("ignore")

from PIL import Image  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scout  # noqa: E402  (its scoreboard reader parses quarter, clock and score)

BOARD_CROP = (250, 612, 1030, 685)  # same strip tools/scouting/scout.py reads, at 1280x720
EVENT_GAP = 8  # seconds without the label that ends an event
# the ball-spot marker (an arrow and a yard line) inside the strip: left of the clock box when the left team has the ball
MARKER_LEFT = (317, 7, 343, 21)
MARKER_RIGHT = (435, 7, 463, 21)
MARKER_INK = 165  # grey level below which a pixel counts as marker ink on the light clock box
MARKER_MIN = 25  # ink pixels needed for a marker to count as present
MIN_RUN = 15  # readings a side must hold to count: possessions last longer, replays and menus flicker
MAX_GAP = 6  # seconds the bar may be unreadable between two possessions (a menu hides it for longer)
DOWN = re.compile(r"^\s*([1I]\w?t|18t|2\w?d|3\w?d|4\w?h)\s*&", re.I)
KINDS = (
    ("Fumble", re.compile(r"F[U0]MB[L1I]E", re.I)),
    ("Interception", re.compile(r"INTERCEPT|\bINT\b", re.I)),
    ("Turnover", re.compile(r"TURNOVER|TURNED OVER", re.I)),
    ("Sack", re.compile(r"\bSACK\b", re.I)),
)


def ocr(img):
    from ocrmac import ocrmac
    return ocrmac.OCR(img, recognition_level="fast").recognize()


def extract_frames(path, out_dir):
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vf", "fps=1,scale=1280:720,crop=%d:%d:%d:%d" % (
            BOARD_CROP[2] - BOARD_CROP[0], BOARD_CROP[3] - BOARD_CROP[1], BOARD_CROP[0], BOARD_CROP[1]), "-q:v", "3", os.path.join(out_dir, "%05d.jpg")],
        check=True,
    )
    return sorted(f for f in os.listdir(out_dir) if f.endswith(".jpg"))


def read_bar(img):
    """(kinds, down, kickoff, break) for one frame of the bar."""
    items = [item[0] for item in ocr(img.resize((img.width * 2, img.height * 2)))]
    text = " ".join(items)
    down = next((read_down(i) for i in items if DOWN.match(i)), None)
    return ([kind for kind, pattern in KINDS if pattern.search(text)], down, bool(re.search(r"KICK\s?OFF|XICKOFF", text, re.I)),
            bool(re.search(r"HALF\s?T[1I]M|END OF", text, re.I)))


def read_down(text):
    first = DOWN.match(text).group(1).lower()
    return 1 if first[0] in "1i" else int(first[0])


def marker_side(img):
    """"L", "R" or None for which side of the clock box carries the ball-spot marker."""
    gray = img.convert("L")
    left, right = (sum(1 for p in gray.crop(box).getdata() if p < MARKER_INK) for box in (MARKER_LEFT, MARKER_RIGHT))
    if left >= MARKER_MIN and left > right + 10:
        return "L"
    if right >= MARKER_MIN and right > left + 10:
        return "R"
    return None


def scan(path):
    events, last = [], {}
    sides, downs, kickoffs, breaks = {}, {}, [], []
    with tempfile.TemporaryDirectory() as tmp:
        for f in extract_frames(path, tmp):
            t = int(f[:5]) - 1
            img = Image.open(os.path.join(tmp, f))
            kinds, down, kickoff, interval = read_bar(img)
            sides[t] = marker_side(img)
            if down:
                downs[t] = down
            if kickoff:
                kickoffs.append(t)
            if interval:
                breaks.append(t)
            for kind in kinds:
                if kind in last and t - last[kind] <= EVENT_GAP:
                    last[kind] = t
                    continue
                last[kind] = t
                events.append({"time": t, "kind": kind})
    changes = possession_changes(sides, downs, kickoffs, breaks)
    for event in events:
        event["side"] = side_at(sides, event["time"])
    for target in [e for e in events if e["kind"] == "Fumble"] + [c for c in changes if is_candidate(c)]:
        target.update(read_situation(path, target["time"]))
    return events, changes


def is_candidate(change):
    return change["down"] in (1, 2, 3) and not change["kickoff"] and not change["break"]


def side_at(sides, t):
    """The marker side at second t, or the nearest earlier reading within 10 s."""
    return next((sides[s] for s in range(t, t - 10, -1) if sides.get(s)), None)


def read_situation(path, t):
    """{quarter, clock, left_score, right_score} from the bar a few seconds before t, or {} when it can't be read."""
    for back in (2, 4, 1, 6, 8):
        second = max(t - back, 0)
        with tempfile.TemporaryDirectory() as tmp:
            frame = os.path.join(tmp, "f.jpg")
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-ss", str(second), "-i", path, "-frames:v", "1", "-vf", "scale=1280:720", "-q:v", "2", frame], check=True)
            if not os.path.exists(frame):
                continue
            board = scout.parse_board(scout.read_frame(Image.open(frame)))
        if board.get("qtr") and board.get("clock"):
            return {"quarter": board["qtr"], "clock": board["clock"], "left_score": board.get("left_score"), "right_score": board.get("right_score")}
    return {}


def possession_changes(sides, downs, kickoffs, breaks):
    """The marker's side, held for MIN_RUN seconds, changing from one stable run to the next."""
    runs = []
    for t in sorted(sides):
        if sides[t] is None:
            continue
        if runs and runs[-1]["side"] == sides[t] and t - runs[-1]["last"] <= 3:
            runs[-1]["last"] = t
            runs[-1]["count"] += 1
        else:
            runs.append({"side": sides[t], "first": t, "last": t, "count": 1})
    stable = [r for r in runs if r["count"] >= MIN_RUN]
    changes = []
    for before, after in zip(stable, stable[1:]):
        if before["side"] == after["side"] or after["first"] - before["last"] > MAX_GAP:
            continue
        t = after["first"]
        recent = [downs[s] for s in range(t - 20, t) if s in downs]
        changes.append({"time": t, "to": after["side"], "down": recent[-1] if recent else None, "kickoff": any(t - 45 <= k <= t for k in kickoffs),
                        "break": any(t - 60 <= b <= t + 10 for b in breaks)})
    return changes


if __name__ == "__main__":
    recording = sys.argv[1]
    plays, changes = scan(recording)
    out = re.sub(r"\.ts$", "", recording) + ".keyplays.json"
    with open(out, "w") as fh:
        json.dump({"file": os.path.abspath(recording), "plays": plays, "possession_changes": changes}, fh, indent=1)
    print(f"{len(plays)} key plays, {len(changes)} possession changes -> {out}")
    for play in plays:
        print(f"  {play['time']:>5}s {play['kind']}")
    for change in changes:
        if is_candidate(change):
            print(f"  {change['time']:>5}s possession change after down {change['down']} (Q{change.get('quarter')} {change.get('clock')}, ball to {change['to']})")
