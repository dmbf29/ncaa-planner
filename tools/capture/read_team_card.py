#!/usr/bin/env python3
"""Read the team card of the opponent picker (Dynasty > Schedule > pick a team) with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_team_card.py image.png

Returns {"name": "ALABAMA", "rank": 13, "rank_unread": false, "overall": 92, "offense": 91, "defense": 94, "prestige": 5.0}. The card sits on the
right of the screen (name, five stars, then the OVR/OFF/DEF badges); the logo grid on the left is ignored. `rank` is the
number printed before the name for a ranked team, else None; `rank_unread` means a rank was printed but its digit couldn't be read. Prestige is counted from the stars' pixels, half a star at a
time: Vision can't read stars, and a half-filled star is a bright left half over a hollow right half.
"""
import json
import re
import sys

from PIL import Image

from read_table import vision_items

NAME_BOX = (0.55, 0.07, 0.97, 0.22)       # x0, y0, x1, y1 as fractions of the image
STARS_BOX = (0.800, 0.312, 0.910, 0.372)
FILLED_BRIGHTNESS = 170
HALF_FILLED = 0.08                          # share of a half-star's box that must be bright (a solid star only covers ~25% of its box; an outline ~1%)
STARS_INSET, STARS_SPAN = 0.027, 0.94       # where the five stars sit inside STARS_BOX, as fractions of its width


def inside(box, w, h, cx, cy):
    return box[0] * w <= cx <= box[2] * w and box[1] * h <= cy <= box[3] * h


def read_stars(img):
    w, h = img.size
    region = img.crop((int(STARS_BOX[0] * w), int(STARS_BOX[1] * h), int(STARS_BOX[2] * w), int(STARS_BOX[3] * h))).convert("L")
    star_w = region.width * STARS_SPAN / 5
    left = region.width * STARS_INSET
    halves = []
    for star in range(5):
        for half in range(2):
            x0 = int(left + star * star_w + half * star_w / 2)
            part = region.crop((x0, 0, int(x0 + star_w / 2), region.height))
            pixels = list(part.get_flattened_data() if hasattr(part, "get_flattened_data") else part.getdata())
            halves.append(sum(1 for p in pixels if p > FILLED_BRIGHTNESS) / len(pixels) > HALF_FILLED)
    return sum(halves) * 0.5


BADGE_CENTRES = (0.790, 0.856, 0.922)     # x of the OVR / OFF / DEF circles
BADGE_NUMBER_Y = (0.375, 0.455)


def read_number(img, box, low=1, high=99):
    """A number read from just its own crop, stretched: far more reliable than the full-screen pass for the badges."""
    from PIL import ImageOps
    w, h = img.size
    crop = img.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h))).convert("L")
    crop = ImageOps.autocontrast(crop).resize((crop.width * 3, crop.height * 3)).convert("RGB")
    for text, *_rest in sorted(vision_items(crop), key=lambda it: -it[3]):
        digits = re.sub(r"\D", "", text.translate(str.maketrans("OolI", "0011")))
        if digits and low <= int(digits) <= high:
            return int(digits)
    return None


def read_team_card(img):
    w, h = img.size
    items = vision_items(img)

    name_items = sorted((it for it in items if inside(NAME_BOX, w, h, it[1], it[2])), key=lambda it: -it[3])
    tallest = name_items[0][3] if name_items else 0
    line = sorted((it for it in name_items if abs(it[2] - name_items[0][2]) < tallest * 0.6), key=lambda it: it[1])
    text = " ".join(it[0] for it in line).strip()
    match = re.match(r"^(\d{1,2})\s+(.+)$", text)
    rank, name = (int(match.group(1)), match.group(2)) if match else (None, text)

    # Ranked teams print their poll rank in small type just left of the name, low on the line. Vision either misses it
    # or glues it to the name as a stray glyph ("«GEORGIA"), so read that spot on its own.
    glued = False
    if rank is None and line:
        left, mid = line[0][4] / w, line[0][2] / h
        glued = bool(re.match(r"^[^A-Za-z0-9]", name or ""))
        x0 = left - 0.002 if glued else left - 0.05
        rank = read_number(img, (x0, mid - 0.02, x0 + 0.02 if glued else left - 0.004, mid + 0.05), 1, 25)
    name = re.sub(r"^[^A-Za-z0-9]+", "", name or "") or None

    overall, offense, defense = (
        read_number(img, (c - 0.026, BADGE_NUMBER_Y[0], c + 0.026, BADGE_NUMBER_Y[1]), 20, 99)
        or next((int(it[0]) for it in items if abs(it[1] / w - c) < 0.03 and 0.36 < it[2] / h < 0.5 and re.fullmatch(r"[2-9]\d", it[0].strip())), None)
        for c in BADGE_CENTRES
    )
    return {"name": name or None, "rank": rank, "overall": overall, "offense": offense, "defense": defense, "prestige": read_stars(img),
            "rank_unread": rank is None and glued}


if __name__ == "__main__":
    print(json.dumps(read_team_card(Image.open(sys.argv[1]).convert("RGB"))))
