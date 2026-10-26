#!/usr/bin/env python3
"""Sinh bo du lieu tong hop lon (CSV kieu rec-export) + nhan gia cho thu c5_pipeline.

Khong dung du lieu LAB-1. Mac dinh 50_000_000 ban ghi, 7 ngay ao.
"""
from __future__ import annotations

import argparse
import os
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="thu muc du lieu tong hop")
    ap.add_argument("--records", type=int, default=50_000_000)
    ap.add_argument("--tids", type=int, default=20)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    os.makedirs(os.path.join(a.out, "bn"), exist_ok=True)
    os.makedirs(os.path.join(a.out, "lab"), exist_ok=True)

    day_ns = 86_400 * 1_000_000_000
    t0 = 10_000_000_000_000  # mono ns ao
    with open(os.path.join(a.out, "benign-khoi-dong.txt"), "w") as fh:
        fh.write("start_mono_ns=%d\n" % t0)
        fh.write("start_wall=2026-10-01T00:00:00+07:00\n")

    # Tan cong nam SOM trong ngay 6 de nam trong pham vi thoi gian cua cac ban ghi
    # (moi ngay chi phu ~ n/(tids) * dt_tb giay, khong phai ca 24h).
    attack_lo = t0 + 5 * day_ns + 120 * 1_000_000_000  # ngay 6, +2 phut
    attack_hi = attack_lo + 600 * 1_000_000_000  # 10 phut

    per_day = a.records // 7
    header = ("ts_enter,cgroup_id,tid,seq,syscall_nr,flags,"
              "cpu_ns,steal_ns,irq_ns,rq_ns,vol_us,steal_off_ns,inst,cyc,pmu_ok,vol_ns,dt_ns\n")
    tids = list(range(5000, 5000 + a.tids))
    last = {t: 0 for t in tids}
    seq = 0
    # LCG nhanh, seed
    state = a.seed & 0xFFFFFFFF

    def rnd():
        nonlocal state
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        return state

    t_gen0 = time.time()
    for day in range(7):
        path = os.path.join(a.out, "bn", "day%02d.csv" % (day + 1))
        day_start = t0 + day * day_ns
        day_end = day_start + day_ns
        n = per_day if day < 6 else (a.records - 6 * per_day)
        # chia deu theo tid trong ngay
        for t in tids:
            last[t] = day_start + (rnd() % 1000)
        with open(path, "w", encoding="utf-8", buffering=8 * 1024 * 1024) as fh:
            fh.write(header)
            buf = []
            written = 0
            while written < n:
                tid = tids[written % a.tids]
                seq += 1
                r = rnd()
                dt = 40_000_000 + (r % 30_000_001)  # 40-70 ms
                prev = last[tid]
                if prev <= day_start:
                    cur = prev if prev > 0 else day_start
                    flags = 1  # FIRST
                    dt_out = 0
                else:
                    cur = prev + dt
                    flags = 0
                    dt_out = dt
                if attack_lo <= cur < attack_hi and flags == 0:
                    dt = 200_000_000 + (rnd() % 100_000_001)
                    cur = prev + dt
                    dt_out = dt
                if cur >= day_end:
                    # reset tid sang dau ngay + offset de tranh ket vong
                    last[tid] = day_start + (rnd() % 10_000)
                    written += 1
                    continue
                last[tid] = cur
                cpu = 5000 + (r % 2001)
                rq = (0, 0, 0, 100, 500, 2000)[r % 6]
                steal = (0, 0, 50, 200)[r % 4]
                irq = (0, 0, 10)[r % 3]
                inst = 10000 + (r % 5001)
                cyc = inst * 2 + (r % 1001)
                pmu = 1 if (r % 20) == 0 else 0
                if pmu:
                    flags |= 1 << 7
                cg = 9000 + (tid % 3)
                buf.append("%d,%d,%d,%d,0,%d,%d,%d,%d,%d,0,0,%d,%d,%d,%d,%d\n" % (
                    cur, cg, tid, seq, flags, cpu, steal, irq, rq,
                    inst, cyc, pmu, cpu, dt_out,
                ))
                written += 1
                if len(buf) >= 20000:
                    fh.write("".join(buf))
                    buf.clear()
                if written % 5_000_000 == 0:
                    print("day%02d %d/%d elapsed=%.1fs" % (
                        day + 1, written, n, time.time() - t_gen0), flush=True)
            if buf:
                fh.write("".join(buf))
        print("wrote %s n=%d" % (path, n), flush=True)

    with open(os.path.join(a.out, "lab", "nhan-tan-cong.tsv"), "w") as fh:
        fh.write("t_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tlop\tid\n")
        fh.write("%d\t%d\tB\tSYN-B1\n" % (attack_lo, attack_hi))
    with open(os.path.join(a.out, "lab", "nhan-lieu.tsv"), "w") as fh:
        fh.write("t_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tmuc\tid\n")
        # muc trong ngay huan luyen (3/4) va ngay kiem (7) de SVG co truc X
        fh.write("%d\t%d\t0\tBEN-0\n" % (
            t0 + 2 * day_ns + 30 * 1_000_000_000,
            t0 + 2 * day_ns + 900 * 1_000_000_000))
        fh.write("%d\t%d\t2\tBEN-2\n" % (
            t0 + 3 * day_ns + 30 * 1_000_000_000,
            t0 + 3 * day_ns + 900 * 1_000_000_000))
        fh.write("%d\t%d\t0\tBEN-0b\n" % (
            t0 + 6 * day_ns + 30 * 1_000_000_000,
            t0 + 6 * day_ns + 400 * 1_000_000_000))
        fh.write("%d\t%d\t2\tBEN-2b\n" % (
            t0 + 6 * day_ns + 400 * 1_000_000_000,
            t0 + 6 * day_ns + 900 * 1_000_000_000))

    # meta
    with open(os.path.join(a.out, "meta.txt"), "w") as fh:
        fh.write("records=%d\ntids=%d\nseed=%d\n"
                 "attack_lo=%d\nattack_hi=%d\ngen_sec=%.2f\n" % (
                     a.records, a.tids, a.seed, attack_lo, attack_hi,
                     time.time() - t_gen0))
    print("XONG out=%s records=%d gen_sec=%.2f" % (
        a.out, a.records, time.time() - t_gen0))


if __name__ == "__main__":
    main()
