#!/usr/bin/env python3
"""Thong ke va ve hinh thi nghiem M4 tu CSV rec-export."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# nanosleep=35 (khoang dot), getppid=110 (khoang ngu)
BURN_NR = 35
SLEEP_NR = 110
COLS = ["dt_ns", "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_ns"]
STAT_COLS = ["n", "median_us", "p90_us", "p99_us"] + [
    f"{c.replace('_ns', '')}_median_us" for c in COLS
]


def us_stats(s: pd.Series) -> tuple[float, float, float]:
    if s.empty:
        return (float("nan"),) * 3
    a = s.dropna().astype(float) / 1000.0
    return float(a.median()), float(a.quantile(0.9)), float(a.quantile(0.99))


def load_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    for c in COLS + ["dt_ns"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def classify(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["kind"] = np.where(
        df["syscall_nr"] == BURN_NR,
        "burn",
        np.where(df["syscall_nr"] == SLEEP_NR, "sleep", "other"),
    )
    return df


def level_table(df: pd.DataFrame, level: str, baseline_medians: dict) -> list[dict]:
    rows = []
    for kind in ("burn", "sleep"):
        sub = df[df["kind"] == kind]
        row = {"experiment": df.attrs.get("experiment", ""), "level": level, "kind": kind}
        row["n"] = len(sub)
        med_dt, p90_dt, p99_dt = us_stats(sub["dt_ns"])
        row["median_us"] = med_dt
        row["p90_us"] = p90_dt
        row["p99_us"] = p99_dt
        for c in COLS:
            med, _, _ = us_stats(sub[c])
            key = c.replace("_ns", "")
            row[f"{key}_median_us"] = med
        base_dt = baseline_medians.get((kind, "dt"), float("nan"))
        base_cpu = baseline_medians.get((kind, "cpu"), float("nan"))
        row["ratio_dt"] = med_dt / base_dt if base_dt and not np.isnan(base_dt) else float("nan")
        row["ratio_cpu"] = row["cpu_median_us"] / base_cpu if base_cpu and not np.isnan(base_cpu) else float("nan")
        rows.append(row)
    return rows


def print_table(exp: str, level: str, rows: list[dict]) -> None:
    print(f"\n=== {exp} muc {level} ===")
    hdr = (
        f"{'kind':6} {'n':>6} {'med_dt':>10} {'p90_dt':>10} {'p99_dt':>10} "
        f"{'med_cpu':>10} {'med_rq':>10} {'med_vol':>10} {'r_dt':>8} {'r_cpu':>8}"
    )
    print(hdr)
    for r in rows:
        print(
            f"{r['kind']:6} {r['n']:6d} {r['median_us']:10.2f} {r['p90_us']:10.2f} {r['p99_us']:10.2f} "
            f"{r['cpu_median_us']:10.2f} {r['rq_median_us']:10.2f} {r['vol_median_us']:10.2f} "
            f"{r['ratio_dt']:8.3f} {r['ratio_cpu']:8.3f}"
        )


def boxplot_exp(outdir: Path, exp: str, by_level: dict[str, pd.DataFrame]) -> None:
    levels = sorted(by_level.keys(), key=lambda x: (str(x).isdigit(), x))
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    dt_data = []
    cpu_data = []
    labels = []
    for lv in levels:
        burn = by_level[lv]
        burn = burn[burn["syscall_nr"] == BURN_NR]
        if burn.empty:
            continue
        labels.append(str(lv))
        dt_data.append((burn["dt_ns"].dropna() / 1000.0).values)
        cpu_data.append((burn["cpu_ns"].dropna() / 1000.0).values)
    axes[0].boxplot(dt_data, labels=labels)
    axes[0].set_title(f"{exp} dt burn (us)")
    axes[0].set_xlabel("muc")
    axes[1].boxplot(cpu_data, labels=labels)
    axes[1].set_title(f"{exp} cpu burn (us)")
    axes[1].set_xlabel("muc")
    fig.tight_layout()
    fig.savefig(outdir / f"{exp}.png", dpi=120)
    plt.close(fig)


def run_experiment(
    outdir: Path,
    exp: str,
    csv_paths: dict[str, Path],
    summary_rows: list[dict],
) -> None:
    by_level: dict[str, pd.DataFrame] = {}
    baseline_medians: dict = {}
    for level in sorted(csv_paths.keys(), key=lambda x: (str(x).isdigit(), x)):
        df = classify(load_csv(csv_paths[level]))
        df.attrs["experiment"] = exp
        by_level[level] = df
    if "0" in by_level:
        for kind in ("burn", "sleep"):
            sub = by_level["0"][by_level["0"]["kind"] == kind]
            baseline_medians[(kind, "dt")] = float(sub["dt_ns"].median() / 1000.0) if len(sub) else float("nan")
            baseline_medians[(kind, "cpu")] = float(sub["cpu_ns"].median() / 1000.0) if len(sub) else float("nan")
    for level, df in by_level.items():
        rows = level_table(df, level, baseline_medians)
        print_table(exp, level, rows)
        summary_rows.extend(rows)
    boxplot_exp(outdir, exp, by_level)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", type=Path, required=True)
    ap.add_argument("--summary", type=Path, required=True)
    ap.add_argument("manifest", nargs="+", help="exp:level:csv ...")
    args = ap.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)

    grouped: dict[str, dict[str, Path]] = {}
    for item in args.manifest:
        exp, level, path = item.split(":", 2)
        grouped.setdefault(exp, {})[level] = Path(path)

    summary_rows: list[dict] = []
    for exp, paths in sorted(grouped.items()):
        run_experiment(args.outdir, exp, paths, summary_rows)

    pd.DataFrame(summary_rows).to_csv(args.summary, index=False)
    print(f"\nluu summary: {args.summary}")


if __name__ == "__main__":
    main()
