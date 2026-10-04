#!/usr/bin/env python3
"""Turn a screen recording of the CFB roster table (scrolled right across every column set, then down a page,
repeat) into a Team Builder Unleashed CSV.

Prototype, local-only, macOS-only (Apple Vision OCR via ocrmac). Reuses OCR helpers from ../roster_video/extract.py
(read-only import -- that file is NOT modified).

    ../roster_video/venv/bin/python video_to_csv.py ../../roster_test/ul_monroe_full.mov out_dir/

How it works
  1. Find the moments the table holds still and keep one frame per distinct state.
  2. OCR every row of every kept frame, assigning each number to its column header.
  3. Stitch the frames together: consecutive frames share columns (horizontal scroll) and/or rows (vertical scroll),
     so the vertical shift between two frames is whichever one makes the shared cells agree. Rows are chained
     into players that way, so no timing or page counting is needed, and names (only visible in the leftmost view)
     get attached to the same player's ratings from the other views.
  4. Vote per cell across every view that showed it, write the CSV, and report anything weak.
"""
import csv
import json
import multiprocessing
import os
import re
import sys
from collections import Counter, defaultdict

import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "roster_video"))
from extract import (align_to_pane, alnum, clean, digits, edit_distance, lookalike_key, ocr, snap_position,  # noqa: E402
                     tidy_last_name, title)

TEXT_COLS = ["NAME", "YEAR", "POS", "OVR"]
RATINGS = ("SPD ACC AGI COD STR AWR CAR BCV BTK TRK SFA SPM JKM CTH CIT SPC SRR MRR DRR RLS JMP THP SAC MAC DAC "
           "RUN TUP BSK PAC PBK PBP PBF RBK RBP RBF LBK IBL PRC TAK POW BSH FMV PMV PUR MCV ZCV PRS RET KPW KAC "
           "STA TGH INJ LSP").split()
# Left-to-right order on the game's screen. NIL and DEV hold icons the importer doesn't need but they take up space.
CANON = ["NAME", "YEAR", "POS", "OVR", "NIL", "DEV"] + RATINGS
IGNORED = {"NIL", "DEV"}
CSV_RATING = {"RBF": "RPF"}  # the game says RBF, the importer's column is RPF
CSV_RATINGS = [CSV_RATING.get(r, r) for r in RATINGS]
# The importer wants the older labels; the game now shows EDG / MIKE / WILL / SAM.
POSITION_TO_CSV = {"LEDG": "LE", "REDG": "RE", "MIKE": "MLB", "WILL": "LOLB", "SAM": "ROLB"}
GAME_POSITIONS = {"QB", "HB", "FB", "WR", "TE", "LT", "LG", "C", "RG", "RT", "LEDG", "REDG", "DT", "MIKE", "WILL",
                  "SAM", "CB", "FS", "SS", "K", "P"}
CSV_HEADER = ["firstName", "lastName", "position", "jerseyNumber", "classYear", "heightInches", "weightLbs", "isLefty",
              "skinTone", "portraitId", "devTrait", "homeTown", "homeTownState"] + CSV_RATINGS

# Row geometry as fractions of the frame (measured on the 2824x1230 recording; the layout is proportional).
TABLE_X1 = 0.76
HEADER_Y = (0.27, 0.37)
ROW0_CENTER, ROW_PITCH, ROWS = 0.3935, 0.0716, 9
STABLE_FRAMES = 6
MIN_CHANGE = 2.0  # mean pixel change (0-255, on a 96x40 thumbnail) before a still frame counts as a new view


def table_region(frame):
    h, w = frame.shape[:2]
    return frame[int(h * 0.37):, : int(w * TABLE_X1)]


def row_strip(frame, i):
    h, w = frame.shape[:2]
    y0 = int((ROW0_CENTER + ROW_PITCH * (i - 0.5)) * h) + 2
    y1 = int((ROW0_CENTER + ROW_PITCH * (i + 0.5)) * h) - 2
    return frame[y0:y1, : int(w * TABLE_X1)]


# ----------------------------------------------------------------------------------------------------- 1. frames

def keep_still_frames(path, out_dir):
    cap = cv2.VideoCapture(path)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    kept, prev, last_kept, stable, n = [], None, None, 0, -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        n += 1
        if n % 600 == 0:
            print(f"progress scan {n} {total}", file=sys.stderr, flush=True)
        sig = cv2.resize(cv2.cvtColor(table_region(frame), cv2.COLOR_BGR2GRAY), (96, 40)).astype(float)
        stable = stable + 1 if prev is not None and np.abs(sig - prev).mean() < 1.0 else 0
        prev = sig
        if stable != STABLE_FRAMES:
            continue
        if last_kept is not None and np.abs(sig - last_kept).mean() < MIN_CHANGE:
            continue
        last_kept = sig
        file = os.path.join(out_dir, f"frame_{len(kept):04d}.jpg")
        cv2.imwrite(file, frame, [cv2.IMWRITE_JPEG_QUALITY, 95])
        kept.append(file)
    return kept


# ------------------------------------------------------------------------------------------------ 2. OCR a frame

def canon_name(text):
    """Map an OCR'd header ('PMU', '▼ OVR') onto a column name, or None."""
    words = re.findall(r"[A-Z]{2,5}", clean(text).upper())
    if not words:
        return None
    word = words[-1]
    if word in CANON:
        return word
    close = [c for c in CANON if len(c) == len(word) and edit_distance(c, word) <= 1]
    return close[0] if len(close) == 1 else None


def find_columns(frame):
    """{column: x centre in px} for the columns whose header is fully visible, in this frame."""
    h, w = frame.shape[:2]
    pw = int(w * TABLE_X1)
    found = []
    for text, _, (x, _y, bw, _h) in ocr(frame[int(h * HEADER_Y[0]): int(h * HEADER_Y[1]), :pw]):
        name = canon_name(text)
        if name:
            found.append((CANON.index(name), (x + bw / 2) * pw))
    found.sort(key=lambda f: f[1])
    mono = []  # keep a left-to-right run whose canonical order increases
    for idx, x in found:
        if not mono or idx > mono[-1][0]:
            mono.append((idx, x))
    cols = {}
    for (i0, x0), (i1, x1) in zip(mono, mono[1:] + [(None, None)]):
        cols[CANON[i0]] = x0
        if x1 is not None and 1 < i1 - i0 <= 4:  # a header the OCR missed: space it evenly in the gap
            for k in range(1, i1 - i0):
                cols[CANON[i0 + k]] = x0 + (x1 - x0) * k / (i1 - i0)
    return {c: x for c, x in cols.items() if 0.02 * pw < x < 0.985 * pw}


def split_numbers(text, x, bw):
    """A token like '86 91' (merged by OCR) becomes [(86, x of first), (91, x of second)]."""
    groups = re.findall(r"\d+", clean(text))
    return [(g, x + bw * (k + 0.5) / len(groups)) for k, g in enumerate(groups)]


def read_rows(frame, cols):
    """One dict per table row: {column: text}. Numbers are matched to the nearest header within half a column."""
    pw = int(frame.shape[1] * TABLE_X1)
    ordered = sorted(cols.items(), key=lambda kv: kv[1])
    xs = [x for _, x in ordered]
    year_x = cols.get("YEAR")
    rows = []
    for i in range(ROWS):
        strip = row_strip(frame, i)
        cells = {}
        for text, _, (x, _y, bw, _h) in ocr(strip):
            text = clean(text)
            cx = (x + bw / 2) * pw
            if "NAME" in cols or year_x:
                limit = (year_x - 60) if year_x else (cols["NAME"] + 200)
                if "NAME" in cols and cx < limit and not re.fullmatch(r"[\d\s]+", text):
                    cells["NAME"] = (cells.get("NAME", "") + " " + text).strip()
                    continue
            pieces = split_numbers(text, x * pw, bw * pw) if re.search(r"\d", text) else [(text, cx)]
            for piece, px in pieces:
                if not xs:
                    continue
                k = min(range(len(xs)), key=lambda j: abs(xs[j] - px))
                gaps = [abs(xs[j] - xs[k]) for j in (k - 1, k + 1) if 0 <= j < len(xs)]
                if abs(xs[k] - px) > 0.5 * (min(gaps) if gaps else 100):
                    continue
                col = ordered[k][0]
                if col in IGNORED or col == "NAME":
                    continue
                if col == "POS":
                    piece = re.sub(r"(?<=[A-Za-z])\d+$", "", piece)
                if col == "YEAR":
                    cells[col] = (cells.get(col, "") + " " + piece).strip()
                else:
                    cells.setdefault(col, piece)
        rows.append(cells)
    return rows


def process_frame(path):
    frame = cv2.imread(path)
    cols = find_columns(frame)
    return {"file": path, "cols": cols, "rows": read_rows(frame, cols)}



# ------------------------------------------------------------------------- 2b. the right-hand player pane
# Whichever player is highlighted shows full first/last name, handedness, jersey, height/weight and hometown there.
# The highlighted row of the table identifies who, and every player gets highlighted at least once.

STATES = ("Alabama AL|Alaska AK|Arizona AZ|Arkansas AR|California CA|Colorado CO|Connecticut CT|Delaware DE|Florida FL|"
          "Georgia GA|Hawaii HI|Idaho ID|Illinois IL|Indiana IN|Iowa IA|Kansas KS|Kentucky KY|Louisiana LA|Maine ME|"
          "Maryland MD|Massachusetts MA|Michigan MI|Minnesota MN|Mississippi MS|Missouri MO|Montana MT|Nebraska NE|"
          "Nevada NV|New Hampshire NH|New Jersey NJ|New Mexico NM|New York NY|North Carolina NC|North Dakota ND|"
          "Ohio OH|Oklahoma OK|Oregon OR|Pennsylvania PA|Rhode Island RI|South Carolina SC|South Dakota SD|"
          "Tennessee TN|Texas TX|Utah UT|Vermont VT|Virginia VA|Washington WA|West Virginia WV|Wisconsin WI|"
          "Wyoming WY").split("|")
# The importer's homeTownState is the index into that alphabetical list, 50 = Non-US.
STATE_INDEX = {entry.rsplit(" ", 1)[1]: i for i, entry in enumerate(STATES)}
NON_US = 50


LOOKALIKES = {"U": "V", "V": "U", "D": "O", "O": "D", "0": "O", "1": "I", "L": "I", "I": "L", "8": "B", "5": "S"}


def state_index(text):
    """Index of a US state abbreviation, forgiving one lookalike slip ('WU' for WV, 'DH' for OH); None if unknown."""
    if text in STATE_INDEX:
        return STATE_INDEX[text]
    fixes = {STATE_INDEX[text[:i] + LOOKALIKES[c] + text[i + 1:]] for i, c in enumerate(text)
             if c in LOOKALIKES and text[:i] + LOOKALIKES[c] + text[i + 1:] in STATE_INDEX}
    return fixes.pop() if len(fixes) == 1 else None


def read_pane_full(frame):
    """Read the pane; if height or weight didn't come out (OCR drops the quote mark sometimes), retry enlarged."""
    h, w = frame.shape[:2]
    crop = frame[int(h * 0.20): int(h * 0.56), int(w * 0.79):]
    best = None
    for scale in (1, 2, 3, 1.5):
        scaled = crop if scale == 1 else cv2.resize(crop, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        read = _read_pane(scaled)
        if read and best is None:
            best = read
        if read and read["height"] and read["weight"]:
            return read
    return best


def _read_pane(crop):
    res = [(clean(t), x, y, bw, bh) for t, _, (x, y, bw, bh) in ocr(crop)]
    labels = {t.upper(): (x, y) for t, x, y, _, _ in res}
    if "POSITION" not in labels:
        return None

    def below(label, side):
        if label not in labels:
            return None
        lx, ly = labels[label]
        cands = [(ly - y, t) for t, x, y, bw, _ in res if abs(x - lx) < 0.12 and 0 < ly - y < 0.2 and t.upper() != label]
        return min(cands)[1] if cands else None

    names = [t for t, x, y, _, _ in sorted(res, key=lambda r: -r[2]) if y > labels["POSITION"][1] + 0.06 and x < 0.3]
    if len(names) < 2:
        return None
    out = {"first": names[0], "last": " ".join(names[1:])}
    pos = below("POSITION", "l") or ""
    m = re.match(r"\s*([A-Z0-9]+)\s*(?:\(\s*([LR])\s*\))?\s*\|?\s*#?\s*(\d+)?", pos.upper())
    out["position"] = snap_position(m.group(1)) if m else ""
    out["lefty"] = {"L": True, "R": False}.get(m.group(2)) if m else None
    out["jersey"] = m.group(3) if m else None
    hw = below("HEIGHT & WEIGHT", "r") or ""
    hm = re.search(r"(\d)\s*['\u2019\u2018`\u00b4]\s*(\d{1,2})", hw)
    wm = re.search(r"(\d{2,3})\s*[lI1]?bs", hw)
    out["height"] = int(hm.group(1)) * 12 + int(hm.group(2)) if hm else None
    out["weight"] = int(wm.group(1)) if wm else None
    town = re.sub(r"[^A-Za-z0-9.,'\- ]", "", below("HOMETOWN", "l") or "").strip()
    city, _, st = town.rpartition(",")
    out["hometown"] = (city.strip()[:1].upper() + city.strip()[1:]) or None
    st = st.strip().upper()
    known = state_index(st)
    out["state"] = known if known is not None else (NON_US if city else None)
    out["state_text"] = st
    return out


def highlighted_row(frame):
    means = [cv2.cvtColor(row_strip(frame, i), cv2.COLOR_BGR2GRAY).mean() for i in range(ROWS)]
    best = int(np.argmax(means))
    return best if means[best] > 150 else None


def process_pane(path):
    frame = cv2.imread(path)
    hl = highlighted_row(frame)
    return {"file": path, "hl": hl, "pane": read_pane_full(frame) if hl is not None else None}


def attach_panes(frames, tracks, panes):
    """{track id: vote over every pane read taken while that track's row was highlighted}."""
    row_track = {(f, i): t for t, track in enumerate(tracks) for f, i in track}
    by_file = {p["file"]: p for p in panes}
    reads = defaultdict(list)
    for f, frame in enumerate(frames):
        p = by_file.get(frame["file"])
        if p and p["hl"] is not None and p["pane"]:
            t = row_track.get((f, p["hl"]))
            if t is not None:
                reads[t].append(p["pane"])
    return reads


def pane_vote(reads, table_last):
    """Settle one player's pane reads. Reads whose last name isn't the table's (the pane lagging a row change) are dropped."""
    mine = [r for r in reads if not table_last or lookalike_key(r["last"]) == lookalike_key(table_last)
            or edit_distance(lookalike_key(r["last"]), lookalike_key(table_last)) <= 1]
    result = {"reads": len(mine), "dropped": len(reads) - len(mine)}
    for field in ("first", "last", "position", "lefty", "jersey", "height", "weight", "hometown", "state", "state_text"):
        top, n, total = vote([r.get(field) if not isinstance(r.get(field), bool) else int(r[field]) for r in mine])
        result[field] = bool(top) if field == "lefty" and top is not None else top
        result[field + "_votes"] = (n, total)
    return result


# ----------------------------------------------------------------------------------------------- 3. stitch frames

def num(cell):
    d = digits(cell)
    return int(d) if d and 0 <= int(d) <= 99 else None


def shared_matches(a, b, shift):
    """(matching cells, compared cells) if frame b's row i+shift is frame a's row i."""
    match = total = 0
    for i in range(ROWS):
        j = i + shift
        if not 0 <= j < ROWS:
            continue
        for col in RATINGS + ["OVR"]:
            x, y = num(a["rows"][i].get(col)), num(b["rows"][j].get(col))
            if x is None or y is None:
                continue
            total += 1
            match += x == y
    return match, total


def best_shift(a, b):
    scored = []
    for s in range(-(ROWS - 1), ROWS):
        m, t = shared_matches(a, b, s)
        scored.append((m, t, s))
    scored.sort(reverse=True)
    best, second = scored[0], scored[1]
    return best, second


def stitch(frames):
    """Chain rows across consecutive frames. Returns ([player track: [(frame idx, row idx)]], problems)."""
    problems = []
    tracks = []
    owner = {}  # (frame idx, row idx) -> track id
    for i in range(ROWS):
        if frames[0]["rows"][i]:
            owner[(0, i)] = len(tracks)
            tracks.append([(0, i)])
    for f in range(1, len(frames)):
        (m, t, s), (m2, _, _) = best_shift(frames[f - 1], frames[f])
        if t < 12 or m < 0.75 * t or m - m2 < 0.2 * t:
            problems.append(f"frame {f}: weak link to the previous frame (shift {s}, {m}/{t} cells agree, "
                            f"runner-up {m2})")
        for j in range(ROWS):
            if not frames[f]["rows"][j]:
                continue
            prev = owner.get((f - 1, j - s))
            if prev is None:
                owner[(f, j)] = len(tracks)
                tracks.append([(f, j)])
            else:
                owner[(f, j)] = prev
                tracks[prev].append((f, j))
    return tracks, problems


# ------------------------------------------------------------------------------------------------- 4. vote + write

def vote(values):
    values = [v for v in values if v not in (None, "")]
    if not values:
        return None, 0, 0
    top, n = Counter(values).most_common(1)[0]
    return top, n, len(values)


def build_players(frames, tracks):
    players = []
    for t, track in enumerate(tracks):
        cells = defaultdict(list)
        for f, i in track:
            for col, text in frames[f]["rows"][i].items():
                cells[col].append(num(text) if col in RATINGS + ["OVR"] else text)
        players.append({"id": t, "cells": cells, "track": track, "flags": [] if "NAME" in cells else ["no name seen"]})
    return players


def parse_name(raw):
    m = re.match(r"^\s*([A-Za-z0-9])\s*\.\s*(.+)$", raw)
    if not m:
        return "", raw.strip()
    first = m.group(1).translate(str.maketrans("0158", "OISB"))
    last = re.sub(r"(^|[\s'\-])l", r"\1I", re.sub(r"'\s+", "'", m.group(2))).strip().rstrip(".")
    return first.upper(), tidy_last_name(last)


def load_db_roster(path):
    """The dynasty DB's roster for this team (bin/rails runner tools/team_builder_csv/dump_roster.rb)."""
    if not path or not os.path.exists(path):
        return []
    line = next((l for l in open(path) if l.startswith("{")), None)
    return json.loads(line)["players"] if line else []


def db_first_name(db, initial, last, position, year):
    """Full first name of the one DB player this is, or None if there isn't exactly one candidate."""
    key = lookalike_key(last)
    pool = [d for d in db if lookalike_key(d["last_name"] or "") == key]
    if not pool:
        pool = [d for d in db if abs(len(lookalike_key(d["last_name"] or "")) - len(key)) <= 1
                and edit_distance(lookalike_key(d["last_name"] or ""), key) <= 1]
    pool = [d for d in pool if alnum((d["first_name"] or "")[:1]) == alnum(initial)] or ([] if initial else pool)
    if len(pool) > 1:
        pool = [d for d in pool if d["position"] == position] or pool
    if len(pool) > 1:
        pool = [d for d in pool if (d["class_year"] or "").replace(" ", "").startswith(year)] or pool
    return pool[0]["first_name"] if len(pool) == 1 else None


def pane_reads_position(reads):
    return vote([r.get("position") for r in reads])[0] or ""


def finalize(players, pane_reads, db):
    out = []
    for p in players:
        flags = list(p["flags"])
        value = {}
        for col, vs in p["cells"].items():
            top, n, total = vote(vs)
            value[col] = top
            # Each cell is seen in ~25 frames, so stray misreads ('5' for 57 at a cut-off edge) are outvoted.
            if col in RATINGS and (n < 2 or n < 0.7 * total):
                flags.append(f"{col} unsure: {Counter(v for v in vs if v is not None).most_common(3)}")
        if value.get("LSP") is None:
            value["LSP"] = 0  # long snapper: the one column that scrolls off the right edge only briefly
        for col in RATINGS:
            if value.get(col) is None:
                flags.append(f"{col} missing")
        raw_name = value.get("NAME")
        initial, table_last = parse_name(raw_name) if raw_name else ("", "")
        position = snap_position(re.split(r"[\s(]", value.get("POS", "") or "")[0]) if value.get("POS") else ""
        if position not in GAME_POSITIONS:
            # The table's POS cell is occasionally unreadable ('P' next to the OVR column); the pane has it too.
            pane_position = snap_position(pane_reads_position(pane_reads.get(p["id"], [])))
            if pane_position in GAME_POSITIONS:
                position = pane_position
            else:
                flags.append(f"unknown position {value.get('POS')!r}")
        year = re.match(r"\s*(FR|SO|JR|SR)", (value.get("YEAR") or "").upper())
        year = year.group(1) if year else ""

        pane = pane_vote(pane_reads.get(p["id"], []), table_last)
        last = table_last
        if pane["reads"] and pane.get("last"):
            last = align_to_pane(table_last, pane["last"]) or table_last
        pane_first = title(pane["first"]) if pane["reads"] and pane.get("first") else None
        if pane_first and initial and alnum(pane_first[:1]) != alnum(initial):
            flags.append(f"pane first name {pane_first!r} doesn't start with the row's initial {initial!r}")
            pane_first = None
        db_first = db_first_name(db, initial, last, position, year) if db else None
        first, first_source = initial, "initial"
        if pane_first and pane["first_votes"][0] >= 2:
            first, first_source = pane_first, "video"
        elif db_first:
            first, first_source = db_first, "db"
        elif pane_first:
            first, first_source = pane_first, "video (1 read)"
        if pane_first and db_first and alnum(pane_first) != alnum(db_first):
            flags.append(f"first name: video says {pane_first!r}, DB says {db_first!r}")
        if first_source == "initial":
            flags.append("first name is only an initial")
        if pane["reads"] == 0:
            flags.append("never read from the side pane (no height/weight)")
        elif pane.get("position") and pane["position"] != position:
            flags.append(f"pane position {pane['position']!r} vs table {position!r}")
        if pane["reads"] and (pane.get("height") is None or pane.get("weight") is None):
            flags.append(f"height/weight unread (pane reads: {pane['reads']})")
        if pane["reads"] and pane.get("state") == NON_US and len(pane.get("state_text") or "") <= 3:
            flags.append("hometown state not a US abbreviation, set to Non-US")

        out.append({"first": first, "first_source": first_source, "last": last, "raw_name": raw_name,
                    "position": position, "csv_position": POSITION_TO_CSV.get(position, position), "class": year,
                    "ovr": value.get("OVR"), "jersey": pane.get("jersey"), "height": pane.get("height"),
                    "weight": pane.get("weight"), "lefty": pane.get("lefty"), "hometown": pane.get("hometown"),
                    "state": pane.get("state"), "pane_reads": pane["reads"],
                    "ratings": {CSV_RATING.get(r, r): value.get(r) for r in RATINGS}, "flags": flags})
    return out


def write_csv(players, path):
    def lefty(v):
        return "" if v is None else ("TRUE" if v else "FALSE")

    with open(path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(CSV_HEADER)
        for p in players:
            writer.writerow([p["first"], p["last"], p["csv_position"], p["jersey"] or "", p["class"], p["height"] or "",
                             p["weight"] or "", lefty(p["lefty"]), "", "", "", p["hometown"] or "",
                             "" if p["state"] is None else p["state"]] + [p["ratings"][r] for r in CSV_RATINGS])


def cached_pool_map(fn, items, cache_path, label):
    if os.path.exists(cache_path) and not os.environ.get("REOCR"):
        return json.load(open(cache_path))
    results = []
    with multiprocessing.get_context("spawn").Pool(max(1, (os.cpu_count() or 2) // 2)) as pool:
        for done, result in enumerate(pool.imap(fn, items), start=1):
            print(f"progress {label} {done} {len(items)}", file=sys.stderr, flush=True)
            results.append(result)
    json.dump(results, open(cache_path, "w"), indent=1)
    return results


def main(video, out_dir, db_roster=None):
    os.makedirs(out_dir, exist_ok=True)
    frame_dir = os.path.join(out_dir, "frames")
    os.makedirs(frame_dir, exist_ok=True)
    files = sorted(os.path.join(frame_dir, f) for f in os.listdir(frame_dir) if f.endswith(".jpg"))
    if not files or os.environ.get("RESCAN"):
        files = keep_still_frames(video, frame_dir)
    print(f"{len(files)} distinct still frames kept", file=sys.stderr, flush=True)
    frames = cached_pool_map(process_frame, files, os.path.join(out_dir, "frames.json"), "read")
    frames = [f for f in frames if len(f["cols"]) >= 4]
    panes = cached_pool_map(process_pane, [f["file"] for f in frames], os.path.join(out_dir, "panes.json"), "pane")
    tracks, problems = stitch(frames)
    db = load_db_roster(db_roster or os.path.join(out_dir, "db_roster.json"))
    players = finalize(build_players(frames, tracks), attach_panes(frames, tracks, panes), db)
    players = [p for p in players if p["last"]]
    json.dump({"players": players, "stitch_problems": problems}, open(os.path.join(out_dir, "players.json"), "w"),
              indent=1)
    write_csv(players, os.path.join(out_dir, "team_builder.csv"))
    flagged = sum(bool(p["flags"]) for p in players)
    print(f"{len(players)} players ({flagged} flagged), {len(problems)} weak frame links, {len(db)} DB players",
          file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:4])
