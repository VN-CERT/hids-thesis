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
FLAG_CLAMPED = 1 << 6


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
COLS = ["dt_ns", "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_ns", "steal_off_ns"]
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


def clamped_count(sub: pd.DataFrame) -> float:
    if sub.empty or "flags" not in sub.columns:
        return float("nan")
    fl = pd.to_numeric(sub["flags"], errors="coerce").fillna(0).astype(np.int64)
    return float((fl & FLAG_CLAMPED).sum())


def steal_off_total_ns(sub: pd.DataFrame) -> float:
    if sub.empty or "steal_off_ns" not in sub.columns:
        return float("nan")
    s = sub["steal_off_ns"].dropna().astype(float)
    if s.empty:
        return float("nan")
    return float(s.sum())


def col_mean_ns(sub: pd.DataFrame, col: str) -> float:
    if col not in sub.columns:
        return float("nan")
    s = sub[col].dropna().astype(float)
    if s.empty:
        return float("nan")
    return float(s.mean())


def fmt_num(x: float, width: int = 0, prec: int = 2) -> str:
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return "n/a"
    if width:
        return f"{x:{width}.{prec}f}"
    return f"{x:.{prec}f}"


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
        if "dt_ns" not in sub.columns:
            med_dt = mean_dt = p90_dt = p99_dt = float("nan")
        else:
            med_dt, mean_dt, p90_dt, p99_dt = us_stats_full(sub["dt_ns"])
        row["median_us"] = med_dt
        row["p90_us"] = p90_dt
        row["p99_us"] = p99_dt
        row["dt_mean_us"] = mean_dt
        row["dt_p90_us"] = p90_dt
        row["dt_p99_us"] = p99_dt
        for c in COLS:
            key = c.replace("_ns", "")
            if c not in sub.columns:
                row[f"{key}_median_us"] = float("nan")
                if key in CORE_METRICS:
                    row[f"{key}_mean_us"] = float("nan")
                    row[f"{key}_p90_us"] = float("nan")
                    row[f"{key}_p99_us"] = float("nan")
                continue
            med, mean, p90, p99 = us_stats_full(sub[c])
            row[f"{key}_median_us"] = med
            if key in CORE_METRICS:
                row[f"{key}_mean_us"] = mean
                row[f"{key}_p90_us"] = p90
                row[f"{key}_p99_us"] = p99
        row["steal_gt0_frac"] = steal_gt0_frac(sub)
        row["steal_total_ns"] = steal_total_ns(sub)
        row["steal_off_total_ns"] = steal_off_total_ns(sub)
        if row["n"] and not np.isnan(row["steal_off_total_ns"]):
            row["steal_off_mean_us"] = row["steal_off_total_ns"] / row["n"] / 1000.0
        else:
            row["steal_off_mean_us"] = float("nan")
        if "vol_ns" in sub.columns:
            _, vol_mean, _, _ = us_stats_full(sub["vol_ns"])
            row["vol_mean_us"] = vol_mean
        else:
            row["vol_mean_us"] = float("nan")
        row["clamped_n"] = clamped_count(sub)
        row["vm_steal_probe_pct"] = float("nan")
        base_dt = baseline_medians.get((kind, "dt"), float("nan"))
        base_cpu = baseline_medians.get((kind, "cpu"), float("nan"))
        row["ratio_dt"] = med_dt / base_dt if base_dt and not np.isnan(base_dt) else float("nan")
        cpu_med = row.get("cpu_median_us", float("nan"))
        row["ratio_cpu"] = (
            cpu_med / base_cpu if base_cpu and not np.isnan(base_cpu) and not np.isnan(cpu_med) else float("nan")
        )
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
        st_tot = r.get("steal_total_ns", float("nan"))
        st_ms = st_tot / 1e6 if not np.isnan(st_tot) else float("nan")
        vmp = r.get("vm_steal_probe_pct", float("nan"))
        print(
            f"{r['kind']:6} {r['n']:6d} {fmt_num(r['median_us'], 9):>9} "
            f"{fmt_num(r.get('steal_mean_us'), 9):>9} {fmt_num(r.get('steal_p90_us'), 9):>9} "
            f"{fmt_num(r['steal_gt0_frac'], 7, 3):>7} {fmt_num(st_ms, 10):>10} "
            f"{fmt_num(vmp, 8, 3):>8} {fmt_num(r['ratio_dt'], 7, 3):>7}"
        )


def load_e2_probe_pcts(outdir: Path, levels: list[str]) -> dict[str, float]:
    pcts: dict[str, float] = {}
    for lv in levels:
        p = outdir / "E2" / f"{lv}.vm_steal_probe_pct"
        if not p.exists():
            continue
        t = p.read_text().strip()
        if t:
            try:
                pcts[lv] = float(t)
            except ValueError:
                pass
    return pcts


def boxplot_e2(outdir: Path, by_level: dict[str, pd.DataFrame], probe_pcts: dict[str, float]) -> None:
    levels = [lv for lv in E2_LEVEL_ORDER if lv in by_level]
    if not levels:
        return
    fig, axes = plt.subplots(1, 3, figsize=(11, 4))
    metrics = [("dt_ns", "dt (us)"), ("cpu_ns", "cpu (us)"), ("steal_ns", "steal (us)")]
    for ax, (col, title) in zip(axes, metrics):
        data = []
        labels = []
        for lv in levels:
            burn = by_level[lv]
            burn = burn[burn["syscall_nr"].isin(BURN_NRS)]
            if burn.empty:
                continue
            labels.append(str(lv))
            data.append((burn[col].dropna().astype(float) / 1000.0).values)
        if not data:
            continue
        ax.boxplot(data, labels=labels)
        ax.set_yscale("log")
        ax.set_title(title)
        ax.set_xlabel("CPU limit (MHz)")
        for i, lv in enumerate(labels):
            pr = probe_pcts.get(lv, float("nan"))
            if not np.isnan(pr):
                ax.text(i + 1, ax.get_ylim()[0], f"probe={pr:.2f}%", ha="center", va="top", fontsize=7)
    fig.suptitle("E2 burn intervals")
    fig.tight_layout()
    fig.savefig(outdir / "E2.png", dpi=120)
    plt.close(fig)


def decomposition_rows(exp: str, by_level: dict[str, pd.DataFrame]) -> list[dict]:
    levels = sort_levels(list(by_level.keys()))
    bl = baseline_level_key(by_level, exp)
    dt_cols = ["cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_ns"]
    off_col = "steal_off_ns"
    rows: list[dict] = []
    for kind in ("burn", "sleep"):
        if bl not in by_level:
            continue
        base = by_level[bl][by_level[bl]["kind"] == kind]
        if base.empty:
            continue
        base_dt = col_mean_ns(base, "dt_ns")
        base_parts = {c: col_mean_ns(base, c) for c in dt_cols}
        base_off = col_mean_ns(base, off_col)
        for lv in levels:
            sub = by_level[lv][by_level[lv]["kind"] == kind]
            if sub.empty:
                continue
            mean_dt = col_mean_ns(sub, "dt_ns")
            parts = {c: col_mean_ns(sub, c) for c in dt_cols}
            off_mean = col_mean_ns(sub, off_col)
            d_dt = mean_dt - base_dt
            d_parts = {c.replace("_ns", ""): parts[c] - base_parts[c] for c in dt_cols}
            d_off = (
                off_mean - base_off
                if not (np.isnan(off_mean) or np.isnan(base_off))
                else float("nan")
            )
            check = sum(d_parts[k] for k in ("cpu", "steal", "irq", "rq", "vol")) - d_dt
            rows.append(
                {
                    "experiment": exp,
                    "kind": kind,
                    "level": lv,
                    "delta_dt_mean_ns": d_dt,
                    "delta_cpu_mean_ns": d_parts["cpu"],
                    "delta_steal_mean_ns": d_parts["steal"],
                    "delta_irq_mean_ns": d_parts["irq"],
                    "delta_rq_mean_ns": d_parts["rq"],
                    "delta_vol_mean_ns": d_parts["vol"],
                    "delta_steal_off_mean_ns": d_off,
                    "check_sum_ns": check,
                }
            )
    return rows


def print_decomposition(exp: str, rows: list[dict]) -> None:
    sub = [r for r in rows if r["experiment"] == exp]
    if not sub:
        return
    print(f"\n=== Phan ra muc tang — {exp} (ns, so voi muc dau) ===")
    hdr = (
        f"{'kind':6} {'level':>10} {'d_dt':>12} {'d_cpu':>10} {'d_steal':>10} "
        f"{'d_irq':>8} {'d_rq':>10} {'d_vol':>10} {'d_st_off':>10} {'check':>10}"
    )
    print(hdr)
    for r in sub:
        print(
            f"{r['kind']:6} {str(r['level']):>10} "
            f"{fmt_num(r['delta_dt_mean_ns'], 12, 0):>12} "
            f"{fmt_num(r['delta_cpu_mean_ns'], 10, 0):>10} "
            f"{fmt_num(r['delta_steal_mean_ns'], 10, 0):>10} "
            f"{fmt_num(r['delta_irq_mean_ns'], 8, 0):>8} "
            f"{fmt_num(r['delta_rq_mean_ns'], 10, 0):>10} "
            f"{fmt_num(r['delta_vol_mean_ns'], 10, 0):>10} "
            f"{fmt_num(r['delta_steal_off_mean_ns'], 10, 0):>10} "
            f"{fmt_num(r['check_sum_ns'], 10, 0):>10}"
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
    if exp == "E2":
        probe = load_e2_probe_pcts(outdir, sort_levels(list(by_level.keys())))
        for r in summary_rows:
            if r.get("experiment") == "E2" and r.get("kind") == "burn":
                pr = probe.get(str(r["level"]))
                if pr is not None:
                    r["vm_steal_probe_pct"] = pr
        boxplot_e2(outdir, by_level, probe)
    else:
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
    ap.add_argument(
        "--m4-close",
        action="store_true",
        help="ve E2.png dac biet + luu decompose-E1/E2.csv tu thu muc --outdir",
    )
    ap.add_argument("manifest", nargs="*", help="exp:level:csv ...")
    args = ap.parse_args()

    if args.probe_steal_pct:
        csv_p, w0, w1 = args.probe_steal_pct
        pct = probe_vm_steal_pct(Path(csv_p), w0, w1)
        print(f"{pct:.6f}")
        return

    if args.m4_close:
        if not args.outdir:
            ap.error("--m4-close can --outdir")
        args.outdir.mkdir(parents=True, exist_ok=True)
        decomp: list[dict] = []
        for exp, pattern in (("E1", "E1/L{}.csv"), ("E2", "E2/{}.csv")):
            paths: dict[str, Path] = {}
            if exp == "E1":
                for L in range(4):
                    p = args.outdir / pattern.format(L)
                    if p.exists():
                        paths[str(L)] = p
            else:
                for lv in E2_LEVEL_ORDER:
                    p = args.outdir / pattern.format(lv)
                    if p.exists():
                        paths[lv] = p
            if not paths:
                continue
            by_level = {}
            for level, p in paths.items():
                df = classify(load_csv(p))
                df.attrs["experiment"] = exp
                by_level[level] = df
            decomp.extend(decomposition_rows(exp, by_level))
            if exp == "E2":
                boxplot_e2(args.outdir, by_level, load_e2_probe_pcts(args.outdir, list(paths.keys())))
        if decomp:
            ddf = pd.DataFrame(decomp)
            for exp in ("E1", "E2"):
                sub = ddf[ddf["experiment"] == exp]
                if not sub.empty:
                    sub.to_csv(args.outdir / f"decompose-{exp}.csv", index=False)
                    print_decomposition(exp, decomp)
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
