#!/usr/bin/env python3
"""Sinh bo tong hop C5 voi nguon nen/bn/benign-lieu/slow + nhan gia (M6g-b).

Mac dinh 10_000_000 ban ghi. Timestamp DON DIEU theo tid (khong wrap).
"""
from __future__ import annotations

import argparse
import os
import time


COLS = ("tid,ts_enter,syscall_nr,flags,cpu_ns,steal_ns,irq_ns,rq_ns,vol_ns,"
        "steal_off_ns,dt_ns,inst,cyc,pmu_ok,cgroup_id,seq,vol_us\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--records", type=int, default=10_000_000)
    ap.add_argument("--tids", type=int, default=12)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    for d in ("nen", "bn", "benign-lieu", "slow", "lab"):
        os.makedirs(os.path.join(a.out, d), exist_ok=True)

    day_ns = 86_400 * 1_000_000_000
    t0 = 10_000_000_000_000
    with open(os.path.join(a.out, "benign-khoi-dong.txt"), "w") as fh:
        fh.write("start_mono_ns=%d\n" % t0)
        fh.write("start_wall=2026-10-01T00:00:00+07:00\n")

    state = a.seed & 0xFFFFFFFF

    def rnd():
        nonlocal state
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        return state

    n_nen = int(a.records * 0.70)
    n_bn = int(a.records * 0.15)
    n_bl = int(a.records * 0.10)
    n_slow = a.records - n_nen - n_bn - n_bl

    tids = list(range(5000, 5000 + a.tids))
    seq = 0
    t_gen0 = time.time()

    def write_chunk(path, n, t_start, span_ns, attack_ranges=None, inflate=False):
        """Ghi n ban ghi, timestamp don dieu theo tid trong [t_start, t_start+span)."""
        nonlocal seq
        attack_ranges = attack_ranges or []
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        # dt trung binh de phu gan het span
        per_tid = max(1, (n + a.tids - 1) // a.tids)
        dt_base = max(1_000_000, span_ns // max(1, per_tid))
        last = {t: None for t in tids}
        with open(path, "w", encoding="utf-8", buffering=8 * 1024 * 1024) as fh:
            fh.write(COLS)
            buf = []
            written = 0
            while written < n:
                tid = tids[written % a.tids]
                seq += 1
                r = rnd()
                jitter = (r % max(1, dt_base // 5)) - (dt_base // 10)
                dt = max(500_000, dt_base + jitter)
                if last[tid] is None:
                    cur = t_start + (tid % 97) * 1000
                    flags = 1
                    dt_out = 0
                else:
                    cur = last[tid] + dt
                    flags = 0
                    dt_out = dt
                for alo, ahi in attack_ranges:
                    if flags == 0 and alo <= cur < ahi:
                        # keo dai dt trong tan cong
                        dt = max(dt, dt_base * 4)
                        cur = last[tid] + dt
                        dt_out = dt
                        break
                if inflate and flags == 0 and (r % 17) == 0:
                    dt = max(dt, dt_base * 3)
                    cur = last[tid] + dt
                    dt_out = dt
                # khong wrap: neu vuot span, van ghi nhung giu don dieu (span chi la goi y)
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
                buf.append("%d,%d,0,%d,%d,%d,%d,%d,0,0,%d,%d,%d,%d,%d,%d,0\n" % (
                    tid, cur, flags, cpu, steal, irq, rq, dt_out,
                    inst, cyc, pmu, cg, seq,
                ))
                written += 1
                if len(buf) >= 20000:
                    fh.write("".join(buf))
                    buf.clear()
            if buf:
                fh.write("".join(buf))
        # thoi gian thuc te phu
        t_hi = max(last[t] for t in tids if last[t] is not None)
        return written, t_hi

    # --- nen: 7 ngay, moi ngay span = day_ns ---
    per = n_nen // 7
    for day in range(7):
        n = per if day < 6 else (n_nen - 6 * per)
        path = os.path.join(a.out, "nen", "day%02d.csv" % (day + 1))
        _, thi = write_chunk(path, n, t0 + day * day_ns, day_ns)
        print("nen day%02d n=%d t_hi=%d" % (day + 1, n, thi), flush=True)

    # --- bn: attacks nam trong nua dau span thuc te ---
    # Dat attack offset theo ti le span de luon nam trong du lieu
    bn_specs = [
        ("B1-D1N0", 0, 2, "B1-10s@N0", 0.10, 0.15),
        ("B1-D1N2", 2, 2, "B1-10s@N2", 0.35, 0.15),
        ("B1-D1N4", 4, 2, "B1-10s@N4", 0.60, 0.15),
        ("B4-D1N0", 0, 6, "B4@N0", 0.10, 0.15),
        ("B4-D1N2", 2, 6, "B4@N2", 0.35, 0.15),
        ("B4-D1N4", 4, 6, "B4@N4", 0.60, 0.15),
    ]
    per_bn = n_bn // len(bn_specs)
    attacks = []
    muc_rows = []
    for i, (sess, muc, day_off, atk_id, off_frac, dur_frac) in enumerate(bn_specs):
        n = per_bn if i < len(bn_specs) - 1 else (n_bn - (len(bn_specs) - 1) * per_bn)
        t_start = t0 + day_off * day_ns
        # span du de chua ~n ban ghi o dt ~50ms
        span = max(3600 * 1_000_000_000, int(n / a.tids * 55_000_000 * 1.2))
        # tam dat attack theo span du kien; sau khi ghi se chinh lai theo t_hi
        alo = t_start + int(span * off_frac)
        ahi = alo + int(span * dur_frac)
        path = os.path.join(a.out, "bn", sess, "session.csv")
        _, thi = write_chunk(path, n, t_start, span, attack_ranges=[(alo, ahi)], inflate=True)
        attacks.append((alo, ahi, "B", atk_id))
        muc_rows.append((t_start, max(thi, ahi) + 1, str(muc), sess))
        print("bn %s n=%d muc=%s atk=%s [%d,%d) thi=%d" % (
            sess, n, muc, atk_id, alo, ahi, thi), flush=True)

    # --- benign-lieu ---
    bl_specs = [
        ("BEN-D1-8-r1", "D1-8", 3, 0.1),
        ("BEN-D1-16-r1", "D1-16", 3, 0.5),
        ("BEN-D3-4-r1", "D3-4", 4, 0.1),
        ("BEN-D3-7-r1", "D3-7", 4, 0.5),
    ]
    per_bl = n_bl // len(bl_specs)
    for i, (sess, muc, day_off, off_frac) in enumerate(bl_specs):
        n = per_bl if i < len(bl_specs) - 1 else (n_bl - (len(bl_specs) - 1) * per_bl)
        t_start = t0 + day_off * day_ns + int(off_frac * 3600 * 1_000_000_000)
        span = max(900 * 1_000_000_000, int(n / a.tids * 55_000_000 * 1.2))
        path = os.path.join(a.out, "benign-lieu", sess, "session.csv")
        _, thi = write_chunk(path, n, t_start, span)
        muc_rows.append((t_start, thi + 1, muc, sess))
        print("benign-lieu %s n=%d muc=%s" % (sess, n, muc), flush=True)

    # --- slow ---
    slow_specs = [
        ("B1-60s", "B1-60s", 6, 0.2, 0.2),
        ("B1-300s", "B1-300s", 6, 0.5, 0.3),
    ]
    per_sl = n_slow // len(slow_specs)
    for i, (sess, atk_id, day_off, off_frac, dur_frac) in enumerate(slow_specs):
        n = per_sl if i < len(slow_specs) - 1 else (n_slow - (len(slow_specs) - 1) * per_sl)
        t_start = t0 + day_off * day_ns + 2 * 3600 * 1_000_000_000
        span = max(2000 * 1_000_000_000, int(n / a.tids * 55_000_000 * 1.2))
        alo = t_start + int(span * off_frac)
        ahi = alo + int(span * dur_frac)
        path = os.path.join(a.out, "slow", sess, "session.csv")
        _, thi = write_chunk(path, n, t_start, span, attack_ranges=[(alo, ahi)], inflate=True)
        attacks.append((alo, ahi, "B", atk_id))
        muc_rows.append((t_start, max(thi, ahi) + 1, "0", sess))
        print("slow %s n=%d atk=%s" % (sess, n, atk_id), flush=True)

    muc_rows.append((t0, t0 + 7 * day_ns, "0", "nen"))

    with open(os.path.join(a.out, "lab", "nhan-tan-cong.tsv"), "w") as fh:
        fh.write("t_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tlop\tid\n")
        for lo, hi, lop, iid in attacks:
            fh.write("%d\t%d\t%s\t%s\n" % (lo, hi, lop, iid))

    with open(os.path.join(a.out, "lab", "nhan-lieu.tsv"), "w") as fh:
        fh.write("t_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tmuc\tid\n")
        for lo, hi, muc, note in muc_rows:
            if note.startswith("BEN"):
                fh.write("%d\t%d\t%s\t%s\n" % (lo, hi, muc, note))

    with open(os.path.join(a.out, "lab", "nhan-phien.tsv"), "w") as fh:
        fh.write("start_ns\tstop_ns\tmuc\tid\n")
        for lo, hi, muc, note in muc_rows:
            if note.startswith("BEN") or note == "nen":
                continue
            fh.write("%d\t%d\t%s\t%s\n" % (lo, hi, muc, note))

    with open(os.path.join(a.out, "meta.txt"), "w") as fh:
        fh.write("records=%d\ntids=%d\nseed=%d\ngen_sec=%.2f\n" % (
            a.records, a.tids, a.seed, time.time() - t_gen0))
    print("XONG out=%s records=%d gen_sec=%.2f attacks=%d" % (
        a.out, a.records, time.time() - t_gen0, len(attacks)))


if __name__ == "__main__":
    main()
