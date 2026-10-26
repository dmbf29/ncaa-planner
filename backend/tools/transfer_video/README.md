# transfer_video

Reads a screen recording of the "players leaving" screen (NAME / POS / YEAR / OVR / REASON / PERSUASION CHANCE)
and lists every player whose reason starts with **Transfer** or **Leaving** (the game uses both for a player who is entering the portal), with the full name, position, class, overall and the
attribute tiles in the right-hand pane. Pro Draft / Graduation / Staying rows are ignored. Runs locally (Apple Vision
OCR via `ocrmac`), no AI API. It borrows the OCR and name helpers from `tools/roster_video` and uses its venv
(see that README for setup).

```bash
roster_video/venv/bin/python transfer_video/extract.py recording.mov > transfers.json
```

Record each team's list with the highlight stepping through the rows (hold the stick down). The team is read from the
banner at the top. Output: `{ "players": [...], "unhighlighted": [...] }`. `players` carry `team`, `first_name`,
`last_name`, `position`, `class_year`, `overall`, `transfer_reason` and whichever of `speed`, `acceleration`,
`agility`, `change_of_direction`, `strength`, `awareness` appear on the tiles (the other tiles, e.g. Throw Power, aren't
tracked). `unhighlighted` are Transfer rows seen in the table but never selected (the highlight can jump two rows):
only initial + last name, class and overall, so they can be flagged but not have stats updated.

Progress lines (`progress scan|read done total`) go to stderr like roster_video. Layout is proportional to the frame.
