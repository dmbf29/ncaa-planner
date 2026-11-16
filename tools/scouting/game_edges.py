"""Finds where the plays after touchdowns end and where the game itself ends in a stream recording, from the scoreboard bar.
Writes <recording>.edges.json next to the recording (it needs the .scout.json made by scout.py):

  conversions: [{score_time, end, source}]  one per touchdown in the scouting report. After the touchdown the bar's centre slot
                         shows "PAT" while the kick is set up and "PAT GOOD" / "2-PT GOOD" (or a no-good label) when the play is
                         over; `end` is the second just after the last of those labels. If no label was readable, `end` is
                         the second the KICKOFF label shows (source "kickoff"). Neither (end of a half, overtime, the last play
                         of the game): `end` is null.
  final: {end, source} or null  where the game is over: the end of the "Final" scoreboard card shown after the last play, or
                         the start of the first post-game screen (Post Game, Player of the Game) when the card never showed.
                         Anything after it is menus (and their music). Highlights and uploads can stop at `end`. Null when the
                         recording stops before then.

    backend/tools/roster_video/venv/bin/python tools/scouting/game_edges.py streams/etothebman/2026-11-08_22-01-30.ts
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import warnings

warnings.filterwarnings("ignore")

from PIL import Image  # noqa: E402

CONVERSION_WINDOW = 75  # seconds after the touchdown to look for the conversion
BOARD_CROP = (250, 600, 1030, 700)  # the scoreboard bar and the "Final" card, at 1280x720
RESULT = re.compile(r"\bPAT\b|PAT\s?(NO\s?)?GOOD|2.?PT|NO\s?GOOD|FAILED|CONVERSION|BLOCKED|MISSED", re.I)
KICKOFF = re.compile(r"KICK\s?OFF|CKOFF|ICKOF|KOFF", re.I)
FINAL = re.compile(r"\bFinal\b", re.I)
POST_GAME = re.compile(r"POST\s?GAME|OF THE GAME|RETURN TO HUB|VIEW HIGHLIGHTS", re.I)  # Vision reads "PLAYER" as "PLAVEII" at times
TOP_CROP = (0, 0, 1280, 130)  # where those screens print their title, at 1280x720
LABEL_GAP = 4  # seconds the label may flicker out of the read before it counts as gone
RESULT_TAIL = 1.5  # seconds kept after the last result label
KICKOFF_TAIL = 1.0
END_SCAN_STEP = 3


def ocr(img, level):
    from ocrmac import ocrmac
    return " ".join(item[0] for item in ocrmac.OCR(img.resize((img.width * 2, img.height * 2)), recognition_level=level).recognize())


def frames(path, start, length, step, tmp, crop):
    """{second: image} for `length` seconds from `start`, one frame every `step` seconds, cut to `crop` of the 1280x720 frame.
    A recording whose last seconds can't be decoded gives what was read."""
    subprocess.run(
        ["ffmpeg", "-nostdin", "-v", "error", "-ss", str(start), "-t", str(length), "-i", path, "-vf", "fps=1/%d,scale=1280:720,crop=%d:%d:%d:%d" % (
            step, crop[2] - crop[0], crop[3] - crop[1], crop[0], crop[1]), "-q:v", "3", os.path.join(tmp, "%05d.jpg")],
        check=False, stderr=subprocess.DEVNULL,
    )
    return {start + i * step: Image.open(os.path.join(tmp, f)) for i, f in enumerate(sorted(os.listdir(tmp)))}


def conversion_end(path, score_time):
    with tempfile.TemporaryDirectory() as tmp:
        labelled, kickoff = [], None
        for t, img in sorted(frames(path, score_time, CONVERSION_WINDOW, 1, tmp, BOARD_CROP).items()):
            text = ocr(img, "fast")
            if RESULT.search(text):
                labelled.append(t)
            elif kickoff is None and KICKOFF.search(text):
                kickoff = t
        if labelled:
            run_end = labelled[0]
            for t in labelled[1:]:
                if t - run_end > LABEL_GAP:
                    break
                run_end = t
            return {"score_time": score_time, "end": run_end + RESULT_TAIL, "source": "label"}
        if kickoff is not None:
            return {"score_time": score_time, "end": kickoff + KICKOFF_TAIL, "source": "kickoff"}
        return {"score_time": score_time, "end": None, "source": None}


def game_end(path, after, duration):
    """{end, source} for where the game is over, scanning from `after` and stopping at the first sign of it, or None."""
    with tempfile.TemporaryDirectory() as bars, tempfile.TemporaryDirectory() as tops:
        bar_frames = frames(path, after, duration - after, END_SCAN_STEP, bars, BOARD_CROP)
        top_frames = frames(path, after, duration - after, END_SCAN_STEP, tops, TOP_CROP)
        card_seen = False
        for t in sorted(bar_frames):
            if t in top_frames and POST_GAME.search(ocr(top_frames[t], "fast")):
                return {"end": t, "source": "post game screen"}
            on_card = bool(FINAL.search(ocr(bar_frames[t], "accurate")))
            if card_seen and not on_card:
                return {"end": t, "source": "final card"}
            card_seen = card_seen or on_card
    return None


if __name__ == "__main__":
    recording = sys.argv[1]
    report = json.load(open(re.sub(r"\.ts$", "", recording) + ".scout.json"))
    scoring = report["scoring"]
    conversions = [conversion_end(recording, play["time"]) for play in scoring if play["kind"] == "Touchdown"]
    final = game_end(recording, scoring[-1]["time"], report["duration_s"]) if scoring else None
    out = re.sub(r"\.ts$", "", recording) + ".edges.json"
    with open(out, "w") as fh:
        json.dump({"file": os.path.abspath(recording), "conversions": conversions, "final": final}, fh, indent=1)
    print(f"{len(conversions)} touchdowns ({sum(1 for c in conversions if c['end'])} with an end), game end {final} -> {out}")
