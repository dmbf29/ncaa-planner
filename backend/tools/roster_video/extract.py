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
NAME_RE = re.compile(r"^[A-Za-z0-9]{1,2}\.\s*[A-Za-z]")  # the row's "J.Smith" shape


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


def confirmed(whole_reads, cell_reads):
    """True once the whole-row read and a single-cell read of the same cell give the same number.

    Only two *independent* methods agreeing counts: reads of one cell at different scales share the same
    pixels, so they can repeat the same slip (a green arrow next to "60" read as "09" at 1x and 2x).
    """
    return any(r and r in cell_reads for r in whole_reads)


def read_window(strip, cx, gap, scale):
    """The number at column centre cx, read from a window that includes the neighbouring columns."""
    x0 = max(int(cx - 1.6 * gap), 0)
    window = cv2.copyMakeBorder(strip[:, x0: int(cx + 1.6 * gap)], 12, 12, 12, 12, cv2.BORDER_REPLICATE)
    window = cv2.resize(window, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
    target = (cx - x0 + 12) * scale
    width = window.shape[1]
    best = None
    for text, _, (x, _y, bw, _h) in ocr(window):
        distance = abs((x + bw / 2) * width - target)
        if distance < 0.5 * gap * scale and (best is None or distance < best[0]):
            best = (distance, text)
    return digits(clean(best[1])) if best else ""


def read_row(strip, cols):
    tw = strip.shape[1]
    tokens = sorted(((clean(t), (x + bw / 2) * tw, x * tw) for t, _, (x, _y, bw, _h) in ocr(strip)),
                    key=lambda t: t[1])
    if not tokens:
        return None
    year_x = cols.get("YEAR", tw * 0.2)
    name = " ".join(t for t, cx, _ in tokens if cx < year_x - 40)
    if not NAME_RE.match(name):
        # Whole-row OCR sometimes drops the initial ("K.Shepherd" -> "..Shepherd"); the name cell alone reads fine.
        name_cell = cv2.copyMakeBorder(strip[:, : int(year_x - 40)], 12, 12, 12, 12, cv2.BORDER_REPLICATE)
        for scale in (2, 1.5, 3):
            retry = " ".join(clean(t) for t, _, _ in ocr(cv2.resize(name_cell, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)))
            if NAME_RE.match(retry):
                name = retry
                break
    row = {"NAME": name, "_unsure": []}
    votes = {}
    text_cols = {"YEAR", "POS"}
    for t, cx, _ in tokens:
        if cx < year_x - 40:
            continue
        col = min((c for c in cols if c != "NAME"), key=lambda c: abs(cols[c] - cx))
        if col in text_cols:
            if col == "POS":
                # POS sits right next to OVR, so OCR can merge them ("LT67"); only trailing digits go, since a
                # leading one is a misread letter ("0B" is QB) that snap_position fixes.
                t = re.sub(r"(?<=[A-Za-z])\d+$", "", t)
            row[col] = (row.get(col, "") + " " + t).strip()
        else:
            votes.setdefault(col, []).append(digits(t))
    # Reading the whole row lets OCR merge or drop neighbouring numbers, so each numeric cell is also read from a
    # window around it. The window has to include the neighbouring columns: an isolated cell crop gets its
    # orientation guessed wrong ("66" read as "99", "60" + arrow as "09"), at every scale.
    xs = sorted(cols.values())
    gap = float(np.median(np.diff(xs)))
    for col, cx in cols.items():
        if col == "NAME" or col in text_cols:
            continue
        reads = votes.setdefault(col, [])
        whole_reads = list(reads)
        for scale in (1, 2, 1.5, 3):
            if confirmed(whole_reads, reads[len(whole_reads):]):
                break
            reads.append(read_window(strip, cx, gap, scale))
    for col, vs in votes.items():
        vs = [v for v in vs if v]
        top, n = Counter(vs).most_common(1)[0] if vs else ("", 0)
        row[col] = top
        if n < 2 and col in ("OVR", *STAT_FIELDS):
            row["_unsure"].append(f"{col} votes {vs}")
    return row


CLASS_RE = re.compile(r"^\s*(FR|SO|JR|SR)\s*(\(\s*RS\s*\))?", re.IGNORECASE)


def class_from(text):
    """'SR (RS) K' -> 'SR (RS)': the pane's class line can carry a NIL diamond that OCR reads as a letter."""
    m = CLASS_RE.match(text.split("|")[0])
    if not m:
        return text.split("|")[0].strip()
    return f"{m.group(1).upper()} (RS)" if m.group(2) else m.group(1).upper()


def position_from_row(text):
    """The row's position cell, tolerating stray characters after it ('LGE' -> 'LG')."""
    token = re.split(r"[\s(]", text.strip())[0]
    snapped = snap_position(token)
    if snapped in VALID_POSITIONS:
        return snapped
    letters = re.sub(r"[^A-Z0-9]", "", token.upper())
    for size in range(len(letters) - 1, 0, -1):
        prefix = snap_position(letters[:size])
        if prefix in VALID_POSITIONS:
            return prefix
    return snapped


def pane_box(shape):
    """(y0, y1, x0) of the right-hand player pane, as fractions of the frame."""
    h, w = shape[:2]
    return int(h * 0.207), int(h * 0.47), int(w * 0.79)


def read_team(frame):
    """Team name from the dropdown bar above the table (e.g. 'TEXAS TECH'); None if unreadable."""
    h, w = frame.shape[:2]
    res = ocr(frame[int(h * 0.205): int(h * 0.29), int(w * 0.035): int(w * 0.235)])
    return " ".join(clean(t) for t, _, _ in res).strip() or None


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
    # A leading digit is a misread letter ("0B (R)" is QB); snap_position fixes it.
    m = re.match(r"([A-Z0-9]+)(?:\s*\([A-Z]\))?\s*\|?\s*#?(\d+)?", pos_line.upper())
    return {"first": lines[p - 2], "last": lines[p - 1], "position": snap_position(m.group(1) if m else pos_line),
            "jersey": m.group(2) if m else None, "class": class_from(lines[c + 1])}


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
    # An unresolved row/pane disagreement keeps the row's reading (white-on-dark, keeps casing like "McCullom")
    # and gets flagged below; resolve_names has already tried extra reads to settle it.
    player = {
        "first_name": title(pane["first"]),
        "last_name": title(last_from_row) if last_from_row.isupper() else last_from_row,
        "class_year": (row.get("YEAR") or pane["class"]).upper(),  # OCR sometimes returns the short labels as "so"
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
    if initial_of(row["NAME"]) and pane["first"] and alnum(initial_of(row["NAME"])) != alnum(pane["first"][0]):
        flags.append(f"row/pane first initial differ: {row['NAME']!r} vs {pane['first']!r}")
    row_pos = position_from_row(row["POS"]) if row.get("POS") else ""
    if row_pos and row_pos != pane["position"]:
        flags.append(f"row/pane position differ: {row.get('POS')!r} vs {pane['position']!r}")
    if alnum(pane["class"]) and row.get("YEAR") and alnum(row["YEAR"]) != alnum(pane["class"]):
        flags.append(f"row/pane class differ: {row.get('YEAR')!r} vs {pane['class']!r}")
    if pane["position"] not in VALID_POSITIONS:
        flags.append(f"unknown position {pane['position']!r}")
    if not player["overall"] or any(not player[f] for f in STAT_FIELDS.values()):
        flags.append("missing stat")
    if flags:
        player["needs_review"] = flags
    return player


COLS = {}


def init_worker(cols):
    COLS.update(cols)


DIGIT_LOOKALIKES = str.maketrans("0158", "OISB")


def initial_of(name):
    """First letter of the row's 'J.Smith' name, tolerating OCR reading the letter as a lookalike digit."""
    return name[:1].translate(DIGIT_LOOKALIKES)


LOOKALIKES = str.maketrans({"L": "I", "1": "I", "|": "I", "0": "O"})


def lookalike_key(text):
    """Letters only, with the characters the row font can't tell apart folded together (I/l/1/|, O/0)."""
    return re.sub(r"[^A-Z]", "", text.upper().translate(LOOKALIKES))


def align_to_pane(row_last, pane_last):
    """Settle a last name using both sources, each for what it reads reliably.

    The row is mixed case (McCullom, DeMarco) but its font can't tell a capital I from a lowercase l, or an O
    from a 0 ("Moore III" reads "Moore Ill", "Iosefa" reads "losefa"). The pane is ALL CAPS, so its letters are
    unambiguous. When the two agree up to those lookalikes, take the pane's letters and punctuation with the
    row's capitalisation. Returns None when they genuinely differ.
    """
    if lookalike_key(row_last) != lookalike_key(pane_last):
        return None
    row_chars = [c for c in row_last if c.isalnum()]
    out, k = [], 0
    for p in pane_last.upper():
        if not p.isalnum():
            out.append(p)
            continue
        if k >= len(row_chars):
            return None
        c = row_chars[k]
        k += 1
        if c.upper() == p:
            out.append(c)
        else:  # a lookalike: capital at the start of a word or after a capital (III), otherwise lowercase
            previous = out[-1] if out else ""
            out.append(p.lower() if previous.isalpha() and previous.islower() else p)
    return "".join(out)


def last_of(name):
    last = name.split(".", 1)[1] if "." in name else name
    return last.strip(" .")


def names_disagree(pane, row):
    initial = initial_of(row["NAME"])
    return alnum(last_of(row["NAME"])) != alnum(pane["last"]) or (
        bool(initial) and bool(pane["first"]) and alnum(initial) != alnum(pane["first"][0]))


def upscale(img, scale):
    return cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)


def resolve_names(pane, row, pane_reads, row_names):
    """Row and pane disagree on the name: settle it by majority across extra reads of both.

    The row's last name (white on dark) is the cleaner read; the pane's (coloured text on a team-coloured
    background) is the one that slips on low-contrast teams. Returns the pane/row, adjusted to agree when
    one reading clearly wins.
    """
    lasts = [(alnum(last_of(n)), last_of(n), "row") for n in row_names if last_of(n)]
    lasts += [(alnum(p["last"]), p["last"], "pane") for p in pane_reads]
    # Re-reading the same pixels at other scales isn't fully independent, and a pane slip tends to repeat,
    # so a row read counts double.
    weights = Counter()
    for key, _, src in lasts:
        if key:
            weights[key] += 2 if src == "row" else 1
    if weights:
        key, n = weights.most_common(1)[0]
        if n >= 2:
            display = next((d for k, d, src in lasts if k == key and src == "row"), None) or next(d for k, d, _ in lasts if k == key)
            pane = {**pane, "last": display}
            row = {**row, "NAME": f"{row['NAME'][:1] or pane['first'][:1]}.{display}"}
    firsts = Counter(alnum(p["first"]) for p in pane_reads if p["first"])
    if firsts:
        key, n = firsts.most_common(1)[0]
        if n >= 2:
            pane = {**pane, "first": next(p["first"] for p in pane_reads if alnum(p["first"]) == key)}
    return pane, row


def read_player(item):
    """Worker: OCR one player's pane crop + highlighted-row strip into (dedupe key, player dict)."""
    pane_crop, strip = item
    pane = read_pane(pane_crop)
    row = read_row(strip, COLS) if pane else None
    if not pane or not row:
        return None
    aligned = align_to_pane(last_of(row["NAME"]), pane["last"])
    if aligned and aligned != last_of(row["NAME"]):
        row = {**row, "NAME": f"{row['NAME'].split('.', 1)[0]}.{aligned}"}
    if names_disagree(pane, row):
        pane_reads = [pane] + [p for p in (read_pane(upscale(pane_crop, s)) for s in (2, 1.5, 3)) if p]
        name_strip = strip[:, : int(COLS.get("YEAR", strip.shape[1] * 0.2) - 40)]
        name_strip = cv2.copyMakeBorder(name_strip, 12, 12, 12, 12, cv2.BORDER_REPLICATE)
        row_names = [row["NAME"]] + [" ".join(clean(t) for t, _, _ in ocr(upscale(name_strip, s))) for s in (2, 3)]
        pane, row = resolve_names(pane, row, pane_reads, row_names)
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
    team = read_team(first)
    print(f"team: {team}", file=sys.stderr)
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
    json.dump({"team": team, "players": players}, sys.stdout, indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
