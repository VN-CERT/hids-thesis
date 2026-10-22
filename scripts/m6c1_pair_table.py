#!/usr/bin/env python3
"""M6c-1 muc 3d: bang hieu rq theo cap ghep moc thoi gian (cung phuong phap
m6b13_pair.py cua R031 B3'): cap (W_i, S_i) tu log bpftrace su kien, gan vao
khoang collector chua S_i; chi giu khoang chua dung 1 cap va preempt = 0 trong
cua so (from, to]. hieu = rq_bpftrace - rq_collector (us) = (S-W) - rq_ns.
In: so cap, trung vi, p10, p90 cua hieu (us), lech tong %.
"""
import argparse
import bisect
import csv
import statistics
import subprocess


def pct(vals, q):
    if not vals:
        return float("nan")
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round(q * (len(s) - 1)))))
    return s[k]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--btlog", required=True)
    ap.add_argument("--bin", required=True, dest="binpath")
    ap.add_argument("--tid", required=True, type=int)
    ap.add_argument("--from", required=True, type=int, dest="t_from")
    ap.add_argument("--to", required=True, type=int, dest="t_to")
    ap.add_argument("--label", default="")
    ap.add_argument("--rec-export", default="./bin/rec-export")
    args = ap.parse_args()

    events = []
    with open(args.btlog, errors="replace") as f:
        for line in f:
            p = line.split()
            if len(p) == 4 and p[0] == "W":
                events.append((int(p[1]), "W"))
            elif len(p) == 3 and p[0] in ("S", "P"):
                events.append((int(p[1]), p[0]))
    events.sort(key=lambda e: e[0])

    pairs = []
    p_ts = []
    pending = None
    for ts, kind in events:
        if kind == "W":
            if pending is None:
                pending = ts
        elif kind == "S":
            if pending is not None:
                pairs.append((pending, ts))
                pending = None
        else:
            p_ts.append(ts)

    out = subprocess.run([args.rec_export, args.binpath],
                         capture_output=True, text=True, check=True).stdout
    recs = []
    for row in csv.DictReader(out.splitlines()):
        if int(row["tid"]) != args.tid:
            continue
        recs.append({"ts": int(row["ts_enter"]), "rq": int(row["rq_ns"]),
                     "n_pair": 0, "pair_dur": 0, "n_preempt": 0})
    recs.sort(key=lambda r: r["ts"])
    ts_list = [r["ts"] for r in recs]
    for w_ts, s_ts in pairs:
        i = bisect.bisect_left(ts_list, s_ts)
        if i < len(recs):
            recs[i]["n_pair"] += 1
            recs[i]["pair_dur"] += s_ts - w_ts
    for t in p_ts:
        i = bisect.bisect_left(ts_list, t)
        if i < len(recs):
            recs[i]["n_preempt"] += 1

    diffs_us = []
    sum_bt = sum_coll = 0
    for r in recs:
        if not (args.t_from < r["ts"] <= args.t_to):
            continue
        if r["n_pair"] == 1 and r["n_preempt"] == 0:
            diffs_us.append((r["pair_dur"] - r["rq"]) / 1000.0)
            sum_bt += r["pair_dur"]
            sum_coll += r["rq"]
    tot_pct = ((sum_bt - sum_coll) / sum_coll * 100.0) if sum_coll else float("nan")
    print(f"{args.label}\tn={len(diffs_us)}\tmedian_us={statistics.median(diffs_us) if diffs_us else float('nan'):.3f}"
          f"\tp10_us={pct(diffs_us, 0.10):.3f}\tp90_us={pct(diffs_us, 0.90):.3f}"
          f"\tlech_tong_pct={tot_pct:+.2f}")


if __name__ == "__main__":
    main()
