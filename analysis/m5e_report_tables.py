#!/usr/bin/env python3
"""Bang tai co dinh + T4 CI cho R020."""
from __future__ import annotations

import math
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


def ci95(vals: list[float]) -> tuple[float, float, float]:
    if not vals:
        return 0.0, 0.0, 0.0
    m = statistics.mean(vals)
    if len(vals) < 2:
        return m, 0.0, 0.0
    s = statistics.stdev(vals)
    half = 1.96 * s / math.sqrt(len(vals))
    return m, s, half


def fixed_table(root: Path) -> str:
    lines = ["=== tai co dinh (chi run latency_sanity=1) ==="]
    for load in sorted(root.glob("T*-R*")):
        if not load.is_dir():
            continue
        for cond in ("C0", "C1", "C2"):
            avgs, p50s, p99s, cgs = [], [], [], []
            for run_dir in sorted(load.glob(f"{cond}/run*")):
                rf = run_dir / "result.txt"
                if not rf.exists():
                    continue
                p = parse_result(rf)
                if p.get("latency_sanity") != "1":
                    lines.append(f"BO QUA {run_dir} sanity={p.get('latency_sanity')}")
                    continue
                if p.get("latency_ms"):
                    avgs.append(float(p["latency_ms"]))
                if p.get("p50_ms"):
                    p50s.append(float(p["p50_ms"]))
                if p.get("p99_ms"):
                    p99s.append(float(p["p99_ms"]))
                if p.get("cgroup_cpu_usec"):
                    cgs.append(float(p["cgroup_cpu_usec"]))
            if not avgs:
                continue
            lines.append(
                f"{load.name}\t{cond}\tavg_ms={statistics.mean(avgs):.4f}\t"
                f"p50={statistics.mean(p50s):.4f}\tp99={statistics.mean(p99s):.4f}\t"
                f"cgroup_cpu_usec={statistics.mean(cgs):.0f}\tn={len(avgs)}"
            )
    return "\n".join(lines)


def t4_table(root: Path) -> str:
    lines = ["=== T4 kich tran (95% CI tren metric value) ==="]
    for cond in ("C0", "C1", "C2"):
        vals = []
        for run_dir in sorted((root / "T4" / cond).glob("run*")):
            rf = run_dir / "result.txt"
            if rf.exists() and parse_result(rf).get("value"):
                vals.append(float(parse_result(rf)["value"]))
        m, s, h = ci95(vals)
        lines.append(f"T4\t{cond}\tmean={m:.4f}\tstd={s:.4f}\tci95_half={h:.4f}\tn={len(vals)}")
    return "\n".join(lines)


def main() -> None:
    root = Path(sys.argv[1])
    print(fixed_table(root))
    print()
    print(t4_table(root))


if __name__ == "__main__":
    main()
