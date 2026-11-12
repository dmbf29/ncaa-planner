#!/usr/bin/env python3
"""Read a team's schedule-setup screen (Dynasty > Schedule, the WEEK / LOCATION / OPPONENT / STADIUM list) with Apple Vision.

    backend/tools/roster_video/venv/bin/python tools/capture/read_team_schedule.py image.png

Returns {"team": "MISSOURI STATE", "rows": [{"week": 3, "location": "AT", "stadium": "...", "opponent": "NDSU", "locked": false, "open": false}]}.
The AT/VS cell of a dimmed (locked) row is too faint for Vision, so `location` is often blank there; the backend works out
home/away from `stadium` instead (the team's own stadium is the one most rows share).
`open` is true for an "OPEN" row (no opponent). `locked` comes from the padlock beside the week number: the game dims
locked rows, and a padlock sits at a fixed spot, so it is detected from pixels rather than OCR. A locked row with an
opponent is a fixed game; a locked OPEN row is a bye; an unlocked row with an opponent is a pre-filled option the coach
can still change. The cursor row is drawn white with no padlock, so it always reads as unlocked.
"""
import json
import re
import sys

from PIL import Image

from read_table import vision_items

WEEK_END, LOCATION_END, OPPONENT_START, OPPONENT_END = 0.17, 0.37, 0.43, 0.70
LOCK_BOX = (0.020, 0.048)    # padlock x range as fractions of the width
ROW_HALF_HEIGHT = 0.02       # of the image height, around each row's centre


def clean_week(text):
    digits = re.sub(r"[^0-9OolI]", "", text).translate(str.maketrans("OolI", "0011"))
    return int(digits) if digits.isdigit() and int(digits) <= 19 else None


def has_lock(img, cy):
    """True when the dim padlock sits at its spot on a dark row. Locked rows are drawn lighter (grey ~64, padlock ~100)
    than unlocked ones (flat ~44), and the white cursor row has no padlock."""
    w, h = img.size
    box = img.crop((int(w * LOCK_BOX[0]), int(cy - h * ROW_HALF_HEIGHT), int(w * LOCK_BOX[1]), int(cy + h * ROW_HALF_HEIGHT))).convert("L")
    pixels = box.get_flattened_data() if hasattr(box, "get_flattened_data") else box.getdata()
    pixels = list(pixels)
    if sum(pixels) / len(pixels) > 150:
        return False
    return sum(1 for p in pixels if p > 70) / len(pixels) > 0.02


def cluster(values, gap):
    groups = []
    for value in sorted(values):
        if groups and value - groups[-1][-1] < gap:
            groups[-1].append(value)
        else:
            groups.append([value])
    return [sum(g) / len(g) for g in groups]


def read_team_schedule(img):
    w, h = img.size
    items = vision_items(img)
    team = next((t for t, cx, cy, _bh, l, _r in sorted(items, key=lambda it: it[2]) if cy < h * 0.12 and w * 0.05 < l < w * 0.3 and len(t) > 2 and t.strip().upper() != "L2"), None)
    header = next((cy for t, _cx, cy, *_ in items if t.strip().upper() == "WEEK"), None)
    if header is None:
        return {"team": team, "rows": []}

    # Dimmed (locked) rows are the ones Vision skips most often, so rows are found from the opponent column and each
    # row's week is counted from whichever week numbers were read, a row pitch apart.
    body = [it for it in items if it[2] > header + h * 0.04]
    centres = cluster([it[2] for it in body if w * OPPONENT_START <= it[4] < w * OPPONENT_END], h * 0.03)
    if not centres:
        return {"team": team, "rows": []}
    diffs = sorted(b - a for a, b in zip(centres, centres[1:]))
    pitch = next((d for d in diffs if d > h * 0.05), h * 0.0875)
    anchors = []
    for t, cx, cy, *_ in body:
        week = clean_week(t) if cx < w * WEEK_END else None
        row = min(centres, key=lambda c: abs(c - cy))
        if week is not None and abs(row - cy) < pitch * 0.4:
            anchors.append((week, row))
    rows = []
    for cy in centres:
        week = None
        if anchors:
            base_week, base_cy = anchors[0]
            week = base_week + round((cy - base_cy) / pitch)
        in_row = [it for it in body if abs(it[2] - cy) < pitch * 0.4]
        location = " ".join(it[0] for it in in_row if w * WEEK_END <= it[1] < w * LOCATION_END).strip()
        opponent = " ".join(it[0] for it in sorted(in_row, key=lambda it: it[1]) if w * OPPONENT_START <= it[4] < w * OPPONENT_END).strip()
        opponent = re.sub(r"^[^A-Za-z0-9]+", "", opponent)  # the little person icon marking another user's team
        is_open = opponent.upper() == "OPEN"
        stadium = " ".join(it[0] for it in sorted(in_row, key=lambda it: it[1]) if it[4] >= w * OPPONENT_END).strip()
        rows.append({"week": week, "location": location, "stadium": stadium, "opponent": "" if is_open else opponent, "open": is_open,
                     "locked": has_lock(img, cy), "y": round(cy / h, 4)})
    return {"team": team, "rows": rows}


if __name__ == "__main__":
    print(json.dumps(read_team_schedule(Image.open(sys.argv[1]).convert("RGB")), indent=1))
