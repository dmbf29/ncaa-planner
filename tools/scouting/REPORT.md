# Game-tape prototype: Georgia Southern (etothebman) vs Kansas, 2026-10-31 (final 24-21 in GS's favor)

Pipeline (all local, Apple Vision via ocrmac, no AI API): ffmpeg 1 fps frames -> fast OCR finds "SELECT A PLAY" screens
(252 of 2,448 frames, ~78 separate play-call windows) -> accurate OCR of the card strip + scoreboard -> parse.
Run order: detect.py, ocrframes.py, parse.py, agg.py, calls.py (scripts expect frames in ./fps/NNNN.jpg).

Read straight off the play-call screen: quarter/clock/down&distance/score, play cards (formation, play name, PASS/RUN/KICK,
"N CALLS | X AVG YDS", "AVAILABLE IN N PLAYS"), formation/concept lists with usage and avg yds.

## Most-used plays (cumulative calls, avg yds)
Inside Zone (Gun Wing Slot Offset) 15 / 6.3 | Zone Option (Wing Tight Z) 11 / 12.0 | Dagger (Bunch Str Offset) 10 / 3.6 |
Drag Under (Doubles) 7 / 3.3 | Double Cross (Wing HB WK) 7 / 13.7 | RPO Glance Post 5 / 8.4 | MTN PA Wheel Over 4 / 11.0 | HB Angle 3 / 10.7

## Tendencies this game (partial: only plays visible on Recent/Favorites cards are caught)
- Almost everything is Gun (Wing / Wing HB WK / Doubles / Bunch Str Offset).
- Passing on 3rd & long: MTN PA Wheel Over (3&13, 3&20, 3&7), Double Cross (3&10, 3&12).
- Dagger is a 1st/2nd-down staple but only 3.6 avg yds; Double Cross / Zone Option are the efficient ones.
- Goes to the same few cards: Double Cross -> Drag Under -> Mtn PA Wheel Over repeat within a drive.
