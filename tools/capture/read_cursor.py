#!/usr/bin/env python3
"""Read a cursor picture saved by watch.py (the highlighted Player Stats row stacked over the player card).

    backend/tools/roster_video/venv/bin/python tools/capture/read_cursor.py cursor/001.png

Returns {"card_name": "Jaquari Brown", "position": "CB", "number": 20, "numbers": [2.0, 2.0]}: the card's full
name, its position label and jersey number, and the numbers read off the row (zeros are left out, since Vision
skips a lone 0 and the caller only needs the non-zero values to tell two same-named players apart).
"""
import json
import re
import sys

from PIL import Image

from read_table import parse_number, vision_items



def read_cursor(img):
    items = vision_items(img)
    # The strip is the top band (about one row tall); the card sits under the black gap.
    strip_h = img.height * 0.2
    numbers = []
    for text, cx, cy, h, _l, _r in items:
        if cy < strip_h and cx > img.width * 0.2:
            value = parse_number(text)
            if value:
                numbers.append(value)
    card = sorted((i for i in items if i[2] >= strip_h and i[1] < img.width * 0.4), key=lambda i: i[2])
    lines = [i[0].strip() for i in card]
    name_parts, position, number = [], None, None
    for text in lines:
        if re.fullmatch(r"POSITION", text, re.I) or re.search(r"ARCHETYPE", text, re.I):
            break
        match = re.search(r"([A-Za-z]{1,5})\s*\|\s*#?\s*(\d+)", text)
        if match:
            position, number = match.group(1).upper(), int(match.group(2))
            continue
        if re.search(r"[A-Za-z]{2}", text):
            name_parts.append(text)
    # Anything after the POSITION label that looks like "CB | #20"
    if position is None:
        for text in lines:
            match = re.search(r"([A-Za-z]{1,5})\s*\|\s*#?\s*(\d+)", text)
            if match:
                position, number = match.group(1).upper(), int(match.group(2))
    name = " ".join(name_parts).strip()
    return {"card_name": name.title() if name.isupper() else name, "position": position, "number": number, "numbers": numbers}


if __name__ == "__main__":
    print(json.dumps(read_cursor(Image.open(sys.argv[1]).convert("RGB")), indent=1))
