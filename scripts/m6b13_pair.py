#!/usr/bin/env python3
"""M6b-1.3 B3': ghep cap wakeup bpftrace voi khoang collector theo MOC THOI GIAN.

- bpftrace log che do su kien (G3_BT_EVENTS=1): dong "W mono_ns cpu_probe target_cpu",
  "S mono_ns cpu", "P mono_ns cpu".
- Cap (W_i, S_i): S_i la switch-in dau tien cua tid dich SAU W_i. Giu nguyen W dau
  tien dang cho (giong ngu nghia @w cua chuong trinh tong hop); W den khi dang co W
  cho thi dem la wakeup thua, khong tao cap.
- Ban ghi collector (bin/rec-export): khoang cua ban ghi i la (ts_enter_truoc, ts_enter].
  Cap duoc gan vao khoang chua S_i. Preempt cua khoang = so su kien P roi vao khoang.
- Phan loc: khoang chua DUNG MOT cap va preempt = 0 -> d = rq_ns - (S_i - W_i).
"""
import argparse
import csv
import statistics
import subprocess
import sys


def pct90(vals):
    if not vals:
        return None
    s = sorted(vals)
    k = max(0, (9 * len(s) + 9) // 10 - 1)  # nearest-rank p90
    return s[k]


def stats(name, vals):
    if not vals:
        print(f"{name}: n=0")
        return
    print(
        f"{name}: n={len(vals)} mean={statistics.fmean(vals):.1f} ns "
        f"median={statistics.median(vals):.1f} ns p90={pct90(vals)} ns "
        f"max={max(vals)} ns min={min(vals)} ns sum={sum(vals)} ns"
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--btlog", required=True)
    ap.add_argument("--bin", required=True, dest="binpath")
    ap.add_argument("--tid", required=True, type=int)
    ap.add_argument("--from", required=True, type=int, dest="t_from")
    ap.add_argument("--to", required=True, type=int, dest="t_to")
    ap.add_argument("--rec-export", default="./bin/rec-export")
    args = ap.parse_args()

    events = []  # (ts, kind, a, b)
    agg = {}
    with open(args.btlog, errors="replace") as f:
        for line in f:
            p = line.split()
            if len(p) == 4 and p[0] == "W":
                events.append((int(p[1]), "W", int(p[2]), int(p[3])))
            elif len(p) == 3 and p[0] == "S":
                events.append((int(p[1]), "S", int(p[2]), 0))
            elif len(p) == 3 and p[0] == "P":
                events.append((int(p[1]), "P", int(p[2]), 0))
            elif p and p[0].startswith("@"):
                agg[p[0].rstrip(":")] = p[-1]
    events.sort(key=lambda e: e[0])
    print(f"su kien: W={sum(1 for e in events if e[1]=='W')} "
          f"S={sum(1 for e in events if e[1]=='S')} P={sum(1 for e in events if e[1]=='P')}")
    for k in ("@rq_sau_wakeup_ns", "@so_lan", "@rq_sau_preempt_ns", "@so_lan_preempt", "@rq_tong_ns"):
        if k in agg:
            print(f"bpftrace tong hop {k} = {agg[k]}")

    pairs = []  # (w_ts, s_ts, w_cpu_probe, w_target_cpu, s_cpu)
    pending = None
    extra_w = s_no_w = 0
    p_ts = []
    for ts, kind, a, b in events:
        if kind == "W":
            if pending is None:
                pending = (ts, a, b)
            else:
                extra_w += 1
        elif kind == "S":
            if pending is not None:
                pairs.append((pending[0], ts, pending[1], pending[2], a))
                pending = None
            else:
                s_no_w += 1
        else:
            p_ts.append(ts)
    print(f"cap (W,S) ghep duoc: {len(pairs)}; wakeup thua khi dang co W cho: {extra_w}; "
          f"S khong co W cho: {s_no_w}; W con cho den cuoi: {1 if pending else 0}")

    out = subprocess.run(
        [args.rec_export, args.binpath], capture_output=True, text=True, check=True
    ).stdout
    recs = []
    for row in csv.DictReader(out.splitlines()):
        if int(row["tid"]) != args.tid:
            continue
        recs.append(
            {
                "ts": int(row["ts_enter"]),
                "flags": int(row["flags"]),
                "rq": int(row["rq_ns"]),
                "vol": int(row["vol_ns"]),
            }
        )
    recs.sort(key=lambda r: r["ts"])
    print(f"ban ghi collector cua tid {args.tid}: tong {len(recs)}")

    # Gan cap vao khoang chua S (theo ts_enter cua ban ghi, khong dung thu tu cap).
    import bisect

    ts_list = [r["ts"] for r in recs]
    for r in recs:
        r["n_pair"] = 0
        r["pair_dur"] = 0
        r["n_preempt"] = 0
    unassigned = 0
    for w_ts, s_ts, wcpu, wtcpu, scpu in pairs:
        i = bisect.bisect_left(ts_list, s_ts)
        if i >= len(recs):
            unassigned += 1
            continue
        r = recs[i]
        r["n_pair"] += 1
        r["pair_dur"] += s_ts - w_ts
        r.setdefault("pair_list", []).append((w_ts, s_ts, wcpu, wtcpu))
    for t in p_ts:
        i = bisect.bisect_left(ts_list, t)
        if i < len(recs):
            recs[i]["n_preempt"] += 1
    print(f"cap khong roi vao khoang collector nao (S sau ban ghi cuoi): {unassigned}")

    win = [r for r in recs if args.t_from < r["ts"] <= args.t_to]
    pairs_win = [p for p in pairs if args.t_from < p[1] <= args.t_to]
    print(f"--- trong cua so ({args.t_from}, {args.t_to}] ---")
    print(f"tong cho sau wakeup bpftrace (cap co S trong cua so): {sum(p[1]-p[0] for p in pairs_win)} ns "
          f"({len(pairs_win)} cap)")
    print(f"tong rq_ns collector (ban ghi trong cua so): {sum(r['rq'] for r in win)} ns "
          f"({len(win)} ban ghi)")
    print(f"tong rq_ns collector (tat ca ban ghi cua tid): {sum(r['rq'] for r in recs)} ns")
    print(f"tong cho bpftrace (tat ca cap): {sum(p[1]-p[0] for p in pairs)} ns ({len(pairs)} cap)")

    filt = []
    for r in win:
        if r["n_pair"] == 1 and r["n_preempt"] == 0 and r.get("pair_list"):
            w_ts, s_ts, wcpu, wtcpu = r["pair_list"][0]
            filt.append(
                {
                    "d": r["rq"] - (s_ts - w_ts),
                    "same_cpu": wcpu == wtcpu,
                    "migrated": bool(r["flags"] & 0x8),
                }
            )
    print(f"--- phan loc: khoang chua dung 1 cap, preempt = 0: {len(filt)} khoang ---")
    stats("d = rq_ns - (S-W) tat ca", [f["d"] for f in filt])
    stats("d wakeup cung CPU (cpu_probe == target_cpu)", [f["d"] for f in filt if f["same_cpu"]])
    stats("d wakeup khac CPU", [f["d"] for f in filt if not f["same_cpu"]])
    stats("d ban ghi MIGRATED", [f["d"] for f in filt if f["migrated"]])
    stats("d ban ghi khong MIGRATED", [f["d"] for f in filt if not f["migrated"]])
    multi = sum(1 for r in win if r["n_pair"] > 1)
    withp = sum(1 for r in win if r["n_preempt"] > 0)
    print(f"khoang trong cua so co >1 cap: {multi}; co preempt: {withp}")


if __name__ == "__main__":
    main()
