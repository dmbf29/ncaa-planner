# team_builder_csv

Screen recording of the roster table -> CSV for the Team Builder Unleashed extension
(teamcrafters.net), so a team can be used in Play Now. Separate from `tools/roster_video`; it only
imports a few OCR helpers from there and changes nothing in it. Local-only, macOS-only.

```bash
cd backend
tools/roster_video/venv/bin/python tools/team_builder_csv/video_to_csv.py \
  roster_test/ul_monroe_full.mov tmp/team_builder_csv/ul_monroe
node tools/team_builder_csv/check_ovr.js tmp/team_builder_csv/ul_monroe/players.json
```

Output in the out dir: `team_builder.csv` (upload this), `players.json` (with per-player flags), and
`frames/` + `frames.json` (cached; delete them or set `RESCAN=1` / `REOCR=1` to redo a step).

## Recording

Roster table, columns scrolled all the way right and back to the left, then down to the next page,
repeating until the last player. Keep the table's left edge in frame so the NAME column shows in the leftmost view.
Name column and the headers must be visible; the pane on the right doesn't matter.

## How it works

Keeps one frame per still moment, OCRs every row, and chains rows across frames: two consecutive
frames share columns and/or rows, so the vertical shift that makes the shared cells agree says
which row is which player. Each cell is read in ~25 frames and majority-voted.

## Limits

- First names are initials only (the table shows `B.Ficklin`); `jerseyNumber`, height, weight, handedness, hometown,
  skin tone and dev trait aren't in the table and are left blank (the importer keeps its template's values).
- Game position labels are mapped to the importer's: LEDG/REDG -> LE/RE, MIKE -> MLB, WILL -> LOLB, SAM -> ROLB.
- `check_ovr.js` compares the game's OVR to the importer's calculator. Expect a small, consistent gap (the calculator
  is an unofficial estimate); scatter beyond that means a misread rating.
- `ref/` holds copies of the importer's `csv-import.js` and sample CSV (GPL-3.0, jtrosclair/teamcrafters-classic-roster-importer).
