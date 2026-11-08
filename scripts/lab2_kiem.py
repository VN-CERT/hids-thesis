#!/usr/bin/env python3
"""lab2_kiem.py — kiểm sau mỗi phiên LAB-2.
Tieu chi: drops=0; cgroup nginx; tid records >= 50; moc ±1s; PMU 4–6%;
A2: beacon >= 3; B2: bytes khop ±5%; C2: tries >= 10.
"""
from __future__ import annotations

import argparse
import glob
import importlib.util
import os
import sys


def _load_lab1c():
    path = os.path.join(os.path.dirname(__file__), "lab1c_kiem.py")
    spec = importlib.util.spec_from_file_location("lab1c_kiem", path)
    mod = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    L = _load_lab1c()
    ap = argparse.ArgumentParser()
    ap.add_argument("--sess", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--lop", required=True, choices=["A2", "B2", "C2", "N"])
    ap.add_argument("--t0", type=int, required=True)
    ap.add_argument("--t1", type=int, required=True)
    ap.add_argument("--tids", required=True)
    ap.add_argument("--oracle", type=float, required=True)
    ap.add_argument("--oracle-ref", type=float, default=-1.0)
    ap.add_argument("--min-recs", type=int, default=50)
    ap.add_argument("--pids-check", default="")
    ap.add_argument("--relax-moc", action="store_true")
    args = ap.parse_args()

    sess = args.sess
    datadir = os.path.join(sess, "data")
    out = os.path.join(sess, "kiem.txt")
    tids = {int(x) for x in args.tids.split(",") if x.strip()}
    msgs: list[str] = []
    ok = True

    bins = sorted(glob.glob(os.path.join(datadir, "*.bin")))
    if not bins:
        open(out, "w").write("FAIL: khong co .bin\nok=0\n")
        print("FAIL: khong co .bin\nok=0")
        return 1
    b = max(bins, key=os.path.getsize)

    kd, pd = L.status_drops(datadir)
    msgs.append(f"drops kernel={kd} proc={pd}")
    if kd != 0 or pd != 0:
        msgs.append("FAIL drops != 0")
        ok = False

    info = L.rec_stat_info(b)
    msgs.append(
        f"rec-stat recs={info.get('recs')} pmu_pct={info.get('pmu_pct')} "
        f"bin={b} n_bins={len(bins)}"
    )
    pmu = info.get("pmu_pct")
    if pmu != pmu or not (4.0 <= float(pmu) <= 6.0):
        msgs.append(f"FAIL PMU={pmu} ngoai [4,6]")
        ok = False
    else:
        msgs.append("PMU DAT")

    counts = {t: 0 for t in tids}
    first_ts = {t: None for t in tids}
    last_ts = {t: None for t in tids}
    for bip in bins:
        c_i, f_i, l_i = L.count_tid_records(bip, tids, args.t0, args.t1)
        for t in tids:
            counts[t] += c_i.get(t, 0)
            if f_i.get(t) is not None:
                if first_ts[t] is None or f_i[t] < first_ts[t]:
                    first_ts[t] = f_i[t]
            if l_i.get(t) is not None:
                if last_ts[t] is None or l_i[t] > last_ts[t]:
                    last_ts[t] = l_i[t]
    total = sum(counts.values())
    msgs.append(f"tid_records_total={total} per={counts}")
    if total < args.min_recs:
        msgs.append(f"FAIL n_ban_ghi_tid={total} < {args.min_recs}")
        ok = False
    else:
        msgs.append("n_ban_ghi_tid DAT")

    if total > 0:
        fmin = min(v for v in first_ts.values() if v is not None)
        lmax = max(v for v in last_ts.values() if v is not None)
        d0 = abs(fmin - args.t0) / 1e9
        d1 = abs(lmax - args.t1) / 1e9
        msgs.append(f"moc |first-t0|={d0:.3f}s |last-t1|={d1:.3f}s")
        if args.relax_moc:
            if d0 > 1.0:
                msgs.append("FAIL moc nhan first > 1s")
                ok = False
            else:
                msgs.append("moc nhan DAT (relax last)")
        elif d0 > 1.0 or d1 > 1.0:
            msgs.append("FAIL moc nhan > 1s")
            ok = False
        else:
            msgs.append("moc nhan DAT")
    else:
        msgs.append("FAIL khong co ban ghi de kiem moc")
        ok = False

    msgs.append(f"oracle lop={args.lop} value={args.oracle}")
    if args.lop == "A2":
        if args.oracle < 3:
            msgs.append(f"FAIL A2 beacon/oracle={args.oracle} < 3")
            ok = False
        else:
            msgs.append("A2 oracle DAT (>=3 beacon)")
    elif args.lop == "B2":
        if args.oracle_ref > 0:
            ref = args.oracle_ref
            diff = abs(args.oracle - ref) / ref * 100.0
            msgs.append(f"B2 bytes_sent={args.oracle} ref={ref} diff_pct={diff:.3f}")
            if diff > 5.0:
                msgs.append("FAIL B2 bytes khong khop ±5%")
                ok = False
            else:
                msgs.append("B2 bytes DAT")
        else:
            if args.oracle < 1:
                msgs.append("FAIL B2 bytes=0")
                ok = False
            else:
                msgs.append("B2 bytes DAT (khong co ref)")
    elif args.lop == "C2":
        if args.oracle < 10:
            msgs.append(f"FAIL C2 tries={args.oracle} < 10")
            ok = False
        else:
            msgs.append("C2 tries DAT")
    else:
        msgs.append("N: khong kiem oracle tan cong")

    cg_ok = True
    for pid_s in (args.pids_check or "").split(","):
        if not pid_s.strip():
            continue
        pid = int(pid_s)
        path = f"/proc/{pid}/cgroup"
        if not os.path.isfile(path):
            msgs.append(f"cgroup pid={pid}: process gone (ok neu da ket thuc)")
            continue
        txt = open(path).read()
        if "docker-" not in txt and "lab0-nginx" not in txt:
            msgs.append(f"FAIL cgroup pid={pid}: {txt[:200]}")
            cg_ok = False
            ok = False
        else:
            msgs.append(f"cgroup pid={pid}: OK")
    if cg_ok:
        msgs.append("cgroup DAT (hoac pid da ket thuc)")

    msgs.append(f"ok={1 if ok else 0}")
    open(out, "w").write("\n".join(msgs) + "\n")
    print("\n".join(msgs))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
