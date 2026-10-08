#!/usr/bin/env python3
"""p99 tu pgbench --log hoac hey CSV."""
import sys
from pathlib import Path


def p99_from_sorted(vals):
    if not vals:
        return None
    vals.sort()
    i = int(0.99 * (len(vals) - 1))
    return vals[i]


def pgbench_log_p99(path: Path):
    lats = []
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0].isdigit():
            try:
                lats.append(float(parts[3]))
            except ValueError:
                pass
        elif "|" in line:
            try:
                lats.append(float(line.strip().split("|")[3]))
            except (IndexError, ValueError):
                pass
    return p99_from_sorted(lats)


def hey_csv_p99(path: Path):
    lats = []
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("HTTP") or line.startswith("response"):
            continue
        cols = line.split(",")
        if len(cols) >= 5:
            try:
                lats.append(float(cols[4]) * 1000)  # s -> ms
            except ValueError:
                pass
    return p99_from_sorted(lats)


def main():
    kind, p = sys.argv[1], Path(sys.argv[2])
    if kind == "pgbench":
        v = pgbench_log_p99(p)
    elif kind == "hey":
        v = hey_csv_p99(p)
    else:
        sys.exit(2)
    if v is None:
        print("")
    else:
        print(f"{v:.6f}")


if __name__ == "__main__":
    main()
