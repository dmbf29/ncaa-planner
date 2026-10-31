#!/usr/bin/env python3
"""Read a Top 25 poll screen off a Remote Play screenshot with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_top25.py image.png

Returns {"rows": [{"rank": 3, "name": "Ohio State", "lw": 2, "y": 0.41}]}: one entry per visible row whose
rank (1-25) was read at the left edge. The team name is the text after the rank up to the first number/dash
column (LW, W-L); matching it to a college is the backend's job (RankingStats::LocalTop25). Only the rank, name
and LW columns are read; the matchups are ignored.
"""
import json
import re
import sys

from PIL import Image

from read_table import vision_items

# Column boundaries as fractions of the window width. The poll reads RANK (with a small up/down arrow after the
# number), LW, a logo, NAME/VOTES, W-L, PTS, LAST WEEK, THIS WEEK; the player card on the right is ignored.
RANK_END, LW_END, NAME_START, NAME_END = 0.085, 0.15, 0.17, 0.30
TABLE_TOP, TABLE_BOTTOM = 0.31, 0.90
ROW_PITCH = 0.0465     # row height / window height


def leading_number(text):
    """The rank/LW number at the start of a cell; Vision tacks the trend arrow on as a letter ("5A", "10v")."""
    match = re.match(r"^\s*(\d{1,2})(?!\d)", text.replace("O", "0").replace("l", "1").replace("I", "1"))
    return int(match.group(1)) if match and 1 <= int(match.group(1)) <= 25 else None


def read_top25(img):
    w, h = img.size
    items = [(t.strip(), cx / w, cy / h) for t, cx, cy, _bh, _l, _r in vision_items(img) if t.strip()]
    items = [it for it in items if TABLE_TOP < it[2] < TABLE_BOTTOM]

    # Rows are anchored on the team names (always read); Vision sometimes drops a rank or LW digit, so a missing
    # rank is filled in from the nearest row whose rank was read (rows are one pitch apart and consecutive).
    anchors = []
    for _t, _x, y in sorted((it for it in items if NAME_START <= it[1] < NAME_END), key=lambda it: it[2]):
        if not anchors or y - anchors[-1] > ROW_PITCH * 0.5:
            anchors.append(y)

    rows = []
    for y in anchors:
        near = [it for it in items if abs(it[2] - y) < ROW_PITCH * 0.5]
        rank = next((leading_number(t) for t, tx, _ in near if tx < RANK_END and leading_number(t)), None)
        lw = next((leading_number(t) for t, tx, _ in near if RANK_END <= tx < LW_END and re.fullmatch(r"\d{1,2}", t)), None)
        name = " ".join(t for t, tx, _ in sorted(near, key=lambda it: it[1]) if NAME_START <= tx < NAME_END)
        name = re.sub(r"\s*\(\d+\)\s*$", "", name).strip()   # "Oklahoma (2)": first-place votes
        rows.append({"rank": rank, "name": name, "lw": lw, "y": round(y, 4)})

    known = [r for r in rows if r["rank"] is not None]
    for row in rows:
        if row["rank"] is None and known:
            ref = min(known, key=lambda r: abs(r["y"] - row["y"]))
            guess = ref["rank"] + round((row["y"] - ref["y"]) / ROW_PITCH)
            row["rank"] = guess if 1 <= guess <= 25 else None
    return {"rows": [r for r in rows if r["rank"] is not None]}


if __name__ == "__main__":
    print(json.dumps(read_top25(Image.open(sys.argv[1]).convert("RGB")), indent=1))
