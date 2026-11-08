#!/usr/bin/env python3
"""LAB-2 — mẫu tải nền mỗi 10s trong cửa sổ nhãn (không đụng .bin/collector).
Ghi <sess>/tai-nen.tsv; cuoi cua so append 1 dong tai-nen-tomtat.tsv.
"""
from __future__ import annotations

import argparse
import os
import statistics
import subprocess
import time
from pathlib import Path


def read_loadavg() -> float:
    return float(open("/proc/loadavg").read().split()[0])


def read_stat_idle_total() -> tuple[int, int]:
    for line in open("/proc/stat"):
        if line.startswith("cpu "):
            parts = [int(x) for x in line.split()[1:]]
            total = sum(parts)
            idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
            return idle, total
    return 0, 0


def read_cgroup_usage_usec(cg: str) -> int:
    p = Path(cg) / "cpu.stat"
    if not p.is_file():
        return -1
    for line in p.read_text().splitlines():
        if line.startswith("usage_usec"):
            return int(line.split()[1])
    return -1


def n_stress() -> int:
    n = 0
    try:
        out = subprocess.check_output(
            ["pgrep", "-a", "stress-ng"], text=True, stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        return 0
    for line in out.splitlines():
        # worker stream/cpu (bo qua process cha timeout wrapper neu can)
        if "stress-ng-stream" in line or "stress-ng-cpu" in line:
            n += 1
        elif " --stream " in line or line.rstrip().endswith("--stream"):
            pass  # parent
        elif " --cpu " in line and "stress-ng --cpu" in line:
            pass
    # fallback: dem moi dong stress-ng-stream / [run]
    if n == 0:
        for line in out.splitlines():
            if "stress-ng-stream" in line or "stress-ng-cpu" in line or "[run]" in line:
                n += 1
    return n


def p95(xs: list[float]) -> float:
    if not xs:
        return float("nan")
    if len(xs) == 1:
        return xs[0]
    s = sorted(xs)
    idx = min(len(s) - 1, max(0, int(round(0.95 * (len(s) - 1)))))
    return float(s[idx])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sess", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--lop", required=True)
    ap.add_argument("--muc", required=True)
    ap.add_argument("--cg-nginx", required=True)
    ap.add_argument("--cg-postgres", required=True)
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--interval-s", type=float, default=10.0)
    ap.add_argument("--tomtat", required=True, help="path tai-nen-tomtat.tsv")
    ap.add_argument("--wait-until-mono-ns", type=int, default=0,
                    help="neu >0: cho den mono_ns nay moi bat dau mau")
    args = ap.parse_args()

    sess = Path(args.sess)
    sess.mkdir(parents=True, exist_ok=True)
    out = sess / "tai-nen.tsv"

    if args.wait_until_mono_ns > 0:
        while time.monotonic_ns() < args.wait_until_mono_ns:
            time.sleep(0.2)

    # header
    with open(out, "w") as f:
        f.write(
            "t_mono_ns\tloadavg_1m\tcpu_pct_tong\t"
            "cpu_pct_nginx_cgroup\tcpu_pct_postgres_cgroup\tn_stress_worker\n"
        )

    idle0, tot0 = read_stat_idle_total()
    ng0 = read_cgroup_usage_usec(args.cg_nginx)
    pg0 = read_cgroup_usage_usec(args.cg_postgres)
    t_wall0 = time.monotonic()

    rows_load: list[float] = []
    rows_cpu: list[float] = []
    rows_ng: list[float] = []
    rows_pg: list[float] = []
    rows_n: list[float] = []

    end = t_wall0 + args.duration_s
    next_t = t_wall0

    while True:
        now = time.monotonic()
        if now >= end and now > t_wall0:
            # mot mau cuoi neu chua co
            if not rows_load and now >= t_wall0:
                pass
            else:
                break
        if now < next_t:
            time.sleep(min(0.2, next_t - now))
            continue

        idle1, tot1 = read_stat_idle_total()
        ng1 = read_cgroup_usage_usec(args.cg_nginx)
        pg1 = read_cgroup_usage_usec(args.cg_postgres)
        dt = now - t_wall0 if now == next_t and not rows_load else (now - (next_t - args.interval_s))
        # dung delta tu mau truoc
        dt = max(1e-6, now - t_wall0) if not rows_load else max(1e-6, args.interval_s)

        d_tot = tot1 - tot0
        d_idle = idle1 - idle0
        cpu_tong = 0.0 if d_tot <= 0 else 100.0 * (1.0 - d_idle / d_tot)

        def cg_pct(u0: int, u1: int) -> float:
            if u0 < 0 or u1 < 0:
                return float("nan")
            # usage_usec / (dt_s * 1e6) * 100 = % of one CPU; tong co the >100 neu nhieu CPU
            return 100.0 * (u1 - u0) / (dt * 1e6)

        # tinh dt that tu mau truoc
        if rows_load:
            dt = args.interval_s
        else:
            dt = max(args.interval_s * 0.5, now - t_wall0)

        # re-read with proper previous snapshot
        cpu_ng = cg_pct(ng0, ng1)
        cpu_pg = cg_pct(pg0, pg1)
        # recalculate cpu_tong with same window
        d_tot = tot1 - tot0
        d_idle = idle1 - idle0
        cpu_tong = 0.0 if d_tot <= 0 else 100.0 * (1.0 - d_idle / d_tot)

        load = read_loadavg()
        ns = n_stress()
        mono = time.monotonic_ns()
        line = f"{mono}\t{load:.3f}\t{cpu_tong:.3f}\t{cpu_ng:.3f}\t{cpu_pg:.3f}\t{ns}\n"
        with open(out, "a") as f:
            f.write(line)

        rows_load.append(load)
        rows_cpu.append(cpu_tong)
        rows_ng.append(cpu_ng)
        rows_pg.append(cpu_pg)
        rows_n.append(float(ns))

        idle0, tot0 = idle1, tot1
        ng0, pg0 = ng1, pg1
        next_t += args.interval_s
        if now >= end:
            break

    # tomtat
    def avg(xs: list[float]) -> float:
        return float(statistics.mean(xs)) if xs else float("nan")

    tomtat = Path(args.tomtat)
    if not tomtat.exists():
        tomtat.write_text(
            "run_id\tlop\tmuc_tranh_chap\tload_1m_tb\tload_1m_p95\t"
            "cpu_tong_tb%\tcpu_nginx_tb%\tcpu_pg_tb%\tn_worker_tb\n"
        )
    row = (
        f"{args.run_id}\t{args.lop}\t{args.muc}\t"
        f"{avg(rows_load):.3f}\t{p95(rows_load):.3f}\t"
        f"{avg(rows_cpu):.3f}\t{avg(rows_ng):.3f}\t{avg(rows_pg):.3f}\t"
        f"{avg(rows_n):.3f}\n"
    )
    with open(tomtat, "a") as f:
        f.write(row)
    print(f"tai-nen samples={len(rows_load)} -> {out}", flush=True)
    print(row.strip(), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
