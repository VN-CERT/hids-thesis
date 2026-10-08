#!/usr/bin/env python3
"""Anh xa lượt đo M5e -> wall-clock; giao với cửa sổ git push (HH:MM local +07)."""
from __future__ import annotations

import datetime as dt
import sys
from pathlib import Path


def parse_result(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def pgbench_window(pb: Path) -> tuple[dt.datetime, dt.datetime] | None:
    lines = [l for l in pb.read_text(errors="replace").splitlines() if l and l[0].isdigit()]
    if not lines:
        return None
    t0 = int(lines[0].split()[4])
    t1 = int(lines[-1].split()[4])
    return dt.datetime.fromtimestamp(t0), dt.datetime.fromtimestamp(t1)


def hey_window(hey: Path) -> tuple[dt.datetime, dt.datetime] | None:
    offsets: list[float] = []
    for line in hey.read_text(errors="replace").splitlines()[1:]:
        if line.startswith("HTTP") or not line.strip():
            continue
        cols = line.split(",")
        if len(cols) >= 8:
            try:
                offsets.append(float(cols[7]))
            except ValueError:
                pass
    if not offsets:
        return None
    end = dt.datetime.fromtimestamp(hey.stat().st_mtime)
    dur = max(offsets) - min(offsets)
    if dur <= 0:
        dur = 60.0
    start = end - dt.timedelta(seconds=dur)
    return start, end


def run_window(run_dir: Path) -> tuple[dt.datetime, dt.datetime] | None:
    pb = run_dir / "pgbench_txn.log"
    hey = run_dir / "hey.csv"
    if pb.exists() and pb.stat().st_size > 50:
        w = pgbench_window(pb)
        if w:
            return w
    if hey.exists() and hey.stat().st_size > 50:
        return hey_window(hey)
    rf = run_dir / "result.txt"
    if rf.exists():
        end = dt.datetime.fromtimestamp(rf.stat().st_mtime)
        load = run_dir.parent.parent.name
        dur = 95 if load.startswith("T4") else 78
        return end - dt.timedelta(seconds=dur), end
    return None


def parse_hhmm(s: str) -> dt.time:
    a, b = s.split(":")
    return dt.time(int(a), int(b))


def overlaps(
    start: dt.datetime, end: dt.datetime, wstart: dt.time, wend: dt.time
) -> bool:
    day = start.date()
    ws = dt.datetime.combine(day, wstart)
    we = dt.datetime.combine(day, wend)
    if we <= ws:
        we += dt.timedelta(days=1)
    return start < we and end > ws


def main() -> None:
    root = Path(sys.argv[1])
    windows_path = Path(sys.argv[2])
    windows: list[tuple[str, dt.time, dt.time, str]] = []
    for line in windows_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        name, t0, t1 = parts[0], parts[1], parts[2]
        note = parts[3] if len(parts) > 3 else ""
        windows.append((name, parse_hhmm(t0), parse_hhmm(t1), note))

    out_lines = ["load\tcond\trun\tstart\tend\tnoise_windows"]
    for rf in sorted(root.rglob("result.txt")):
        run_dir = rf.parent
        load = run_dir.parent.parent.name
        if load == "step1-zstd" or not (
            load.startswith("T3-R") or load.startswith("T4-R") or load == "T4"
        ):
            continue
        cond = run_dir.parent.name
        run = run_dir.name
        w = run_window(run_dir)
        if not w:
            continue
        hit = [n for n, a, b, _ in windows if overlaps(w[0], w[1], a, b)]
        noise = ",".join(hit) if hit else ""
        out_lines.append(
            f"{load}\t{cond}\t{run}\t{w[0].strftime('%H:%M:%S')}\t{w[1].strftime('%H:%M:%S')}\t{noise}"
        )
        p = parse_result(rf)
        lines = rf.read_text().splitlines()
        filtered = [ln for ln in lines if not ln.startswith("noise=")]
        if noise:
            filtered.append(f"noise=1")
            filtered.append(f"noise_windows={noise}")
        else:
            filtered.append("noise=0")
        rf.write_text("\n".join(filtered) + "\n")

    map_path = root / "noise-run-map.tsv"
    map_path.write_text("\n".join(out_lines) + "\n")
    reruns = [ln for ln in out_lines[1:] if ln.split("\t")[-1]]
    (root / "noise-reruns.list").write_text("\n".join(reruns) + ("\n" if reruns else ""))
    print(map_path)
    print(f"reruns={len(reruns)}")


if __name__ == "__main__":
    main()
