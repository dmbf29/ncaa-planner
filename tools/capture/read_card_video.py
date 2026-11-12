#!/usr/bin/env python3
"""Read every team card in a screen recording of the opponent picker (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_card_video.py recording.mov

Scrolling through the picker shows one team card at a time. Frames are pulled with ffmpeg, only ones where the card has
held still and differs from the last card read are OCR'd (read_team_card.py), and the result is one entry per team seen:
{"cards": [...]} printed to stdout (read_team_card's dicts). Progress goes to stderr as `progress read DONE TOTAL`.
"""
import json
import os
import subprocess
import sys
import tempfile
import warnings
from collections import Counter

warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image  # noqa: E402

from read_team_card import NAME_BOX, STARS_BOX, read_team_card  # noqa: E402

FPS = 4
THUMB = (96, 32)
HELD_STILL = 1.5      # mean grey-level change vs the previous frame below which the card is not moving
NEW_CARD = 4.0        # ...and above which it differs from the last card read


def thumb(img):
    w, h = img.size
    region = img.crop((int(NAME_BOX[0] * w), int(NAME_BOX[1] * h), int(NAME_BOX[2] * w), int(STARS_BOX[3] * h + 0.2 * h)))
    return list(region.convert("L").resize(THUMB).getdata())


def diff(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def main(path):
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"fps={FPS}", os.path.join(tmp, "%05d.png")], check=True)
        frames = sorted(os.listdir(tmp))
        previous, last_read, readings = None, None, []
        todo = []
        for name in frames:
            img = Image.open(os.path.join(tmp, name)).convert("RGB")
            current = thumb(img)
            if previous is not None and diff(current, previous) < HELD_STILL and (last_read is None or diff(current, last_read) > NEW_CARD):
                todo.append(name)
                last_read = current
            previous = current

        for index, name in enumerate(todo, 1):
            print(f"progress read {index} {len(todo)}", file=sys.stderr, flush=True)
            readings.append(read_team_card(Image.open(os.path.join(tmp, name)).convert("RGB")))

    # A team shown twice (scrolled back over) keeps its most common reading of each field.
    by_name = {}
    for reading in readings:
        if reading["name"]:
            by_name.setdefault(reading["name"].upper(), []).append(reading)
    cards = []
    for name, group in by_name.items():
        card = {"name": name, "readings": len(group)}
        for field in ("rank", "overall", "offense", "defense", "prestige"):
            values = [r[field] for r in group if r[field] is not None]
            card[field] = Counter(values).most_common(1)[0][0] if values else None
        card["rank_unread"] = card["rank"] is None and any(r["rank_unread"] for r in group)
        cards.append(card)
    print(json.dumps({"cards": cards}))


if __name__ == "__main__":
    main(sys.argv[1])
