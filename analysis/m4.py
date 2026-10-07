#!/usr/bin/env python3
"""Thong ke va ve hinh thi nghiem M4 tu CSV rec-export."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# getppid=110 (khoang ngu). Khoang dot: nanosleep (35 arm) hoac clock_nanosleep (230 x86_64).
BURN_NRS = {35, 230}
SLEEP_NR = 110
E2_LEVEL_ORDER = ["Unlimited", "36000", "24000", "12000"]


def sort_levels(levels: list[str]) -> list[str]:
    if any(lv in E2_LEVEL_ORDER for lv in levels):
        return sorted(levels, key=lambda x: E2_LEVEL_ORDER.index(x) if x in E2_LEVEL_ORDER else 999)
    return sorted(levels, key=lambda x: (str(x).isdigit(), x))


def baseline_level_key(by_level: dict[str, pd.DataFrame], exp: str) -> str:
    if exp == "E2" and "Unlimited" in by_level:
        return "Unlimited"
    if "0" in by_level:
        return "0"
    return sort_levels(list(by_level.keys()))[0]
COLS = ["dt_ns", "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_ns"]
CORE_METRICS = ("dt", "cpu", "steal", "rq")
STAT_COLS = ["n", "median_us", "p90_us", "p99_us"] + [
    f"{c.replace('_ns', '')}_median_us" for c in COLS
]


def us_series_us(s: pd.Series) -> pd.Series:
    return s.dropna().astype(float) / 1000.0


def us_stats(s: pd.Series) -> tuple[float, float, float]:
    if s.empty:
        return (float("nan"),) * 3
    a = us_series_us(s)
    return float(a.median()), float(a.quantile(0.9)), float(a.quantile(0.99))


def us_stats_full(s: pd.Series) -> tuple[float, float, float, float]:
    """median, mean, p90, p99 (microseconds)."""
    if s.empty:
        return (float("nan"),) * 4
    a = us_series_us(s)
    return (
        float(a.median()),
        float(a.mean()),
        float(a.quantile(0.9)),
        float(a.quantile(0.99)),
    )


def steal_gt0_frac(sub: pd.DataFrame) -> float:
    if sub.empty or "steal_ns" not in sub.columns:
        return float("nan")
    s = sub["steal_ns"].dropna()
    if s.empty:
        return float("nan")
    return float((s.astype(float) > 0).sum()) / float(len(s))


def steal_total_ns(sub: pd.DataFrame) -> float:
    if sub.empty or "steal_ns" not in sub.columns:
        return float("nan")
    s = sub["steal_ns"].dropna().astype(float)
    if s.empty:
        return float("nan")
    return float(s.sum())


def load_csv(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    for c in COLS + ["dt_ns"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


def classify(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df["kind"] = np.where(
        df["syscall_nr"].isin(BURN_NRS),
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
        med_dt, mean_dt, p90_dt, p99_dt = us_stats_full(sub["dt_ns"])
        row["median_us"] = med_dt
        row["p90_us"] = p90_dt
        row["p99_us"] = p99_dt
        row["dt_mean_us"] = mean_dt
        row["dt_p90_us"] = p90_dt
        row["dt_p99_us"] = p99_dt
        for c in COLS:
            med, mean, p90, p99 = us_stats_full(sub[c])
            key = c.replace("_ns", "")
            row[f"{key}_median_us"] = med
            if key in CORE_METRICS:
                row[f"{key}_mean_us"] = mean
                row[f"{key}_p90_us"] = p90
                row[f"{key}_p99_us"] = p99
        row["steal_gt0_frac"] = steal_gt0_frac(sub)
        row["steal_total_ns"] = steal_total_ns(sub)
        row["vm_steal_probe_pct"] = float("nan")
        base_dt = baseline_medians.get((kind, "dt"), float("nan"))
        base_cpu = baseline_medians.get((kind, "cpu"), float("nan"))
        row["ratio_dt"] = med_dt / base_dt if base_dt and not np.isnan(base_dt) else float("nan")
        row["ratio_cpu"] = row["cpu_median_us"] / base_cpu if base_cpu and not np.isnan(base_cpu) else float("nan")
        rows.append(row)
    return rows


def print_table(exp: str, level: str, rows: list[dict]) -> None:
    print(f"\n=== {exp} muc {level} ===")
    hdr = (
        f"{'kind':6} {'n':>6} {'med_dt':>9} {'mn_st':>9} {'p90_st':>9} "
        f"{'st_gt0':>7} {'st_tot_ms':>10} {'vm_prb%':>8} {'r_dt':>7}"
    )
    print(hdr)
    for r in rows:
        st_ms = r["steal_total_ns"] / 1e6 if not np.isnan(r["steal_total_ns"]) else float("nan")
        vmp = r.get("vm_steal_probe_pct", float("nan"))
        print(
            f"{r['kind']:6} {r['n']:6d} {r['median_us']:9.2f} {r['steal_mean_us']:9.2f} {r['steal_p90_us']:9.2f} "
            f"{r['steal_gt0_frac']:7.3f} {st_ms:10.2f} {vmp:8.3f} {r['ratio_dt']:7.3f}"
        )


def boxplot_exp(outdir: Path, exp: str, by_level: dict[str, pd.DataFrame]) -> None:
    levels = sort_levels(list(by_level.keys()))
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    dt_data = []
    cpu_data = []
    labels = []
    for lv in levels:
        burn = by_level[lv]
        burn = burn[burn["syscall_nr"].isin(BURN_NRS)]
        if burn.empty:
            continue
        labels.append(str(lv))
        dt_data.append((burn["dt_ns"].dropna() / 1000.0).values)
        cpu_data.append((burn["cpu_ns"].dropna() / 1000.0).values)
    if not dt_data:
        plt.close(fig)
        return
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
    for level in sort_levels(list(csv_paths.keys())):
        df = classify(load_csv(csv_paths[level]))
        df.attrs["experiment"] = exp
        by_level[level] = df
    bl = baseline_level_key(by_level, exp)
    if bl in by_level:
        for kind in ("burn", "sleep"):
            sub = by_level[bl][by_level[bl]["kind"] == kind]
            baseline_medians[(kind, "dt")] = float(sub["dt_ns"].median() / 1000.0) if len(sub) else float("nan")
            baseline_medians[(kind, "cpu")] = float(sub["cpu_ns"].median() / 1000.0) if len(sub) else float("nan")
    for level, df in by_level.items():
        rows = level_table(df, level, baseline_medians)
        print_table(exp, level, rows)
        summary_rows.extend(rows)
    boxplot_exp(outdir, exp, by_level)


def load_steal_probe(path: Path) -> pd.DataFrame:
    rows = []
    with path.open() as f:
        for line in f:
            if line.startswith("#") or line.startswith("mono_ns"):
                continue
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) < 7:
                continue
            rows.append(
                {
                    "mono_ns": int(parts[0]),
                    "wall": parts[1],
                    "cpu": int(parts[2]),
                    "vmw_ns": int(parts[4]) if parts[4] else 0,
                }
            )
    return pd.DataFrame(rows)


def probe_vm_steal_pct(path: Path, wall_start: str, wall_end: str) -> float:
    """% steal VM trong cua so [wall_start, wall_end] tu steal-probe (tong dvmw / n_cpu * wall_ns)."""
    df = load_steal_probe(path)
    if df.empty:
        return float("nan")
    ws = pd.to_datetime(wall_start, utc=True)
    we = pd.to_datetime(wall_end, utc=True)
    df["wall_ts"] = pd.to_datetime(df["wall"], utc=True)
    df = df[(df["wall_ts"] >= ws) & (df["wall_ts"] <= we)]
    if df.empty:
        return float("nan")
    n_cpu = df["cpu"].nunique()
    if n_cpu <= 0:
        return float("nan")
    wall_ns = (we - ws).total_seconds() * 1e9
    if wall_ns <= 0:
        return float("nan")
    d_vmw = 0.0
    for cpu, g in df.groupby("cpu"):
        g = g.sort_values("mono_ns")
        d_vmw += float(g["vmw_ns"].iloc[-1] - g["vmw_ns"].iloc[0])
    return 100.0 * d_vmw / (n_cpu * wall_ns)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", type=Path)
    ap.add_argument("--summary", type=Path)
    ap.add_argument("--probe-steal-pct", nargs=3, metavar=("CSV", "WALL_START", "WALL_END"))
    ap.add_argument("manifest", nargs="*", help="exp:level:csv ...")
    args = ap.parse_args()

    if args.probe_steal_pct:
        csv_p, w0, w1 = args.probe_steal_pct
        pct = probe_vm_steal_pct(Path(csv_p), w0, w1)
        print(f"{pct:.6f}")
        return

    if not args.outdir or not args.summary or not args.manifest:
        ap.error("can --outdir, --summary va manifest (hoac --probe-steal-pct)")
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
