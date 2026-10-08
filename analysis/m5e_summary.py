#!/usr/bin/env python3
"""Gop summary M5e: T1-T3 tu m5d, T4 va T*-R* tu m5e OUTROOT."""
from __future__ import annotations

import csv
import sys
from pathlib import Path

# reuse m5_summarize load_rows
sys.path.insert(0, str(Path(__file__).resolve().parent))
from m5_summarize import load_rows  # noqa: E402


def main() -> None:
    m5e = Path(sys.argv[1])
    m5d = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("validation/m5d-20261008")
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
    rows: list[dict] = []
    for load in ("T1", "T2", "T3"):
        rows.extend(load_rows(m5d, load))
    for load in ("T4",):
        rows.extend(load_rows(m5e, load))
    for load_dir in sorted(m5e.glob("T*-R*")):
        if load_dir.is_dir():
            rows.extend(load_rows(m5e, load_dir.name))
    w = csv.DictWriter(sys.stdout, fieldnames=fieldnames, lineterminator="\n")
    w.writeheader()
    for row in rows:
        w.writerow(row)


if __name__ == "__main__":
    main()
