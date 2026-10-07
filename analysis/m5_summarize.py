#!/usr/bin/env python3
"""Tong hop ket qua M5 tu cac thu muc run*/result.txt."""
from __future__ import annotations

import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def parse_result(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def load_load(root: Path, load: str) -> pd.DataFrame:
    rows = []
    for cond_dir in sorted((root / load).glob("C*")):
        cond = cond_dir.name
        vals = []
        recs = []
        drops = []
        for run_dir in sorted(cond_dir.glob("run*")):
            rf = run_dir / "result.txt"
            if not rf.exists():
                continue
            p = parse_result(rf)
            if "value" in p and p["value"]:
                try:
                    vals.append(float(p["value"]))
                except ValueError:
                    pass
            if "records" in p:
                try:
                    recs.append(float(p["records"]))
                except ValueError:
                    pass
            if "drops" in p:
                try:
                    drops.append(float(p["drops"]))
                except ValueError:
                    pass
        if not vals:
            continue
        rows.append(
            {
                "load": load,
                "condition": cond,
                "mean": float(np.mean(vals)),
                "std": float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0,
                "n_runs": len(vals),
                "records_mean": float(np.mean(recs)) if recs else float("nan"),
                "drops_mean": float(np.mean(drops)) if drops else float("nan"),
            }
        )
    return pd.DataFrame(rows)


def add_overhead(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df
    base = df[df["condition"] == "C0"]["mean"]
    b = float(base.iloc[0]) if len(base) else float("nan")
    df = df.copy()
    df["overhead_pct"] = (df["mean"] - b) / b * 100.0 if b else float("nan")
    return df


def main() -> None:
    root = Path(sys.argv[1])
    parts = []
    for load in ("T1", "T2", "T3", "T4"):
        if (root / load).exists():
            parts.append(add_overhead(load_load(root, load)))
    if not parts:
        print("load,condition,mean,std,n_runs,records_mean,drops_mean,overhead_pct")
        return
    out = pd.concat(parts, ignore_index=True)
    print(out.to_csv(index=False))


if __name__ == "__main__":
    main()
