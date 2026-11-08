#!/usr/bin/env python3
"""Turns a run of perf-on-tv.sh into one table per opening.

    python3 -I perf-report.py <out-dir>

Reads <out-dir>/runs.txt (launch time, CPU and memory of surface-manager per opening)
and <out-dir>/novos-perf.ini (the lines of lib/ui/PerfProbe.qml), and writes
<out-dir>/report.md. Times are ms after the launch request; the clock is the TV's.
"""

import pathlib
import re
import sys

CLOCK_TICKS = 100          # USER_HZ of the TV's kernel
MARKS = ["window.create", "launch", "exit", "foreground", "glass.picture", "open.animation", "open.done",
         "script", "loader.subpages", "loader.flow", "loader.settings", "close"]


def read_log(path):
    """The log= value of the QSettings ini file, unescaped."""
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("log="):
            value = line[4:]
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
            value = re.sub(r"\\x([0-9a-fA-F]{1,4})", lambda m: chr(int(m.group(1), 16)), value)
            value = (value.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"')
                     .replace("\\\\", "\\"))
            return [entry for entry in value.split("\n") if entry.strip()]
    return []


def read_runs(path):
    runs = []
    for line in path.read_text().splitlines():
        fields = dict(part.split("=", 1) for part in line.split() if "=" in part)
        if "launch" in fields:
            runs.append(fields)
    return runs


def parse(lines):
    entries = []
    for line in lines:
        parts = line.split(" ")
        if not parts[0].isdigit():
            continue
        entries.append((int(parts[0]), parts[1], parts[2:]))
    return entries


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "| " + " | ".join("---" for _ in head) + " |"]
    out += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    return "\n".join(out)


def report_open(run, entries):
    start = int(run["launch"])
    stop = int(run["stop"])
    mine = [entry for entry in entries if start - 500 <= entry[0] <= stop + 3000]
    wall = max(1, stop - start)
    cpu = int(run.get("cpu_ticks", 0)) * 1000 / CLOCK_TICKS / wall * 100
    out = [f"### {run['scenario']} #{run['open']} (page {run.get('page', 'none')})", ""]
    out.append(f"surface-manager: CPU {cpu:.0f} % of one core over {wall} ms, RSS "
               f"{run.get('rss_before', '?')} → {run.get('rss_open', '?')} → {run.get('rss_after', '?')} kB")
    out.append("")

    marks = []
    for time, kind, rest in mine:
        if kind == "mark" and rest and (rest[0] in MARKS or rest[0].startswith("loader.")):
            marks.append((rest[0], time - start, " ".join(rest[1:])))
    if marks:
        out += ["Timeline (ms after launch request):", "",
                table(["mark", "ms", "detail"], marks), ""]

    segments = []
    for time, kind, rest in mine:
        if kind == "segment":
            fields = dict(part.split("=", 1) for part in rest[1:] if "=" in part)
            segments.append((rest[0], fields.get("ms"), fields.get("fps"), fields.get("maxgap"),
                             fields.get("over34"), fields.get("over50"), fields.get("over100")))
    if segments:
        out += ["Frames per phase:", "",
                table(["phase", "ms", "fps", "max gap", ">34", ">50", ">100"], segments), ""]

    # The script's end and the window's exit each write totals: add them up.
    summed = {}
    for time, kind, rest in mine:
        if kind == "total":
            fields = dict(part.split("=", 1) for part in rest[1:] if "=" in part)
            entry = summed.setdefault(rest[0], [0, 0, 0])
            entry[0] += int(fields.get("n", 0))
            entry[1] += int(fields.get("sum", 0))
            entry[2] = max(entry[2], int(fields.get("max", 0)))
    totals = [(name, n, total, most, f"{total / max(1, n):.1f}") for name, (n, total, most) in summed.items()]
    totals.sort(key=lambda row: -row[2])
    if totals:
        out += ["Costs (ms):", "", table(["path", "n", "sum", "max", "avg"], totals), ""]

    counted = {}
    for time, kind, rest in mine:
        if kind == "count" and len(rest) > 1:
            counted[rest[0]] = counted.get(rest[0], 0) + int(rest[1])
    if counted:
        out += ["Counts:", "", table(["what", "n"], sorted(counted.items())), ""]

    slow = [(time - start, rest[1], rest[0], " ".join(rest[2:])) for time, kind, rest in mine
            if kind == "cost" and len(rest) > 1]
    slow.sort(key=lambda row: -int(row[1]))
    if slow:
        out += ["Slowest single costs:", "", table(["at", "ms", "path", "detail"], slow[:20]), ""]

    gaps = [(time - start, rest[0], " ".join(rest[1:])) for time, kind, rest in mine if kind == "gap"]
    if gaps:
        out += ["Frame gaps of 50 ms and more:", "", table(["at", "ms", "phase"], gaps[:40]), ""]
    return "\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = pathlib.Path(sys.argv[1])
    entries = parse(read_log(folder / "novos-perf.ini"))
    runs = read_runs(folder / "runs.txt")
    head = (folder / "runs.txt").read_text().splitlines()[0]
    text = [f"# Performance run ({head})", ""]
    for run in runs:
        text.append(report_open(run, entries))
    result = "\n".join(text) + "\n"
    (folder / "report.md").write_text(result)
    print(result)


if __name__ == "__main__":
    main()
