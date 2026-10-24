#!/usr/bin/env python3
"""Watch the PS Remote Play window and save a screenshot of every new screen.

You navigate the game with your controller; this notices when the screen has
changed and then held still, OCRs it, and saves it unless it's a repeat of one
already saved this session (moving the cursor on the same page doesn't count).

    python3 tools/capture/watch.py --name week-9-ulm-jmu

Output: pod/captures/<name>/NNN_<header>.png plus manifest.json (timestamp,
header text, and the full OCR text of each capture, for routing/classifying later).

Needs, for the app that runs it (Terminal): Screen Recording (to capture) and
Accessibility (to find the window; without it the whole screen is used).
Keep Remote Play frontmost -- the capture is the screen region, not the window.
Ctrl+C to stop.
"""
import argparse
import difflib
import json
import re
import queue
import subprocess
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

REPO_ROOT = Path(__file__).resolve().parents[2]
TINK = "/System/Library/Sounds/Tink.aiff"


def window_bounds():
    script = ('tell application "System Events" to tell process "RemotePlay" '
              'to get {position, size} of window 1')
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    nums = [int(float(n)) for n in re.findall(r"-?\d+(?:\.\d+)?", r.stdout)]
    return tuple(nums) if r.returncode == 0 and len(nums) == 4 else None


def grab(bounds):
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        cmd = ["screencapture", "-x"]
        if bounds:
            x, y, w, h = bounds
            cmd += ["-R", "%d,%d,%d,%d" % (x, y, w, h)]
        subprocess.run(cmd + [f.name], check=True)
        return Image.open(f.name).convert("RGB").copy()


def signature(img):
    """Small grayscale of the middle of the frame (ignores title bar and the
    hover-only controller bar at the bottom)."""
    w, h = img.size
    mid = img.crop((0, int(h * 0.12), w, int(h * 0.90)))
    return np.asarray(mid.convert("L").resize((128, 72)), dtype=np.float32)


def delta(a, b):
    return float(np.abs(a - b).mean())


def ocr(img, psm=6):
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        img.save(f.name)
        r = subprocess.run(["tesseract", f.name, "stdout", "--psm", str(psm)],
                           capture_output=True, text=True, timeout=45)
    return r.stdout


CATEGORIES = [  # column-header words that identify a Player Stats table
    ("defense", [r"\bSOLO\b", r"\bTAK\b"]),
    ("defense", [r"\bFFUMB\b", r"\bFMBREC\b"]),   # same table scrolled right
    ("rushing", [r"\bCAR\b", r"\b(BTK|BIK|FUMB)\b"]),
    ("receiving", [r"\bREC\b", r"\b(YAC|RAC|DROPS)\b"]),
    ("passing", [r"\bCOMP\b", r"\bATT\b"]),
    ("kicking", [r"\bFGM\b", r"\bXPM\b"]),
    ("punting", [r"\bPUNT"]),
]


def team_scores(raw, teams):
    """Similarity (0-1) of one OCR reading to each team name."""
    flat = lambda t: re.sub(r"[^a-z]", "", t.lower())
    return {t: difflib.SequenceMatcher(None, flat(raw), flat(t)).ratio() for t in teams}


def read_team(pill, teams):
    """Name of the team in the Team Stats pill, one of `teams` (or None). OCR is shaky on
    small, bold text (it reads SMU as 'MU', UL MONROE as 'JL MONROE'), so read the pill a
    few ways and take the closest of the game's two teams instead of trusting any one read."""
    readings = []
    for scale in (3, 4):
        g = pill.resize((pill.width * scale, pill.height * scale), Image.LANCZOS)
        for im, psm in ((g, 7), (g, 8), (g.point(lambda p: 0 if p < 140 else 255), 8)):
            readings.append(re.sub(r"[^A-Za-z ]", "", ocr(im, psm)).strip())
    best, best_score, runner_up = None, 0.0, 0.0
    for team in teams:
        score = max((team_scores(r, [team])[team] for r in readings if r), default=0.0)
        if score > best_score:
            best, best_score, runner_up = team, score, best_score
        elif score > runner_up:
            runner_up = score
    return best if best_score >= 0.6 and best_score - runner_up >= 0.2 else None


def header_slug(img, text, teams=()):
    """Label a screen. Returns (file-name slug, header text, meta) where meta is
    {kind: box_score|team_stats|other, team: one of --teams or None, category}."""
    w, h = img.size
    title, header = "screen", ""
    # below the menu bar and window title bar, above the table
    band = img.crop((0, int(h * 0.09), int(w * 0.65), int(h * 0.19)))
    for line in ocr(band).splitlines():
        if len(re.findall(r"[A-Za-z]", line)) >= 3:
            header = line.strip()
            title = re.sub(r"[^A-Za-z0-9]+", "-", line).strip("-")[:30].lower() or "screen"
            break
    # "in", not startswith: OCR sometimes reads the school logo beside the title as a stray letter ("y-box-score")
    kind = "box_score" if "box-score" in title else "team_stats" if "team-stats" in title else "other"
    meta = {"kind": kind, "team": None, "category": None}
    parts = [title]
    if kind == "team_stats":
        # Inside the light team pill only.
        pill = img.crop((int(w * 0.08), int(h * 0.222), int(w * 0.24), int(h * 0.256))).convert("L")
        if teams:
            meta["team"] = read_team(pill, teams)
            if meta["team"]:
                parts.append(re.sub(r"[^a-z0-9]+", "-", meta["team"].lower()).strip("-"))
        else:
            raw = re.sub(r"[^A-Z ]", "", ocr(pill.resize((pill.width * 3, pill.height * 3), Image.LANCZOS), psm=7).upper()).strip()
            if raw:
                parts.append(re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-"))
        up = text.upper()
        literal = re.search(r"\b(RUSHING|RECEIVING|PASSING|DEFENSE|KICKING|PUNTING)\b", up)
        if literal:
            meta["category"] = literal.group(1).lower()
        else:
            for name, words in CATEGORIES:
                if sum(bool(re.search(wd, up)) for wd in words) >= 2:
                    meta["category"] = name
                    break
        if meta["category"]:
            parts.append(meta["category"])
    return "-".join(parts), header, meta


# --- Defense tables are wider than the window: the right-hand columns (FFUMB,
# FMBREC, ...) only show after scrolling right, which hides the NAME column.
# These helpers tell the two views apart, work out which page of rows a view
# shows, and graft the name column onto the right-hand view.
# Geometry is as fractions of the Remote Play window image (measured at 3024x1888).
NAME_COLUMN_X = (113 / 3024, 508 / 3024)
TABLE_X_END = 2200 / 3024
TABLE_Y = (520 / 1888, 1590 / 1888)


def defense_side(text):
    """'left' (SOLO...DEFL columns), 'right' (FFUMB...TD columns) or None."""
    up = text.upper()
    if re.search(r"\b(FFUMB|FMBREC|FMBYDS|SFTY)\b", up) and not re.search(r"\bSOLO\b", up):
        return "right"
    if re.search(r"\bSOLO\b", up):
        return "left"
    return None


def vertical_thumb(img):
    """(top, length) of the table's vertical scrollbar thumb as fractions of window
    height, or None if there's no scrollbar. The top says which rows are showing;
    length/11 is the thumb's travel per row (11 rows are visible at a time)."""
    a = np.asarray(img.convert("L"), dtype=np.int16)
    h, w = a.shape
    y0 = int(h * 0.18)
    band = a[y0:int(h * 0.90), int(w * 0.7310):int(w * 0.7345)].mean(axis=1) > 150
    best, start = None, None
    for i, v in enumerate(list(band) + [False]):
        if v and start is None:
            start = i
        elif not v and start is not None:
            if i - start > h * 0.05 and (best is None or i - start > best[1] - best[0]):
                best = (start, i)
            start = None
    return (round((y0 + best[0]) / h, 4), round((best[1] - best[0]) / h, 4)) if best else None


ROWS_VISIBLE = 11
MAX_SHIFT_ROWS = 8      # beyond this the two views share too few rows to be worth grafting
ROW_PITCH = 0.04669     # row height / window height
HEADER_HEIGHT = 0.0471  # column-header row height / window height


def row_shift(left_entry, right_entry):
    """How many rows lower the right view is scrolled than the left view (negative = higher)."""
    step = (left_entry["vlen"] + right_entry["vlen"]) / 2 / ROWS_VISIBLE
    return int(round((right_entry["vtop"] - left_entry["vtop"]) / step))


def graft_names(left_img, right_img, shift=0):
    """Name column from the left view + table of the right view = one readable image.
    If the right view is scrolled `shift` rows lower (or higher, negative) than the
    left, only the rows both views show are kept, so every name sits next to its own stats."""
    w, h = left_img.size
    y0, y1 = int(h * TABLE_Y[0]), int(h * TABLE_Y[1])
    nx0, nx1 = int(w * NAME_COLUMN_X[0]), int(w * NAME_COLUMN_X[1])
    tx1 = int(w * TABLE_X_END)
    head_end = y0 + int(h * HEADER_HEIGHT)
    cut = int(round(abs(shift) * h * ROW_PITCH))
    # right lower than left: its first rows are the left's later rows
    left_body = (head_end + cut, y1) if shift >= 0 else (head_end, y1 - cut)
    right_body = (head_end, y1 - cut) if shift >= 0 else (head_end + cut, y1)

    def column(img, x0, x1, body):
        header, rows = img.crop((x0, y0, x1, head_end)), img.crop((x0, body[0], x1, body[1]))
        out = Image.new("RGB", (x1 - x0, header.height + rows.height))
        out.paste(header, (0, 0))
        out.paste(rows, (0, header.height))
        return out

    names, table = column(left_img, nx0, nx1, left_body), column(right_img, nx0, tx1, right_body)
    out = Image.new("RGB", (names.width + table.width, names.height))
    out.paste(names, (0, 0))
    out.paste(table, (names.width, 0))
    return out


def fingerprint(text):
    return re.sub(r"[^a-z0-9]+", " ", text.lower()).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--name", default=datetime.now().strftime("%Y%m%d-%H%M%S"))
    p.add_argument("--out", default=str(REPO_ROOT / "pod" / "captures"))
    p.add_argument("--interval", type=float, default=0.3, help="seconds between looks")
    p.add_argument("--settle", type=float, default=0.6, help="seconds the screen must hold still")
    p.add_argument("--motion", type=float, default=2.0, help="frame-to-frame change that counts as moving")
    p.add_argument("--min-change", type=float, default=0.3, help="ignore settled screens this close to the last one handled (near-identical frames only; real repeats are caught by text comparison)")
    p.add_argument("--dup", type=float, default=0.92, help="text similarity above which a screen is a repeat")
    p.add_argument("--teams", default="", help='the game\'s teams, comma-separated, to fix misread names (e.g. "UL Monroe,James Madison")')
    p.add_argument("--debug", action="store_true", help="print change values every tick (for tuning)")
    args = p.parse_args()

    out = Path(args.out) / args.name
    out.mkdir(parents=True, exist_ok=True)
    manifest, seen = [], []
    teams = [t.strip() for t in args.teams.split(",") if t.strip()]
    jobs = queue.Queue()

    defense_views = []   # saved Defense screens that scroll sideways, for pairing
    composite_of = {}    # view file name -> the grafted composite it's currently part of

    counter = [0]

    def save(img, slug, header, meta, text):
        counter[0] += 1
        name = "%03d_%s.png" % (counter[0], slug)
        img.save(out / name)
        entry = dict(meta, file=name, header=header, at=datetime.now().isoformat(timespec="seconds"), ocr=text)
        manifest.append(entry)
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
        return entry

    def pair_and_graft(entry):
        """Match this view with the other side of the same page (same team, closest
        scroll position) and save the grafted composite. The two needn't be scrolled
        identically: if the list drifted between captures, only the shared rows are used.
        A view already paired only partially is re-paired if this one lines up better,
        which lets you fix a drifted page by re-capturing the other side at the right spot."""
        candidates = []
        for v in defense_views:
            if v["team"] != entry["team"] or v["hscroll"] == entry["hscroll"]:
                continue
            left, right = (entry, v) if entry["hscroll"] == "left" else (v, entry)
            shift = row_shift(left, right)
            if abs(shift) > MAX_SHIFT_ROWS:
                continue
            current = composite_of.get(v["file"])
            if current and abs(shift) >= abs(current["shift_rows"]):
                continue            # already paired at least this well
            candidates.append((abs(shift), v, left, right, shift))
        defense_views.append(entry)
        if not candidates:
            other = "right" if entry["hscroll"] == "left" else "left"
            print("  wait   %s %s view saved -- needs its %s view (scroll sideways without moving up or down)"
                  % (entry["team"], entry["hscroll"], other))
            return
        _, mate, left, right, shift = min(candidates, key=lambda c: c[0])

        old = composite_of.get(mate["file"])
        if old:                     # replace the worse composite; its other view is free again
            manifest.remove(old)
            (out / old["file"]).unlink(missing_ok=True)
            for f in old["grafted_from"]:
                composite_of.pop(f, None)
            print("  redo   replacing %s (list had drifted %d rows)" % (old["file"], abs(old["shift_rows"])))

        composite = graft_names(Image.open(out / left["file"]), Image.open(out / right["file"]), shift)
        team_slug = re.sub(r"[^a-z0-9]+", "-", (entry["team"] or "").lower()).strip("-")
        overlap = ROWS_VISIBLE - abs(shift)
        grafted = save(composite, "team-stats-%s-defense-extra" % team_slug,
                       "defense right-hand columns + names",
                       {"kind": "team_stats", "team": entry["team"], "category": "defense_extra", "hscroll": "grafted",
                        "vtop": min(left["vtop"], right["vtop"]), "shift_rows": shift, "overlap_rows": overlap,
                        "grafted_from": [left["file"], right["file"]]}, "")
        composite_of[entry["file"]] = composite_of[mate["file"]] = grafted
        if shift:
            note = "  [list drifted %d rows: only %d of %d rows matched -- re-capture the other side at the same spot to fix]" % (abs(shift), overlap, ROWS_VISIBLE)
            subprocess.Popen(["afplay", "/System/Library/Sounds/Funk.aiff"])
        else:
            note = ""
        print("  paired %s + %s -> %s%s" % (left["file"], right["file"], grafted["file"], note))

    def worker():
        """OCR + dedupe + save, off the watching loop so no screen is missed."""
        while True:
            img = jobs.get()
            if img is None:
                return
            try:
                text = ocr(img)
                slug, header, meta = header_slug(img, text, teams)
                meta.update(hscroll=None, vtop=None, vlen=None)
                key = None
                if meta["category"] == "defense":
                    thumb = vertical_thumb(img)
                    meta["hscroll"] = defense_side(text)
                    if thumb:
                        meta["vtop"], meta["vlen"] = thumb
                    if meta["hscroll"] and thumb:
                        # Only compare against screens at the same scroll position: the right-hand
                        # pages are nearly all zeros, so by text alone one page looks like another.
                        key = (meta["team"], meta["hscroll"], round(meta["vtop"] / 0.08))
                        slug += "-" + meta["hscroll"]
                fp = fingerprint(text)
                sig = signature(img)
                best = max((difflib.SequenceMatcher(None, fp, f).ratio() for f, k, _ in seen if k == key), default=0.0)
                identical = any(k == key and delta(sig, g) < 1.0 for _, k, g in seen)   # same picture, whatever OCR says
                if best >= args.dup or identical:
                    print("  skip   %-40s repeat of a saved screen (%s)" % (slug, "identical picture" if identical else "%.2f similar" % best))
                    continue
                seen.append((fp, key, sig))
                entry = save(img, slug, header, meta, text)
                print("  saved  %s   (%.2f similar to nearest)" % (entry["file"], best))
                if key is not None:
                    pair_and_graft(entry)
            except Exception as e:  # keep watching no matter what
                print("  error  %s" % e)
                subprocess.Popen(["afplay", "/System/Library/Sounds/Basso.aiff"])
            finally:
                jobs.task_done()

    t = threading.Thread(target=worker, daemon=True)
    t.start()

    bounds = window_bounds()
    print("Window: %s" % (str(bounds) if bounds else "not found (no Accessibility?) -- using the whole screen"))
    print("Saving to %s\nNavigate with your controller. Ctrl+C to stop.\n" % out)

    last = last_handled = None
    queued_sigs = []   # pictures already queued this session, so a repeat doesn't beep
    stable_since, handled, moving_since, warned, tick = None, False, None, False, 0
    try:
        while True:
            tick += 1
            if tick % 30 == 0:
                bounds = window_bounds() or bounds
            img = grab(bounds)
            sig = signature(img)
            d = delta(sig, last) if last is not None else 999.0
            last = sig
            if args.debug:
                print("tick %4d  change %.2f" % (tick, d))

            if d > args.motion:
                stable_since, handled = None, False
                moving_since = moving_since or time.time()
                if time.time() - moving_since > 6 and not warned:
                    warned = True
                    print("  note   screen has been changing for 6s+ (change %.1f); if it's really still, rerun with --motion %.0f" % (d, d * 2))
            else:
                moving_since, warned = None, False
                stable_since = stable_since or time.time()
                if not handled and time.time() - stable_since >= args.settle:
                    handled = True
                    if last_handled is not None and delta(sig, last_handled) < args.min_change:
                        print("  same   (settled, but identical to the last screen)")
                    elif any(delta(sig, earlier) < 1.0 for earlier in queued_sigs):
                        print("  same   (a screen you already captured -- no beep)")
                    else:
                        last_handled = sig
                        queued_sigs.append(sig)
                        jobs.put(img)
                        subprocess.Popen(["afplay", TINK])  # new picture queued -- safe to move on; labeling happens in the background
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nfinishing %d queued screen(s)..." % jobs.unfinished_tasks)
        jobs.join()
        print("%d screens saved to %s" % (len(manifest), out))


if __name__ == "__main__":
    main()
