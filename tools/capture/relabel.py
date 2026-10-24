#!/usr/bin/env python3
"""Re-label an already-saved capture folder, e.g. after the watcher's team reading was fixed.

    python3 tools/capture/relabel.py pod/captures/game-1429-... --teams "UL Monroe,SMU"

Re-reads the team on every Team Stats screen, copies it onto the grafted Defense
composites, and marks later repeats of a screen as ignored (they're kept on disk but
dropped from analysis, so the same screen isn't paid for twice). Rewrites manifest.json
(a copy of the old one is kept as manifest.before-relabel.json).
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import watch  # noqa: E402
from PIL import Image  # noqa: E402


DUPLICATE_DELTA = 1.0   # mean pixel difference (0-255) below which two screens are the same picture


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("folder")
    p.add_argument("--teams", required=True, help='the game\'s two teams, comma-separated')
    args = p.parse_args()
    folder = Path(args.folder)
    teams = [t.strip() for t in args.teams.split(",") if t.strip()]
    manifest = json.loads((folder / "manifest.json").read_text())
    shutil.copy(folder / "manifest.json", folder / "manifest.before-relabel.json")
    by_file = {e["file"]: e for e in manifest}

    for e in manifest:   # titles misread with a stray letter ("y BOX SCORE") were filed as "other"
        if e["kind"] == "other" and "box score" in " ".join(e.get("header", "").lower().split()):
            e["kind"] = "box_score"
    for e in manifest:
        if e["kind"] != "team_stats" or e.get("hscroll") == "grafted":
            continue
        img = Image.open(folder / e["file"]).convert("RGB")
        w, h = img.size
        pill = img.crop((int(w * 0.08), int(h * 0.222), int(w * 0.24), int(h * 0.256))).convert("L")
        e["team"] = watch.read_team(pill, teams)
    for e in manifest:
        if e.get("hscroll") == "grafted":
            e["team"] = by_file[e["grafted_from"][0]]["team"]

    # Later repeats of a screen (same team/category/scroll position and visually the same picture)
    # are ignored. Compared by image, not OCR text, which varies between identical frames.
    kept = []
    for e in manifest:
        e.pop("ignore", None)
        if e["kind"] == "other" or e.get("hscroll") == "grafted":
            continue
        key = (e["kind"], e["team"], e["category"], e.get("hscroll"))
        sig = watch.signature(Image.open(folder / e["file"]).convert("RGB"))
        if any(k == key and watch.delta(sig, s) < DUPLICATE_DELTA for k, s in kept):
            e["ignore"] = True
        else:
            kept.append((key, sig))
    # a grafted composite is dropped if either of its source views was
    ignored = {e["file"] for e in manifest if e.get("ignore")}
    for e in manifest:
        if e.get("hscroll") == "grafted" and ignored & set(e["grafted_from"]):
            e["ignore"] = True

    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2))
    for e in manifest:
        flag = "ignored" if e.get("ignore") else ""
        print("%-48s %-18s %-14s %-9s %s" % (e["file"], e["team"], e["category"], e.get("hscroll") or "", flag))


if __name__ == "__main__":
    main()
