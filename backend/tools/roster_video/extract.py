#!/usr/bin/env python3
"""Turn a screen recording of the NCAA roster screen into the roster JSON the importer expects.

Record the roster page and hold the stick down so every player is highlighted in turn.
The right-hand pane shows the full first name; the highlighted row carries the stats.
Everything is OCR'd locally (Apple Vision via ocrmac) -- no AI API calls.

    python extract.py team.mov > team.json
"""
import json
import multiprocessing
import os
import re
import sys
from collections import Counter

import cv2
import numpy as np
from ocrmac import ocrmac
from PIL import Image

HEADERS = {"NAME", "YEAR", "POS", "OVR", "NIL", "DEV", "SPD", "ACC", "AGI", "COD", "STR", "AWR",
           "CAR", "BCV", "BTK", "CTH", "SPC", "CIT", "SRR", "MRR", "DRR", "JKM", "TRK", "PBK", "RBK"}
STAT_FIELDS = {"SPD": "speed", "ACC": "acceleration", "AGI": "agility",
               "COD": "change_of_direction", "STR": "strength", "AWR": "awareness"}
HOMOGLYPHS = str.maketrans("АВСЕНІКМОРТХаеорсху", "ABCEHIKMOPTXaeopcxy")
VALID_POSITIONS = {"QB", "HB", "FB", "WR", "TE", "LT", "LG", "C", "RG", "RT", "LEDG", "REDG", "DT",
                   "MIKE", "WILL", "SAM", "CB", "FS", "SS", "K", "P"}
STABLE_FRAMES = 4


def snap_position(pos):
    pos = pos.upper()
    if pos in VALID_POSITIONS:
        return pos
    for fixed in (pos.replace("O", "Q"), pos.replace("0", "Q"), pos.replace("0", "O"), pos.replace("I", "L")):
        if fixed in VALID_POSITIONS:
            return fixed
    return pos


def ocr(bgr):
    img = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
    return ocrmac.OCR(img, recognition_level="accurate").recognize()


def clean(text):
    return text.translate(HOMOGLYPHS).strip()


def find_headers(frame):
    """x-centre of each column header, read from the first frame that shows the table header."""
    h, w = frame.shape[:2]
    y0, y1 = int(h * 0.27), int(h * 0.37)
    res = ocr(frame[y0:y1, : int(w * 0.76)])
    cols = {}
    for text, _, (x, _y, bw, _h) in res:
        words = re.findall(r"[A-Z]{3,4}", clean(text).upper())
        t = words[-1] if words else ""
        if t in HEADERS:
            cols[t] = (x + bw / 2) * int(w * 0.76)
    return cols


def highlighted_band(frame):
    h, w = frame.shape[:2]
    top = int(h * 0.30)
    gray = cv2.cvtColor(frame[top:, int(w * 0.08): int(w * 0.72)], cv2.COLOR_BGR2GRAY)
    bright = np.where(gray.mean(axis=1) > 170)[0]
    if len(bright) < 20:
        return None
    return top + bright[0], top + bright[-1]


def agreed(reads):
    """True once two non-empty OCR reads of the same cell are identical."""
    counts = Counter(r for r in reads if r)
    return bool(counts) and counts.most_common(1)[0][1] >= 2


def read_row(strip, cols):
    tw = strip.shape[1]
    tokens = sorted(((clean(t), (x + bw / 2) * tw, x * tw) for t, _, (x, _y, bw, _h) in ocr(strip)),
                    key=lambda t: t[1])
    if not tokens:
        return None
    year_x = cols.get("YEAR", tw * 0.2)
    name = " ".join(t for t, cx, _ in tokens if cx < year_x - 40)
    row = {"NAME": name, "_unsure": []}
    votes = {}
    text_cols = {"YEAR", "POS"}
    for t, cx, _ in tokens:
        if cx < year_x - 40:
            continue
        col = min((c for c in cols if c != "NAME"), key=lambda c: abs(cols[c] - cx))
        if col in text_cols:
            row[col] = (row.get(col, "") + " " + t).strip()
        else:
            votes.setdefault(col, []).append(digits(t))
    # Reading the whole row lets OCR merge or drop neighbouring numbers, so read each numeric cell alone --
    # at one scale at first, and at more scales only while the reads still disagree.
    xs = sorted(cols.values())
    half = min(b - a for a, b in zip(xs, xs[1:])) / 2 - 4
    for col, cx in cols.items():
        if col == "NAME" or col in text_cols:
            continue
        raw = strip[:, max(int(cx - half), 0): int(cx + half)]
        raw = cv2.copyMakeBorder(raw, 12, 12, 12, 12, cv2.BORDER_REPLICATE)
        reads = votes.setdefault(col, [])
        for scale in (1, 2, 1.5, 3):
            if agreed(reads):
                break
            cell = cv2.resize(raw, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
            reads.append(digits(" ".join(clean(t) for t, _, _ in ocr(cell))))
    for col, vs in votes.items():
        vs = [v for v in vs if v]
        top, n = Counter(vs).most_common(1)[0] if vs else ("", 0)
        row[col] = top
        if n < 2 and col in ("OVR", *STAT_FIELDS):
            row["_unsure"].append(f"{col} votes {vs}")
    return row


def pane_box(shape):
    """(y0, y1, x0) of the right-hand player pane, as fractions of the frame."""
    h, w = shape[:2]
    return int(h * 0.207), int(h * 0.47), int(w * 0.79)


def read_pane(crop):
    res = ocr(crop)
    lines = [clean(t) for t, _, _ in res]
    up = [l.upper() for l in lines]
    class_idx = next((i for i, l in enumerate(up) if l in ("CLASS", "CLASS & NIL")), None)
    if "POSITION" not in up or class_idx is None:
        return None
    p, c = up.index("POSITION"), class_idx
    if p < 2 or p + 1 >= len(lines) or c + 1 >= len(lines):
        return None
    pos_line = lines[p + 1]
    m = re.match(r"([A-Z]+)(?:\s*\([A-Z]\))?\s*\|?\s*#?(\d+)?", pos_line.upper())
    return {"first": lines[p - 2], "last": lines[p - 1], "position": snap_position(m.group(1) if m else pos_line),
            "jersey": m.group(2) if m else None, "class": lines[c + 1].split("|")[0].strip()}


SUFFIXES = {"II", "III", "IV", "V"}


def title(name):
    """Pane text is ALL CAPS: restore capitalisation, keeping initials (TK) and suffixes (III, Jr.) right."""
    if len(name) <= 2:
        return name

    def word(w):
        if w in SUFFIXES:
            return w
        if w in ("JR.", "SR.", "JR", "SR"):
            return w.capitalize()
        return "-".join(p.capitalize() for p in w.split("-"))
    return " ".join(word(w) for w in name.split())


def alnum(s):
    """Letters only, ignoring a trailing suffix (OCR confuses I/l in 'III')."""
    s = re.sub(r"\s+(?:I[IL]+|IV|V|JR\.?|SR\.?)$", "", s.upper().strip())
    return re.sub(r"[^A-Z]", "", s)


def digits(s):
    m = re.search(r"\d+", s or "")
    return m.group(0) if m else ""


def build(pane, row):
    last_from_row = row["NAME"].split(".", 1)[1].strip() if "." in row["NAME"] else title(pane["last"])
    if alnum(last_from_row) != alnum(pane["last"]):
        last_from_row = title(pane["last"])  # the pane's larger text is the more reliable read
    player = {
        "first_name": title(pane["first"]),
        "last_name": title(last_from_row) if last_from_row.isupper() else last_from_row,
        "class_year": row.get("YEAR") or pane["class"],
        "position": pane["position"],
        "overall": digits(row.get("OVR")),
        "nil_amount": "",  # not tracked; kept empty so every team has the same shape
        "jersey": pane["jersey"],
    }
    for col, field in STAT_FIELDS.items():
        player[field] = digits(row.get(col))
    flags = [f"unsure: {u}" for u in row["_unsure"]]
    if alnum(row["NAME"].split(".", 1)[-1]) != alnum(pane["last"]):
        flags.append(f"row/pane last name differ: {row['NAME']!r} vs {pane['last']!r}")
    row_pos = snap_position(re.split(r"[\s(]", row.get("POS", ""))[0]) if row.get("POS") else ""
    if row_pos and row_pos != pane["position"]:
        flags.append(f"row/pane position differ: {row.get('POS')!r} vs {pane['position']!r}")
    if alnum(pane["class"]) and row.get("YEAR") and alnum(row["YEAR"]) != alnum(pane["class"]):
        flags.append(f"row/pane class differ: {row.get('YEAR')!r} vs {pane['class']!r}")
    if not player["overall"] or any(not player[f] for f in STAT_FIELDS.values()):
        flags.append("missing stat")
    if flags:
        player["needs_review"] = flags
    return player


COLS = {}


def init_worker(cols):
    COLS.update(cols)


def read_player(item):
    """Worker: OCR one player's pane crop + highlighted-row strip into (dedupe key, player dict)."""
    pane_crop, strip = item
    pane = read_pane(pane_crop)
    row = read_row(strip, COLS) if pane else None
    if not pane or not row:
        return None
    key = (pane["first"], pane["last"], pane["position"], pane["class"], pane["jersey"])
    return key, build(pane, row)


def scan(cap, total, shape):
    """Walk the video once; for each moment the pane holds still, keep small crops of that player."""
    y0, y1, x0 = pane_box(shape)
    items, prev, stable, frame_no = [], None, 0, -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_no += 1
        if frame_no % 30 == 0:  # machine-readable, consumed by the Rails job
            print(f"progress scan {frame_no} {total}", file=sys.stderr, flush=True)
        sig = cv2.resize(cv2.cvtColor(frame[y0:y1, x0:], cv2.COLOR_BGR2GRAY), (60, 32)).astype(int)
        stable = stable + 1 if prev is not None and np.abs(sig - prev).mean() < 1.5 else 0
        prev = sig
        if stable != STABLE_FRAMES:
            continue
        band = highlighted_band(frame)
        if band is None:
            continue
        tw = int(frame.shape[1] * 0.76)
        items.append((frame[y0:y1, x0:].copy(), frame[max(band[0] - 4, 0): band[1] + 4, :tw].copy()))
    return items


def worker_count():
    env = os.environ.get("ROSTER_VIDEO_WORKERS")
    return max(1, int(env)) if env else max(1, (os.cpu_count() or 2) // 2)


def main(path):
    cap = cv2.VideoCapture(path)
    ok, first = cap.read()
    cols = find_headers(first)
    if len(cols) < 6:
        sys.exit(f"could not find table headers in first frame (got {sorted(cols)})")
    print(f"columns: {sorted(cols, key=cols.get)}", file=sys.stderr)
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    items = scan(cap, int(cap.get(cv2.CAP_PROP_FRAME_COUNT)), first.shape)

    players, seen = [], set()
    with multiprocessing.get_context("spawn").Pool(worker_count(), initializer=init_worker, initargs=(cols,)) as pool:
        for done, result in enumerate(pool.imap(read_player, items), start=1):
            print(f"progress read {done} {len(items)}", file=sys.stderr, flush=True)
            if result is None or result[0] in seen:
                continue
            seen.add(result[0])
            players.append(result[1])
    review = sum("needs_review" in p for p in players)
    print(f"{len(players)} players, {review} flagged for review", file=sys.stderr)
    json.dump({"players": players}, sys.stdout, indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
