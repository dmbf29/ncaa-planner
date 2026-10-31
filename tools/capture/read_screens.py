#!/usr/bin/env python3
"""Read several Remote Play screenshots in one go (one Vision start-up instead of one per image).

    backend/tools/roster_video/venv/bin/python tools/capture/read_screens.py jobs.json

jobs.json is [{"file": "/path/shot.png", "kind": "box_score" | "table" | "schedule" | "top25" | "heisman" | "potw"}, ...]. Prints a JSON list, one
entry per job in the same order: {"file": ..., "kind": ..., "result": ...} where result is read_box_score's
dict, read_table's list of rows or read_schedule's dict, read_top25's / read_heisman's / read_potw's dict or {"error": "..."} if that image couldn't be read.
"""
import json
import os
import sys
import traceback
import warnings

warnings.filterwarnings("ignore")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image  # noqa: E402

from read_box_score import read_box_score  # noqa: E402
from read_schedule import read_schedule  # noqa: E402
from read_table import read_table  # noqa: E402
from read_heisman import read_heisman  # noqa: E402
from read_potw import read_potw  # noqa: E402
from read_top25 import read_top25  # noqa: E402


def read(job):
    img = Image.open(job["file"]).convert("RGB")
    if job["kind"] == "box_score":
        return read_box_score(img)
    if job["kind"] == "schedule":
        return read_schedule(img)
    if job["kind"] == "potw":
        return read_potw(img)
    if job["kind"] == "heisman":
        return read_heisman(img)
    if job["kind"] == "top25":
        return read_top25(img)
    return read_table(img)


if __name__ == "__main__":
    out = []
    for job in json.load(open(sys.argv[1])):
        try:
            result = read(job)
        except Exception:  # one unreadable image shouldn't sink the rest
            result = {"error": traceback.format_exc(limit=3)}
        out.append({"file": job["file"], "kind": job["kind"], "result": result})
    print(json.dumps(out))
