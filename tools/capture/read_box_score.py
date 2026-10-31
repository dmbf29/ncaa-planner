#!/usr/bin/env python3
"""Read a Box Score page off a Remote Play screenshot with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_box_score.py image.png

The page is a fixed layout: a line score on top (one row per team, a column per quarter plus
Final), then stat rows with the label in the middle and one value on each side. The left value
belongs to the team named in the left panel, the right one to the team in the right panel.
Returns the raw text of every value, e.g. {"First Downs": ["21", "17"]}; turning "31-127-0"
into fields is the caller's job.
"""
import difflib
import json
import re
import sys

from PIL import Image

from read_table import read_cell, read_row_strip, vision_items

LABELS = [
    "Score", "First Downs", "Total Offense", "Total Plays", "Yards Per Play", "Rushes - Yards - TDs", "Yards Per Rush",
    "Comp - Att - TDs", "Yards Per Pass", "Passing Yards", "3rd Down Conv.", "4th Down Conv.", "2-Point Conv.",
    "Red Zone TD-FG-%", "Turnovers", "Fumble Lost", "Interceptions", "PR Yards", "KR Yards", "Total Yards",
    "Punts - Avg", "Penalties - Yards", "T.O.P",
]


def squash(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())


SQUASHED = {squash(label): label for label in LABELS}


def label_for(text):
    match = difflib.get_close_matches(squash(text), SQUASHED, n=1, cutoff=0.85)
    return SQUASHED[match[0]] if match else None


def number_text(text):
    """Vision's usual digit mix-ups inside a stat value ("O-O" for "0-0")."""
    return text.strip().replace("O", "0").replace("o", "0")


def read_box_score(img):
    width, height = img.size
    items = vision_items(img)
    norm = [(text, cx / width, cy / height, h / height, cx, cy) for text, cx, cy, h, _l, _r in items]

    # --- team names from the two big panels (y ~ 0.39), left panel first
    panels = sorted((i for i in norm if 0.37 < i[2] < 0.42 and re.search(r"[A-Za-z]{3}", i[0])), key=lambda i: i[1])
    left_team = next((i[0] for i in panels if i[1] < 0.3), None)
    right_team = next((i[0] for i in reversed(panels) if i[1] > 0.7), None)

    # --- stat rows: label in the middle, a value either side on the same line
    pitch = 0.039
    labelled = {}
    for text, x, y, _h, _cx, _cy in norm:
        if 0.43 < x < 0.57 and y > 0.42:
            label = label_for(text)
            if label and label not in labelled:
                labelled[label] = y
    rows, missing = {}, []
    for label, y in labelled.items():
        sides = []
        for lo, hi, cx_guess in ((0.0, 0.4, 0.142), (0.6, 1.0, 0.858)):
            hits = [i for i in norm if lo < i[1] < hi and abs(i[2] - y) < pitch * 0.45]
            sides.append(number_text(hits[0][0]) if hits else None)
        for side, value in enumerate(sides):
            if value is None:
                # Cropped to its own line, Vision finds a lone digit it skipped on the full screen.
                left_x, right_x = ((0.05, 0.4), (0.6, 0.95))[side]
                strip = [t for t, _x in read_row_strip(img, y * height, pitch * height, left_x * width, right_x * width) if re.search(r"\d", t)]
                cell = float(number_text(strip[0])) if strip and re.fullmatch(r"\d+(\.\d+)?", number_text(strip[0])) else None
                if cell is None:
                    cell = read_cell(img, (0.142, 0.858)[side] * width, y * height, width * 0.025, pitch * height * 0.3)
                if cell is None:
                    missing.append(f"{label}/{'left' if side == 0 else 'right'}")
                else:
                    sides[side] = str(int(cell)) if cell == int(cell) else str(cell)
        rows[label] = sides

    # --- line score: header (1 2 3 4 [OT] Final) and one row per team
    header = sorted((i for i in norm if 0.25 < i[2] < 0.285 and 0.42 < i[1] < 0.75 and re.fullmatch(r"\d+|OT|\dOT|Final", i[0].strip(), re.I)),
                    key=lambda i: i[1])
    columns = [(h[0].strip(), h[1]) for h in header]
    names = [name for name, _x in columns]
    if "1" not in names and {"2", "3"} <= set(names):  # Vision sometimes skips the narrow "1" header; it sits one column left of "2"
        x2, x3 = dict(columns)["2"], dict(columns)["3"]
        columns.insert(0, ("1", x2 - (x3 - x2)))
    line = []
    for row_y in (0.312, 0.37):
        values = {}
        for name, x in columns:
            hits = [i for i in norm if abs(i[1] - x) < 0.02 and abs(i[2] - row_y) < 0.03 and re.fullmatch(r"\d+", number_text(i[0]))]
            if hits:
                values[name] = number_text(hits[0][0])
        if len(values) < len(columns):
            # A line cropped out of the page shows Vision the lone digits (a 0 quarter) it skips on the full screen.
            for text, cx in read_row_strip(img, row_y * height, 0.065 * height, 0.44 * width, 0.74 * width):
                column = min(columns, key=lambda c: abs(c[1] * width - cx))
                if column[0] not in values and abs(column[1] * width - cx) < width * 0.02 and re.fullmatch(r"\d+", number_text(text)):
                    values[column[0]] = number_text(text)
        for name, x in columns:
            if name not in values:
                cell = read_cell(img, x * width, row_y * height, width * 0.02, height * 0.025)
                if cell is None:
                    missing.append(f"line score {name}")
                else:
                    values[name] = str(int(cell))
        line.append(values)

    return {"left_team": left_team, "right_team": right_team, "rows": rows, "line_score": line, "missing": missing}


if __name__ == "__main__":
    print(json.dumps(read_box_score(Image.open(sys.argv[1]).convert("RGB")), indent=1))
