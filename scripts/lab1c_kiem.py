#!/usr/bin/env python3
"""lab1c_kiem.py — kiểm sau mỗi phiên LAB-1c → bn/<run_id>/kiem.txt
Usage: lab1c_kiem.py --sess <dir> --run-id <id> --t0 <ns> --t1 <ns> --tids <csv> --cycles <n> [--period-s N]
"""
from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys


def header_pmu(binpath: str) -> str:
    try:
        out = subprocess.check_output(
            ["python3", "scripts/bin_header.py", binpath],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return ""
    for line in out.splitlines():
        if line.startswith("# pmu:"):
            return line.split(":", 1)[1].strip()
    return ""


def rec_stat_info(binpath: str) -> dict:
    info = {"recs": 0, "pmu_pct": float("nan"), "first": 0}
    try:
        out = subprocess.check_output(
            ["./bin/rec-stat", binpath], text=True, stderr=subprocess.DEVNULL
        )
    except Exception as e:
        info["err"] = str(e)
        return info
    for line in out.splitlines():
        if "tong so ban ghi" in line:
            info["recs"] = int(line.split(":")[-1].strip())
        if "khong-FIRST co co PMU" in line:
            # ... = X.XXXX%
            try:
                info["pmu_pct"] = float(line.split("=")[-1].replace("%", "").strip())
            except ValueError:
                pass
        if "ban ghi co co FIRST" in line:
            try:
                info["first"] = int(line.split(":")[-1].strip())
            except ValueError:
                pass
    return info


def count_tid_records(binpath: str, tids: set[int], t0: int, t1: int) -> dict[int, int]:
    counts = {t: 0 for t in tids}
    first_ts = {t: None for t in tids}
    last_ts = {t: None for t in tids}
    p = subprocess.run(
        ["./bin/rec-export", binpath],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if p.returncode != 0 or not p.stdout:
        return counts, first_ts, last_ts
    lines = p.stdout.splitlines()
    if not lines:
        return counts, first_ts, last_ts
    hdr = lines[0].split(",")
    try:
        itid = hdr.index("tid")
        its = hdr.index("ts_enter")
    except ValueError:
        return counts, first_ts, last_ts
    for line in lines[1:]:
        c = line.split(",")
        if len(c) <= max(itid, its):
            continue
        try:
            tid = int(c[itid])
            ts = int(c[its])
        except ValueError:
            continue
        if tid not in tids:
            continue
        if ts < t0 or ts > t1:
            continue
        counts[tid] += 1
        if first_ts[tid] is None or ts < first_ts[tid]:
            first_ts[tid] = ts
        if last_ts[tid] is None or ts > last_ts[tid]:
            last_ts[tid] = ts
    return counts, first_ts, last_ts


def status_drops(datadir: str) -> tuple[int, int]:
    st = os.path.join(datadir, "status.tsv")
    if not os.path.isfile(st):
        return -1, -1
    lines = [l for l in open(st) if l.strip() and not l.startswith("wall") and not l.startswith("#")]
    if len(lines) < 2:
        return 0, 0
    hdr = lines[0].split("\t")
    last = lines[-1].split("\t")
    d = dict(zip(hdr, last))
    kd = int(float(d.get("kernel_drops_delta") or d.get("kernel_drops") or 0))
    pd = int(float(d.get("proc_drops_delta") or d.get("proc_drops") or 0))
    return kd, pd


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sess", required=True)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--t0", type=int, required=True)
    ap.add_argument("--t1", type=int, required=True)
    ap.add_argument("--tids", required=True, help="csv tids")
    ap.add_argument("--cycles", type=int, required=True)
    ap.add_argument("--min-cycles", type=int, default=20)
    ap.add_argument("--min-recs", type=int, default=100)
    ap.add_argument("--cgroup-substr", default="docker-", help="chuoi phai co trong /proc/pid/cgroup")
    ap.add_argument("--pids-check", default="", help="csv pid con song luc kiem (tuy chon)")
    ap.add_argument("--relax-moc", action="store_true", help="chi can |first-t0|<=1s (thu rut)")
    args = ap.parse_args()

    sess = args.sess
    datadir = os.path.join(sess, "data")
    out = os.path.join(sess, "kiem.txt")
    tids = {int(x) for x in args.tids.split(",") if x.strip()}
    msgs = []
    ok = True

    bins = sorted(glob.glob(os.path.join(datadir, "*.bin")))
    if not bins:
        msgs.append("FAIL: khong co .bin")
        ok = False
        open(out, "w").write("\n".join(msgs) + f"\nok=0\n")
        return 1
    b = max(bins, key=os.path.getsize)

    kd, pd = status_drops(datadir)
    msgs.append(f"drops kernel={kd} proc={pd}")
    if kd != 0 or pd != 0:
        msgs.append("FAIL drops != 0")
        ok = False

    info = rec_stat_info(b)
    msgs.append(f"rec-stat recs={info.get('recs')} pmu_pct={info.get('pmu_pct')} bin={b}")
    pmu = info.get("pmu_pct")
    if pmu != pmu or not (4.0 <= float(pmu) <= 6.0):
        msgs.append(f"FAIL PMU={pmu} ngoai [4,6]")
        ok = False
    else:
        msgs.append("PMU DAT")

    counts, first_ts, last_ts = count_tid_records(b, tids, args.t0, args.t1)
    total = sum(counts.values())
    msgs.append(f"tid_records_total={total} per={counts}")
    if total < args.min_recs:
        msgs.append(f"FAIL n_ban_ghi_tid={total} < {args.min_recs}")
        ok = False
    else:
        msgs.append("n_ban_ghi_tid DAT")

    msgs.append(f"cycles={args.cycles} min={args.min_cycles}")
    if args.cycles < args.min_cycles:
        msgs.append(f"FAIL cycles < {args.min_cycles}")
        ok = False
    else:
        msgs.append("cycles DAT")

    # mốc ±1s
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

    # cgroup check for pids if still alive / from file
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
        if args.cgroup_substr not in txt and "lab0-nginx" not in txt and "docker-" not in txt:
            msgs.append(f"FAIL cgroup pid={pid}: {txt[:200]}")
            cg_ok = False
            ok = False
        else:
            msgs.append(f"cgroup pid={pid}: OK ({txt.strip()[:120]})")
    if cg_ok:
        msgs.append("cgroup DAT (hoac pid da ket thuc)")

    msgs.append(f"ok={1 if ok else 0}")
    open(out, "w").write("\n".join(msgs) + "\n")
    print("\n".join(msgs))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
