#!/usr/bin/env python3
"""Scout every finished recording under streams/ that has no report yet. Safe to run on a schedule (launchd, see below).

    backend/tools/roster_video/venv/bin/python tools/scouting/scout_watch.py [--dry-run]

A recording counts as finished once its file hasn't been written to for IDLE_MINUTES (streamlink writes continuously
while the stream is live). When one session produced several files (disconnects, duplicate recorders), only the
largest file within CLUSTER_MINUTES of its start is scouted and the rest get a .scout.skip marker. The recorder script
isn't touched. A lock file keeps overlapping runs from scouting the same game twice.
"""
import datetime
import glob
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

STREAMS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "streams")
IDLE_MINUTES = 10
CLUSTER_MINUTES = 15
MIN_BYTES = 50 * 1024 * 1024


def started_at(path):
    try:
        return datetime.datetime.strptime(os.path.basename(path)[:19], "%Y-%m-%d_%H-%M-%S")
    except ValueError:
        return None


def mark_skip(f, dry, covered_by=None):
    if not dry:
        with open(f[:-3] + ".scout.skip", "w") as marker:
            marker.write(f"{os.path.basename(covered_by)[:-3]}.scout.md\n" if covered_by else "")


def pending(channel_dir, dry=False):
    files = [f for f in sorted(glob.glob(os.path.join(channel_dir, "*.ts"))) if "_trimmed" not in f and started_at(f)]
    done = lambda f: os.path.exists(f[:-3] + ".scout.json") or os.path.exists(f[:-3] + ".scout.skip")
    idle = lambda f: time.time() - os.path.getmtime(f) > IDLE_MINUTES * 60
    big = [f for f in files if os.path.getsize(f) >= MIN_BYTES]
    for f in files:
        if f not in big and idle(f):
            mark_skip(f, dry)  # too short to be a game
    todo = []
    for f in big:
        if done(f) or not idle(f):
            continue
        rivals = [g for g in big if g != f and abs((started_at(g) - started_at(f)).total_seconds()) < CLUSTER_MINUTES * 60]
        bigger = [g for g in rivals if (os.path.getsize(g), g) > (os.path.getsize(f), f)]
        if bigger:
            mark_skip(f, dry, max(bigger, key=lambda g: (os.path.getsize(g), g)))  # a bigger file covers this session
            continue
        todo.append(f)
    return todo


def main():
    dry = "--dry-run" in sys.argv
    lock = os.path.join(STREAMS, ".scout.lock")
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 3 * 3600:
        print("another scout run is active")
        return
    todo = [f for d in sorted(glob.glob(os.path.join(STREAMS, "*/"))) for f in pending(d, dry)]
    if dry:
        print("\n".join(todo) or "nothing to scout")
        return
    open(lock, "w").close()
    try:
        from scout import scout_file
        for f in todo:
            print("scouting", f, flush=True)
            try:
                scout_file(f)
            except Exception as e:  # one bad recording shouldn't block the rest
                print("failed:", f, e, flush=True)
    finally:
        os.remove(lock)


if __name__ == "__main__":
    main()
