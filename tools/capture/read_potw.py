#!/usr/bin/env python3
"""Read a Player of the Week screenshot (one scope, an OFFENSIVE and a DEFENSIVE winner) with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_potw.py image.png

Returns {"scope": "NATIONAL" | "SUN BELT" | ..., "week": "SEASON WEEK 1", "cards": [{"side", "first", "last", "pos",
"opponent", "venue", "result", "team_score", "opponent_score", "stat_lines": [...]}]}. The winner's own team is only a
logo on this screen, so the backend finds it from the opponent and score (PlayersOfTheWeek::GameCollegeResolver).
Cards are found from their DEFENSIVE / OFFENSIVE labels and each piece of text is recognised by its shape, so it works
on a screenshot of any size.
"""
import json
import re
import sys

from PIL import Image

from read_table import vision_items

CONTEXT = re.compile(r"^(vs|at)\s+(.+?)\s*\(\s*([WL])\s*(\d+)\s*-\s*(\d+)\s*\)$", re.I)


def read_potw(img):
    w, h = img.size
    # (text, left x, centre y, height) as fractions of the image
    items = [(t.strip(), left / w, cy / h, bh / h) for t, _cx, cy, bh, left, _r in vision_items(img) if t.strip()]
    top = [it for it in items if it[2] < 0.14]
    scope = next((t for t, x, _y, _h in sorted(top, key=lambda it: it[1]) if x < 0.5 and len(t) > 2 and not re.fullmatch(r"L\d|R\d", t)), None)
    week = next((t for t, x, _y, _h in top if x > 0.5 and re.search(r"week|championship", t, re.I)), None)

    labels = sorted(((t.upper(), y) for t, x, y, _h in items if x < 0.2 and t.upper() in ("DEFENSIVE", "OFFENSIVE")), key=lambda it: it[1])
    cards = []
    for i, (label, label_y) in enumerate(labels):
        end = labels[i + 1][1] - 0.02 if i + 1 < len(labels) else 1.0
        body = [it for it in items if label_y - 0.01 <= it[2] < end and it[1] > 0.3]

        number = next((it for it in body if re.fullmatch(r"#\d{1,2}", it[0]) and it[1] > 0.7), None)
        pos = None
        if number:
            pos = next((t for t, x, y, _h in body if abs(y - number[2]) < 0.03 and x < number[1] and re.fullmatch(r"[A-Z]{1,4}", t)), None)

        name_items = [it for it in body if it[1] < 0.7 and re.fullmatch(r"[A-Za-z'.\- ]+", it[0]) and not CONTEXT.match(it[0])]
        last = max(name_items, key=lambda it: it[3], default=None)
        first = None
        if last:
            above = [it for it in name_items if it[2] < last[2] and last[2] - it[2] < last[3] * 2.5 and it is not last]
            first = max(above, key=lambda it: it[2], default=None)

        context = next((m for t, *_r in body if (m := CONTEXT.match(t))), None)
        context_y = next((y for t, _x, y, _h in body if CONTEXT.match(t)), None)
        stats = [t for t, x, y, _h in sorted(body, key=lambda it: it[2]) if context_y and y > context_y + 0.01 and x < 0.9 and re.search(r"\d", t)]
        cards.append({
            "side": label.lower(), "first": first[0] if first else None, "last": last[0] if last else None, "pos": pos,
            "opponent": context.group(2) if context else None, "venue": context.group(1).lower() if context else None,
            "result": context.group(3).upper() if context else None,
            "team_score": int(context.group(4)) if context else None, "opponent_score": int(context.group(5)) if context else None,
            "stat_lines": stats,
        })
    return {"scope": scope, "week": week, "cards": cards}


if __name__ == "__main__":
    print(json.dumps(read_potw(Image.open(sys.argv[1]).convert("RGB")), indent=1))
