#!/usr/bin/env python3
"""Read a Scores/Schedules screen off a Remote Play screenshot with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_schedule.py image.png

Returns {"week": "WEEK 1", "filter": "NATIONAL", "rows": [{"away", "connector", "home", "date", "result"}]}: the
raw text of each visible game row, top to bottom. Turning that into colleges, scores and dates is the backend's
job (ScheduleStats::LocalSchedule), since it knows the team names and abbreviations. The screen's layout is fixed,
so each piece of text is given to the column it sits in.
"""
import json
import re
import sys

from PIL import Image

from read_table import vision_items

# The game list is cropped out first (the right-hand side panel and the animated background only add noise).
CROP = (0.03, 0.15, 0.74, 0.90)
# Column boundaries as fractions of the cropped width.
AWAY_END, CONNECTOR_END, HOME_END, DATE_END, RESULT_END = 0.22, 0.30, 0.50, 0.63, 0.80
ROW_PITCH = 0.0467   # row height / window height


def join(items):
    return " ".join(text for text, *_rest in sorted(items, key=lambda it: it[1])).strip()


def read_schedule(img):
    w, h = img.size
    x0, y0, x1, y1 = (int(w * CROP[0]), int(h * CROP[1]), int(w * CROP[2]), int(h * CROP[3]))
    cw, ch = x1 - x0, y1 - y0
    # (text, x fraction of the crop, y fraction of the window)
    items = [(text, cx / cw, (y0 + cy) / h) for text, cx, cy, _bh, _l, _r in vision_items(img.crop((x0, y0, x1, y1)))]

    week = next((t for t, _x, y in items if re.fullmatch(r"(?i)(bowl )?week [\dO]+|conference championship", t.strip()) and y < 0.27), None)
    filt = next((t for t, x, y in items if x > 0.7 and y < 0.27 and len(t) > 3), None)
    header = next((y for t, _x, y in items if t.strip().upper() == "MATCHUP"), None)
    if header is None:
        return {"week": week, "filter": filt, "rows": []}

    body = sorted((it for it in items if it[2] > header + ROW_PITCH * 0.4), key=lambda it: it[2])
    rows, current = [], []
    for item in body:
        if current and item[2] - current[0][2] > ROW_PITCH * 0.4:
            rows.append(current)
            current = []
        current.append(item)
    if current:
        rows.append(current)

    out = []
    for row in rows:
        def column(lo, hi):
            return join([it[:2] for it in row if lo <= it[1] < hi])

        out.append({
            "away": column(0, AWAY_END), "connector": column(AWAY_END, CONNECTOR_END), "home": column(CONNECTOR_END, HOME_END),
            "date": column(HOME_END, DATE_END), "result": column(DATE_END, RESULT_END), "y": round(sum(it[2] for it in row) / len(row), 4),
        })
    return {"week": week, "filter": filt, "rows": out}


if __name__ == "__main__":
    print(json.dumps(read_schedule(Image.open(sys.argv[1]).convert("RGB")), indent=1))
