#!/usr/bin/env python3
"""Tong hop ket qua M5 tu cac thu muc run*/result.txt (stdlib only)."""
from __future__ import annotations

import csv
import statistics
import sys
from pathlib import Path


def parse_result(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def load_rows(root: Path, load: str) -> list[dict]:
    rows: list[dict] = []
    load_dir = root / load
    if not load_dir.is_dir():
        return rows
    for cond_dir in sorted(load_dir.glob("C*")):
        cond = cond_dir.name
        vals: list[float] = []
        recs: list[float] = []
        drops: list[float] = []
        for run_dir in sorted(cond_dir.glob("run*")):
            rf = run_dir / "result.txt"
            if not rf.exists():
                continue
            p = parse_result(rf)
            if p.get("value"):
                try:
                    vals.append(float(p["value"]))
                except ValueError:
                    pass
            if p.get("records"):
                try:
                    recs.append(float(p["records"]))
                except ValueError:
                    pass
            if p.get("drops"):
                try:
                    drops.append(float(p["drops"]))
                except ValueError:
                    pass
        if not vals:
            continue
        mean = statistics.mean(vals)
        std = statistics.stdev(vals) if len(vals) > 1 else 0.0
        rows.append(
            {
                "load": load,
                "condition": cond,
                "mean": mean,
                "std": std,
                "n_runs": len(vals),
                "records_mean": statistics.mean(recs) if recs else "",
                "drops_mean": statistics.mean(drops) if drops else "",
            }
        )
    if not rows:
        return rows
    base = next((r["mean"] for r in rows if r["condition"] == "C0"), None)
    for r in rows:
        if base and base != 0:
            r["overhead_pct"] = (r["mean"] - base) / base * 100.0
        else:
            r["overhead_pct"] = 0.0 if r["condition"] == "C0" else ""
    return rows


def main() -> None:
    root = Path(sys.argv[1])
    fieldnames = [
        "load",
        "condition",
        "mean",
        "std",
        "n_runs",
        "records_mean",
        "drops_mean",
        "overhead_pct",
    ]
    all_rows: list[dict] = []
    for load in ("T1", "T2", "T3", "T4", "T3-R", "T4-R"):
        all_rows.extend(load_rows(root, load))
    for load_dir in sorted(root.glob("T*-R*")):
        if load_dir.is_dir():
            all_rows.extend(load_rows(root, load_dir.name))
    w = csv.DictWriter(sys.stdout, fieldnames=fieldnames, lineterminator="\n")
    w.writeheader()
    for row in all_rows:
        w.writerow(row)


if __name__ == "__main__":
    main()
