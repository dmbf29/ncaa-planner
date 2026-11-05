#!/usr/bin/env python3
"""Read a Player Stats table off a Remote Play screenshot with Apple Vision (no AI API).

    backend/tools/roster_video/venv/bin/python tools/capture/read_table.py image.png

Needs `ocrmac` (macOS, Python 3.10+), which the roster-video tool's venv already has. The
game's tables are fixed-layout, so this reads them structurally instead of as free text:
find the column headers, find each row by the NAME column, then give every number to the
header it sits under. Returns [{"name": "J.Eugene Jr.", "cells": {"TAK": 2.0, "SACK": 0.0, ...}}].
"""
import json
import re
import statistics
import subprocess
import sys
import tempfile

from PIL import Image, ImageStat

# Column headers the game uses, longest first so "INT YDS" wins over "INT".
HEADERS = [
    "INT YDS", "INT AVG", "INT LG", "RAC AVG", "COMP%", "ASSISTS", "FMBREC", "FMBYDS", "FFUMB", "SOLO", "SACKS",
    "SACK", "BLOCK", "SFTY", "CYDA", "DEFL", "NAME", "RATING", "YARDS", "LONG", "COMP", "DROPS", "FUMB", "YPC",
    "ATT", "TAK", "TFL", "INT", "TD", "CAR", "AVG", "BTK", "YAC", "REC", "RAC", "20+",
]


def clean(text):
    return re.sub(r"[^A-Za-z0-9%+ ]", "", text).strip().upper()


# Every table the game shows has a fixed column order. Vision sometimes skips a header, so the order is used to
# put back the ones it left out (a missing TAK header would otherwise shift its numbers onto the next column).
LAYOUTS = [
    ["RATING", "YARDS", "TD", "INT", "LONG", "SACKS", "COMP", "ATT", "COMP%", "YPC"],
    ["CAR", "YARDS", "AVG", "TD", "FUMB", "BTK", "YAC", "LONG", "20+"],
    ["REC", "YARDS", "AVG", "TD", "RAC", "RAC AVG", "LONG", "DROPS"],
    ["SOLO", "ASSISTS", "TAK", "TFL", "SACK", "INT", "INT YDS", "INT AVG", "INT LG", "DEFL", "CYDA", "FFUMB", "FMBREC", "FMBYDS", "BLOCK", "SFTY", "TD"],
]


def fill_missing_headers(stat_cols):
    """[(label, x)] with any header Vision skipped put back between the ones it found, positioned evenly."""
    labels = [label for label, _x in stat_cols]
    best = None
    for layout in LAYOUTS:
        position = -1
        indices = []
        for label in labels:
            try:
                position = layout.index(label, position + 1)
            except ValueError:
                indices = None
                break
            indices.append(position)
        if indices is not None and (best is None or len(indices) > len(best[1])):
            best = (layout, indices)
    if best is None:
        return stat_cols
    layout, indices = best
    filled = []
    for n, ((label, x), index) in enumerate(zip(stat_cols, indices)):
        if n > 0:
            prev_index, prev_x = indices[n - 1], stat_cols[n - 1][1]
            gap = index - prev_index
            for step in range(1, gap):
                filled.append((layout[prev_index + step], prev_x + (x - prev_x) * step / gap))
        filled.append((label, x))
    return filled


# Vision's usual mistakes on the header font, plus the sort arrow it reads as a stray letter ("v RATING").
HEADER_FIXES = {"AUG": "AVG", "AVC": "AVG", "YDS": "YARDS", "INT YOS": "INT YDS", "SACKS": "SACKS"}


def header_label(text):
    """The known column header this text is, or None. Tolerates a sort arrow and one-letter misreads."""
    label = re.sub(r"\bAUG\b", "AVG", clean(text))
    label = HEADER_FIXES.get(label, label)
    if label in HEADERS:
        return label
    words = label.split()
    for start in range(1, len(words)):  # drop a leading sort arrow Vision read as a stray character: "+ RATING", "V RATING"
        suffix = " ".join(words[start:])
        if len(words[0]) == 1 and suffix in HEADERS:
            return suffix
    return None


def vision_items(img):
    """[(text, cx, cy, h)] in pixels, y measured from the top."""
    from ocrmac import ocrmac
    w, h = img.size
    items = []
    for text, _confidence, (x, y, bw, bh) in ocrmac.OCR(img, recognition_level="accurate").recognize():
        items.append((text, (x + bw / 2) * w, (1 - (y + bh / 2)) * h, bh * h, x * w, (x + bw) * w))
    return items


def find_header_row(items):
    """Items on the line holding the most known column headers (the table's header row)."""
    candidates = [it for it in items if header_label(it[0]) or re.fullmatch(r"(INT|RAC) ?(YDS|AVG|LG)", clean(it[0]))]
    if not candidates:
        return None, []
    best_row = max(candidates, key=lambda c: sum(abs(o[2] - c[2]) < c[3] * 0.8 for o in candidates))
    row = sorted((it for it in candidates if abs(it[2] - best_row[2]) < best_row[3] * 0.8), key=lambda it: it[1])
    return best_row[2], row


def split_columns(header_row):
    """Header items -> [(label, center_x)]; merges two-word headers Vision returned as two boxes."""
    cols, i = [], 0
    while i < len(header_row):
        text, cx, _cy, _h, left, right = header_row[i]
        label = header_label(text) or clean(text)
        if i + 1 < len(header_row):
            nxt = header_row[i + 1]
            joined = clean(text + " " + nxt[0])
            if joined in HEADERS and nxt[4] - right < (right - left) * 0.9:
                label, cx, i = joined, (left + nxt[5]) / 2, i + 1
        cols.append((label, cx))
        i += 1
    return cols


def fix_name(text):
    """Vision reads the suffix "III" as "Ill" (lowercase L); "II" likewise."""
    name = re.sub(r"^0(?=\.)", "O", text.strip())  # the initial "O" comes back as a zero
    return re.sub(r"\s(?:I[Il]l|l{3})$", " III", re.sub(r"\s(?:I[Il]|l{2})$", " II", name)) if re.search(r"\s[Il]{2,3}$", name) else name


def parse_number(text):
    t = text.strip().replace("O", "0").replace("o", "0").replace(",", "")
    if t.endswith("%"):
        t = t[:-1]
    try:
        return float(t)
    except ValueError:
        return None


def read_row_strip(img, y, pitch, left_x, right_x):
    """Vision items for just one table row. Cropped to a single line, Vision finds the lone digits (a 0 among
    other 0s) that it skips on the full screen."""
    from ocrmac import ocrmac
    top, bottom = max(0, int(y - pitch * 0.42)), int(y + pitch * 0.42)
    strip = img.crop((max(0, int(left_x)), top, int(right_x), bottom))
    items = []
    for text, _confidence, (x, _y, bw, _bh) in ocrmac.OCR(strip, recognition_level="accurate").recognize():
        items.append((text, left_x + (x + bw / 2) * strip.width))
    return items


# (width, height, enlargement) multiples of the cell size to try: Vision is erratic on a lone digit and
# finds it in some crops and not others.
CELL_CROPS = [(1.0, 1.0, 1), (2.0, 1.0, 1), (3.0, 1.4, 1), (1.5, 2.0, 1), (2.0, 1.4, 2), (3.0, 1.0, 2), (1.0, 1.0, 3)]


# Whether Vision sees a lone digit can hinge on a pixel of crop size, so a cell it still can't find is retried
# with the crop nudged and resized: (height multiple, vertical shift in cell heights).
CELL_RETRIES = [(1.0, 0.0), (1.15, 0.0), (0.9, 0.0), (1.0, 0.12), (1.0, -0.12), (1.3, 0.0)]


def read_cell(img, cx, cy, half_width, half_height):
    for tall, shift in CELL_RETRIES:
        value = read_cell_once(img, cx, cy + shift * half_height, half_width, half_height * tall)
        if value is not None:
            return value
    return None


def read_cell_once(img, cx, cy, half_width, half_height):
    """Last resort for one cell: read crops of several sizes around it and take the first number Vision finds
    near its centre, then tesseract (digits only) on a padded crop."""
    from ocrmac import ocrmac
    for wide, tall, scale in CELL_CROPS:
        left, top = max(0, int(cx - half_width * wide)), max(0, int(cy - half_height * tall))
        crop = img.crop((left, top, int(cx + half_width * wide), int(cy + half_height * tall)))
        if scale > 1:
            crop = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
        for text, _confidence, (x, y, bw, bh) in ocrmac.OCR(crop, recognition_level="accurate").recognize():
            item_x = left + (x + bw / 2) * crop.width / scale
            item_y = top + (1 - (y + bh / 2)) * crop.height / scale
            value = parse_number(text)
            if value is not None and abs(item_x - cx) < half_width * 0.9 and abs(item_y - cy) < half_height * 0.9:
                return value
    crop = img.crop((max(0, int(cx - half_width)), max(0, int(cy - half_height)), int(cx + half_width), int(cy + half_height)))
    # A lone glyph with no surroundings is ignored unless it sits in a generous empty margin.
    for scale in (4, 3, 6):
        big = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
        canvas = Image.new("RGB", (big.width + 400, big.height + 400), tuple(int(v) for v in ImageStat.Stat(big).mean[:3]))
        canvas.paste(big, (200, 200))
        for text, _confidence, _box in ocrmac.OCR(canvas, recognition_level="accurate").recognize():
            value = parse_number(text)
            if value is not None:
                return value
    gray = crop.convert("L").resize((crop.width * 4, crop.height * 4), Image.LANCZOS)
    canvas = Image.new("L", (gray.width + 80, gray.height + 80), int(ImageStat.Stat(gray).mean[0]))
    canvas.paste(gray, (40, 40))
    canvas = Image.eval(canvas, lambda v: 255 - v) if ImageStat.Stat(canvas).mean[0] < 128 else canvas
    with tempfile.NamedTemporaryFile(suffix=".png") as f:
        canvas.save(f.name)
        out = subprocess.run(["tesseract", f.name, "stdout", "--psm", "7", "-c", "tessedit_char_whitelist=0123456789.%"],
                             capture_output=True, text=True).stdout
    return parse_number(out)


def read_table(img, fill_missing=True):
    items = vision_items(img)
    header_y, header_row = find_header_row(items)
    if header_y is None:
        return None
    cols = split_columns(header_row)
    name_col = next(((l, x) for l, x in cols if l == "NAME"), None)
    stat_cols = fill_missing_headers([(l, x) for l, x in cols if l != "NAME"])
    if not stat_cols:
        return None

    first_stat_x = min(x for _, x in stat_cols)
    width, height = img.size
    # A whole Remote Play window has artwork and button hints under the table; the table frame ends at 83.5% of the height.
    # (Cropped images, like the name-grafted composites, hold nothing but the table.)
    table_bottom = height * 0.835 if width / height < 1.8 else height
    # Rows are located by the name items: left of the first stat column, below the header.
    names = sorted((it for it in items if header_y + it[3] < it[2] < table_bottom and it[1] < first_stat_x - 40 and re.search(r"[A-Za-z]{2}", it[0])),
                   key=lambda it: it[2])
    if not names:
        return []
    col_gap = statistics.median([b[1] - a[1] for a, b in zip(stat_cols, stat_cols[1:])] or [160])
    pitch = statistics.median([b[2] - a[2] for a, b in zip(names, names[1:])]) if len(names) > 1 else names[0][3] * 3
    rows = []
    for name in names:
        cells = {}
        for text, cx, cy, h, _l, _r in items:
            if abs(cy - name[2]) > pitch * 0.4 or cx < first_stat_x - 40:
                continue
            value = parse_number(text)
            if value is None:
                continue
            label, label_x = min(stat_cols, key=lambda c: abs(c[1] - cx))
            if abs(label_x - cx) > col_gap * 0.5:  # not under any column: the player card beside the table ("90 OVR")
                continue
            cells[label] = value
        refilled = []
        if fill_missing and len(cells) < len(stat_cols):
            strip_items = read_row_strip(img, name[2], pitch, first_stat_x - 60, stat_cols[-1][1] + 60)
            for text, cx in strip_items:
                value = parse_number(text)
                label = min(stat_cols, key=lambda c: abs(c[1] - cx))[0]
                if value is not None and label not in cells and abs(dict(stat_cols)[label] - cx) < col_gap * 0.45:
                    cells[label] = value
                    refilled.append(label)
            for label, cx in stat_cols:
                if label not in cells:
                    value = read_cell(img, cx, name[2], col_gap * 0.3, pitch * 0.34)
                    if value is not None:
                        cells[label] = value
                        refilled.append(label)
        rows.append({"name": fix_name(name[0]), "cells": cells, "expected_cells": len(stat_cols), "refilled": refilled})
    return rows


if __name__ == "__main__":
    image = Image.open(sys.argv[1]).convert("RGB")
    print(json.dumps(read_table(image), indent=1))
