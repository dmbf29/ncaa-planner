#!/usr/bin/env python3
"""Read a Heisman Watch List screenshot (POS / NAME / TEAM / YEAR table) with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_heisman.py image.png

Returns {"rows": [{"pos", "name", "team", "year", "y"}]}: the raw text of each row, top to bottom. The columns are
located from the header words, so it works on a tight crop of the table as well as a whole window; matching the team
to a college and splitting the name is the backend's job (HeismanCandidates::LocalReader).
"""
import json
import re
import statistics
import sys

from PIL import Image

from read_table import vision_items

MARGIN = 0.01   # fraction of the image width: a column starts this far left of its header


def read_heisman(img):
    w, h = img.size
    # (text, left x fraction, centre y fraction, height fraction)
    items = [(t.strip(), left / w, cy / h, bh / h) for t, _cx, cy, bh, left, _r in vision_items(img) if t.strip()]

    def header(word):
        return next((it for it in items if it[0].upper() == word), None)

    pos, name, team, year = (header(word) for word in ("POS", "NAME", "TEAM", "YEAR"))
    if not (name and team and year):
        return {"rows": []}
    top = max(it[2] for it in (pos, name, team, year) if it) + statistics.median(it[3] for it in items) * 0.8
    edges = [name[1] - MARGIN, team[1] - MARGIN, year[1] - MARGIN]

    body = sorted((it for it in items if it[2] > top), key=lambda it: it[2])
    tolerance = statistics.median(it[3] for it in body) * 0.6 if body else 0
    rows, current = [], []
    for item in body:
        if current and item[2] - current[-1][2] > tolerance:
            rows.append(current)
            current = []
        current.append(item)
    if current:
        rows.append(current)

    def column(row, lo, hi):
        return " ".join(t for t, x, _y, _h in sorted(row, key=lambda it: it[1]) if lo <= x < hi).strip()

    def reread_pos(y):
        """Vision skips a short cell on a busy row; read just that cell, enlarged."""
        half = tolerance * 1.5
        crop = img.crop((0, max(0, int((y - half) * h)), int((edges[0]) * w), min(h, int((y + half) * h))))
        crop = crop.resize((crop.width * 3, crop.height * 3), Image.LANCZOS)
        text = " ".join(t for t, *_rest in vision_items(crop)).strip().upper()
        return text if re.fullmatch(r"[A-Z]{1,3}", text) else ""

    out = []
    for row in rows:
        out.append({
            "pos": column(row, -1, edges[0]) or reread_pos(sum(it[2] for it in row) / len(row)), "name": column(row, edges[0], edges[1]),
            "team": re.sub(r"^\d{1,2}\s+", "", column(row, edges[1], edges[2])),   # a rank number sits before ranked teams
            "year": column(row, edges[2], 2), "y": round(sum(it[2] for it in row) / len(row), 4),
        })
    return {"rows": out}


if __name__ == "__main__":
    print(json.dumps(read_heisman(Image.open(sys.argv[1]).convert("RGB")), indent=1))
