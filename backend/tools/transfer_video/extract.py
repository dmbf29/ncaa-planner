#!/usr/bin/env python3
"""Read a screen recording of the "players leaving" (Reason / Persuasion Chance) screen and list who is transferring.

Scroll through each team so every player is highlighted in turn. For each highlighted row whose REASON starts with
"Transfer" or "Leaving" (the same thing), the right-hand pane gives the full name, position, class, overall and the six attribute tiles. Rows with any
other reason (Pro Draft, Graduation, Staying) are ignored. Everything is OCR'd locally (Apple Vision via ocrmac) --
no AI API calls. Reuses the pane/name helpers from tools/roster_video and its venv.

    python extract.py transfers.mov > transfers.json
"""
import json
import multiprocessing
import os
import re
import sys
from collections import Counter
import importlib.util
from pathlib import Path

import cv2
import numpy as np

# roster_video's extract.py (OCR + name/pane helpers), loaded by path since both tools call their script "extract".
_spec = importlib.util.spec_from_file_location("roster_video_extract", Path(__file__).resolve().parent.parent / "roster_video" / "extract.py")
rv = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rv)

OUTPUT_VERSION = 1
STABLE_FRAMES = 3
PANE_X0 = 0.78  # the pane's left edge, as a fraction of frame width
ATTRIBUTE_FIELDS = {"AWARENESS": "awareness", "SPEED": "speed", "ACCELERATION": "acceleration",
                    "STRENGTH": "strength", "AGILITY": "agility", "CHANGE OF DIRECTION": "change_of_direction"}
REASON_RE = re.compile(r"^\W*(?:tran[s5]f[e3]r|leaving)\b(?:\W*\(?\s*(.*?)\)?\s*$)?", re.IGNORECASE)


OTHER_REASON_RE = re.compile(r"pro\s*draft|graduat|staying", re.IGNORECASE)


def pane_signature_box(shape):
    h, w = shape[:2]
    return int(h * 0.2), int(h * 0.9), int(w * PANE_X0)


def highlighted_band(frame):
    """(top, bottom) of the outlined row. The selected row is a dark row with a bright border, so look for its two
    horizontal edges rather than a filled band; a wide bright block (an open team dropdown) is rejected."""
    h, w = frame.shape[:2]
    top = int(h * 0.30)
    gray = cv2.cvtColor(frame[top:, int(w * 0.08): int(w * 0.72)], cv2.COLOR_BGR2GRAY)
    bright = np.where(gray.mean(axis=1) > 150)[0]
    if len(bright) < 2:
        return None
    first, last = bright[0], bright[-1]
    if not (0.05 * h < last - first < 0.11 * h) or len(bright) > 30:
        return None
    return top + first, top + last


def scan(cap, total, shape):
    """Walk the video once; each time the pane holds still, keep crops of the row, pane, overall and team banner."""
    y0, y1, x0 = pane_signature_box(shape)
    h, w = shape[:2]
    items, prev, stable, frame_no = [], None, 0, -1
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        frame_no += 1
        if frame_no % 30 == 0:  # machine-readable, consumed by the Rails job
            print(f"progress scan {frame_no} {total}", file=sys.stderr, flush=True)
        sig = cv2.resize(cv2.cvtColor(frame[y0:y1, x0:], cv2.COLOR_BGR2GRAY), (60, 40)).astype(int)
        stable = stable + 1 if prev is not None and np.abs(sig - prev).mean() < 1.5 else 0
        prev = sig
        if stable != STABLE_FRAMES:
            continue
        band = highlighted_band(frame)
        if band is None:
            continue
        reason = frame[band[0]: band[1] + 1, int(w * 0.29): int(w * 0.58)].copy()
        height = band[1] - band[0] + 1
        below = frame[band[1] + 1: band[1] + 1 + height, : int(w * 0.58)]
        items.append({
            "reason": reason,
            "below": below.copy() if below.shape[0] >= height * 0.8 else None,
            "pane": frame[int(h * 0.207): int(h * 0.47), x0:].copy(),
            "ovr": frame[int(h * 0.02): int(h * 0.13), int(w * 0.925):].copy(),
            "attrs": frame[int(h * 0.60): int(h * 0.92), x0:].copy(),
            "banner": frame[int(h * 0.02): int(h * 0.09), int(w * 0.11): int(w * 0.43)].copy(),
        })
    return items


def reason_of(crop):
    """The reason text of the highlighted row, and whether it is a Transfer ('Transfer (Playing Style)')."""
    text = " ".join(rv.clean(t) for t, _, _ in rv.ocr(cv2.resize(crop, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC))).strip()
    m = REASON_RE.match(text)
    # A crop caught mid-scroll can hold part of a neighbouring row ("Transfer (NIL) Pro Draft (Projected Round 5"):
    # that reading is the wrong row, so it is dropped rather than flagging a player who isn't leaving.
    if not m or OTHER_REASON_RE.search(text):
        return text, None
    return text, (m.group(1) or "").rsplit("(", 1)[-1].strip(" ()")


def read_attributes(crop):
    """({label: int} for every attribute tile, {field: int} for the six that have columns). Each number is paired
    with the label directly above it; the tiles shown depend on the player's position."""
    res = rv.ocr(crop)
    labels, values = [], []
    for text, _, (x, y, bw, bh) in res:
        t = rv.clean(text).upper()
        cx, top = x + bw / 2, 1 - (y + bh)  # Vision's origin is bottom-left
        if re.fullmatch(r"\d{2,3}", t):
            values.append((cx, top, int(t)))
        elif t.isalpha() or " " in t:
            labels.append((cx, top, re.sub(r"\s+", " ", t)))
    tiles = {}
    for cx, top, value in values:
        above = [(top - ltop, label) for lcx, ltop, label in labels if abs(lcx - cx) < 0.15 and 0 < top - ltop < 0.25]
        if above:
            tiles.setdefault(min(above)[1], value)
    return tiles


def read_table_row(crop):
    """A table row seen without its highlight: initial, last name, position, class, overall and transfer reason.

    While the stick is held the highlight sometimes jumps two rows, so a player is visible in the table but never
    selected and the pane never shows their full name. Only the row's own text is readable for them. The dim POS /
    YEAR / OVR cells get merged by OCR, so those three are parsed together from one string.
    """
    crop = cv2.resize(crop, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    name, middle, reason = [], [], []
    for text, _, (x, _y, bw, _h) in sorted(rv.ocr(crop), key=lambda r: r[2][0]):
        cx = (x + bw / 2) * 0.58  # fraction of the full frame width
        (name if cx < 0.125 else middle if cx < 0.285 else reason).append(rv.clean(text))
    reason, name, middle = REASON_RE.match(" ".join(reason)), re.match(r"^(\w)\.\s*(.+)$", " ".join(name).strip()), " ".join(middle)
    parsed = re.match(r"^\s*(?:(?!(?:FR|SO|JR|SR)\b)([A-Z0-9]{1,4})\s+)?((?:FR|SO|JR|SR)\s*(?:\(\s*RS\s*\))?)?\s*(\d{2})?\s*$", middle.upper())
    if not reason or not name or not parsed:
        return None
    position, class_year, overall = parsed.groups()
    return {"first_initial": rv.initial_of(name.group(1)), "last_name": rv.tidy_last_name(name.group(2)),
            "position": rv.position_from_row(position) if position else "",
            "class_year": re.sub(r"\s*\(\s*RS\s*\)", " (RS)", class_year).strip() if class_year else "",
            "overall": int(overall) if overall else None,
            "transfer_reason": (reason.group(1) or "").strip()}


def read_item(item):
    """(player read from the pane or None, the next row down read from the table or None)."""
    reason_text, detail = reason_of(item["reason"])
    if detail is None:
        return None, None
    below = read_table_row(item["below"]) if item["below"] is not None else None
    return read_player(item, detail), below


def read_player(item, detail):
    pane = rv.read_pane(item["pane"])
    if not pane:
        return None
    if pane["position"] not in rv.VALID_POSITIONS:  # a stray glyph from the "HB | #0" line ("ĐT | #97")
        pane["position"] = rv.snap_position(re.sub(r"[^A-Z]", "", pane["position"].split("|")[0].upper().replace("Đ", "D")))
    ovr = rv.digits(" ".join(rv.clean(t) for t, _, _ in rv.ocr(cv2.resize(item["ovr"], None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC))))
    team = " ".join(rv.clean(t) for t, _, _ in rv.ocr(item["banner"])).strip()
    tiles = read_attributes(item["attrs"])
    for scale in (2, 3):  # OCR occasionally drops a tile; a larger read of the same crop usually finds it
        if len(tiles) >= 6:
            break
        bigger = cv2.resize(item["attrs"], None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        tiles = {**read_attributes(bigger), **tiles}
    attributes = {field: tiles[label] for label, field in ATTRIBUTE_FIELDS.items() if label in tiles}
    player = {
        "team": team,
        "first_name": rv.title(pane["first"]),
        "last_name": rv.tidy_last_name(rv.title(pane["last"])),
        "position": pane["position"],
        "class_year": pane["class"],
        "overall": int(ovr) if ovr else None,
        "transfer_reason": detail,
        "ratings": {re.sub(r"\W+", "_", label.lower()).strip("_"): value for label, value in tiles.items()},
        **attributes,
    }
    flags = []
    if player["overall"] is None:
        flags.append("missing overall")
    if len(tiles) != 6:
        flags.append(f"read {len(tiles)} of 6 attribute tiles")
    if pane["position"] not in rv.VALID_POSITIONS:
        flags.append(f"unknown position {pane['position']!r}")
    if not team:
        flags.append("team unreadable")
    if flags:
        player["needs_review"] = flags
    return player


def worker_count():
    env = os.environ.get("ROSTER_VIDEO_WORKERS")
    return max(1, int(env)) if env else max(1, (os.cpu_count() or 2) // 2)


def unseen_rows(players, candidates):
    """Table rows with a Transfer reason whose player never got highlighted (so has no pane reading)."""
    seen = {}
    for p in players:
        seen.setdefault(p["team"], []).append(p)
    out, taken = [], set()
    for team, row in candidates:
        key = (team, rv.lookalike_key(row["last_name"]))
        if key in taken:
            continue
        known = any(rv.names_match(row["last_name"], p["last_name"]) and
                    row["position"] in ("", rv.position_from_row(p["position"])) for p in seen.get(team, []))
        if not known:
            taken.add(key)
            out.append({"team": team, **row})
    return out


def completeness(player):
    return len(player["ratings"]) + (player.get("overall") is not None)


def main(path):
    cap = cv2.VideoCapture(path)
    ok, first = cap.read()
    if not ok:
        sys.exit("could not read the video")
    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
    items = scan(cap, int(cap.get(cv2.CAP_PROP_FRAME_COUNT)), first.shape)

    best, candidates, last_team = {}, [], ""
    with multiprocessing.get_context("spawn").Pool(worker_count()) as pool:
        for done, (player, below) in enumerate(pool.imap(read_item, items), start=1):
            print(f"progress read {done} {len(items)}", file=sys.stderr, flush=True)
            if player is None:
                continue
            if below:
                candidates.append((player["team"], below))
            key = (player["team"], rv.alnum(player["first_name"]), rv.alnum(player["last_name"]), player["position"])
            # The same player is usually seen in several moments; keep the fullest reading.
            if key not in best or completeness(player) > completeness(best[key]):
                best[key] = player
    players = list(best.values())
    unseen = unseen_rows(players, candidates)
    teams = Counter(p["team"] for p in players)
    review = sum("needs_review" in p for p in players)
    print(f"{len(players)} transfers across {len(teams)} teams, {review} flagged for review, {len(unseen)} not highlighted", file=sys.stderr)
    json.dump({"players": players, "unhighlighted": unseen}, sys.stdout, indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
