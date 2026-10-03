# roster_video

Turns a screen recording of the in-game roster screen into the roster JSON the
importer expects — full first names included. Runs entirely on your Mac (OCR via
Apple Vision), so there are no AI API costs.

Local-only, macOS-only (`ocrmac` uses Apple's Vision framework). The Rails
endpoint refuses to run outside `development`.

## Setup

Needs Python 3.10+ (the system/pyenv 3.8 is too old for `ocrmac`).

```bash
cd backend/tools/roster_video
/opt/homebrew/bin/python3.14 -m venv venv
venv/bin/pip install -r requirements.txt
```

The venv lives at `tools/roster_video/venv` (gitignored). Rails looks for
`venv/bin/python` there; set `ROSTER_VIDEO_PYTHON` to use a different one.

## Recording

- Open the team's **roster** page, sorted how you like, scrolled to the top.
- Record just that area (QuickTime "New Screen Recording" → drag a region). Keep
  the whole table **and** the right-hand player pane in frame, starting from the
  column headers.
- Hold the left stick down to move through the whole roster. The d-pad works too
  but is slower; both read the same. A player needs to stay highlighted for
  roughly a quarter second to be picked up, which holding the stick does.
- Stop once the last player has been highlighted.

Any column layout works (it reads the headers from the first frame), including
the NIL/DEV view. NIL and DEV are ignored: `nil_amount` is always `""`.

## Using it

**In the app (normal path):** open a team's roster page → Import → drop the video
onto the box (or "choose a video"). It reads the video in about 15 seconds, fills
in the JSON and goes straight to the usual review screen. Several tabs can run at
once; only 2 videos process at a time (`ROSTER_VIDEO_CONCURRENCY`), the rest wait.

**Batch (a folder of clips):**

```bash
cd backend
bin/rails roster_import:from_videos            # dry run: reads every clip, prints what would change
bin/rails db:backup:create                     # restorable with db:backup:restore
APPLY=1 bin/rails roster_import:from_videos    # writes
```

Options: `DIR` (default `video_test/`), `SEASON_ID` (default latest). Each clip is
identified by the **team name on screen**, never the filename (it's matched to a
College, tolerating an OCR slip, and skipped if unrecognised or ambiguous). Several
clips of one team: the newest wins. Clips with fewer than 60 players read (a
truncated recording) are skipped. Matches and new players are written; **ambiguous
matches and anything the reader flagged are listed, not written** — resolve those
through the normal Import form. Extractions are cached in `tmp/roster_video/cache`,
so the `APPLY=1` run after a dry run is fast; a JSON report lands in
`tmp/roster_video/`.

**Wrong links.** Rosters imported before full first names existed were matched on last
name + first initial, which could attach a player to an unrelated Student ("Trevor
Calloway" stored as last year's "Trace Calloway"). The batch report lists these as
`probable wrong link`: a "new" row for which the roster already has one player with
the same last name, position, class and all seven ratings under a different first
name. They are never written as new players (that would duplicate them). To fix
them, back up and run `APPLY=1 REPAIR_LINKS=1 bin/rails roster_import:from_videos`:
the existing row gets a new Student with the video's name, and the old Student keeps
their real history. `bin/rails roster_import:audit_links` is a read-only check for
teams without a clip (links whose class, side of the ball or overall jump look
implausible).

**From the command line:**

```bash
venv/bin/python extract.py team.mov > team.json
```

Progress (`progress scan …` / `progress read …`) and a summary go to stderr; the
JSON goes to stdout.

## How it works

1. **Headers:** OCRs the first frame to find the x-position of each column.
2. **Scan:** walks the video and, each time the right-hand pane holds still for
   4 frames, keeps small crops of the pane and of the highlighted row.
3. **Read** (in parallel worker processes): the pane gives the full first and last
   name, position, jersey number and class; the highlighted row gives the stats.
   Each stat is read from the whole row *and* from a window around its column,
   re-read at other scales until the two methods agree (reading the whole row alone
   lets OCR merge or drop neighbouring numbers). The window must include the
   neighbouring columns: an isolated one-cell crop gets its orientation guessed
   wrong by Apple's OCR -- `66` reads as `99` and `60▲` as `09`, at every scale.
4. **Checks:** when the row and pane disagree on a name (e.g. `T.Powell` vs
   `FOWELL`), both are re-read at other scales and the majority wins — row reads
   count double, since the pane's coloured text on a team-coloured background is
   what slips on low-contrast teams. A player gets a `needs_review` list if the
   row and pane still disagree (name, position, class), a stat is missing, or no
   two reads of a stat agreed. The importer ignores that key; the form shows flagged players in an
   amber note on the review screen.

The output is `{ "players": [...] }` with `first_name`, `last_name`, `class_year`,
`position`, `overall`, `nil_amount`, `speed`, `acceleration`, `agility`,
`change_of_direction`, `strength`, `awareness`, plus `jersey`.

## Gotchas

- **Layout is proportional.** Crop positions are fractions of the frame, so
  different recording sizes work, but the pane must stay on the right ~21% of the
  frame and the table header at roughly 27–37% down. If you change the recorded
  region a lot and a clip finds 0 players, start there (`pane_box` and
  `find_headers` in `extract.py`).
- **Wrong-team uploads aren't detected.** It reads whatever team is on screen.
- **OCR slips** are caught by the cross-checks and 3 known fixes: Cyrillic/Latin
  lookalike letters, `O`↔`Q` in positions (`snap_position`), and `III`/`Jr.`
  suffixes. Check the amber "double-check" list on the review screen.
- **Tuning:** `ROSTER_VIDEO_WORKERS` sets processes per video (default: half the
  CPU cores).
- **Import side:** with full first names in the paste, `RosterImport::Matcher`
  uses them to tell apart players who share an initial and last name, and
  `RosterImport::CommitService` upgrades matched students stored as only an initial.
