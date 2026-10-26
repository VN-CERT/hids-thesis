#!/usr/bin/env python3
"""c5_extract.py - trich dac trung STREAMING tu rec-export (CSV/TSV theo TEN cot).

Mot luot doc, bo nho O(so tid + so cgroup) * cua so (giu deque trong ~300s).
Cua so 300 s, buoc 30 s; >= 5 ban ghi / cua so (khop detector_c5.py v1.1).

Nhanh:
  BASELINE_dt_tho, PHANRA_5tp — dung dinh nghia detector_c5.py v1.1 (gom ctx_*).
  AGG_cgroup_giay — theo cgroup, mau 1 Hz (tong cpu, tong own, so syscall, so tid);
    tren cua so 300 s: syscall_rate_mean/cv, cpu_rate_mean/cv, own_rate_mean/cv, tids_mean.

Ghi TSV dau ra (tieu de) cho c5_score.py:
  branch tid start_ns stop_ns <cac cot...>
  (nhanh AGG: cot tid = cgroup_id)

Cach dung:
  python3 analysis/c5_extract.py --tsv FILE.csv [--out OUT.tsv]
          [--window-s 300] [--step-s 30] [--branches BASELINE_dt_tho,PHANRA_5tp,AGG_cgroup_giay]
          [--source TEN]   # them cot nguon neu set
"""
from __future__ import annotations

import argparse
import csv
import math
import sys
from collections import deque

WINDOW_S_DEFAULT = 300
STEP_S_DEFAULT = 30
FLAG_PMU = 1 << 7
MIN_RECS = 5
MIN_DTS = 4

DIMS_BASE = ["dt_med", "dt_p90", "dt_iqr", "dt_cv"]
DIMS_DEC = [
    "own_med", "own_p90", "own_iqr", "own_cv",
    "cpu_med", "cpu_p90", "cpi_med",
    "ctx_steal_med", "ctx_steal_p90",
    "ctx_irq_med", "ctx_irq_p90",
    "ctx_rq_med", "ctx_rq_p90",
]
DIMS_AGG = [
    "syscall_rate_mean", "syscall_rate_cv",
    "cpu_rate_mean", "cpu_rate_cv",
    "own_rate_mean", "own_rate_cv",
    "tids_mean",
]


def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return float("nan")
    if n % 2:
        return s[n // 2]
    return 0.5 * (s[n // 2 - 1] + s[n // 2])


def pct(xs, q):
    s = sorted(xs)
    if not s:
        return float("nan")
    k = max(0, math.ceil(q * len(s)) - 1)
    return s[k]


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def sd(xs):
    if len(xs) < 2:
        return float("nan")
    m = mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


def cv(xs):
    m = mean(xs)
    if m == 0 or m != m:
        return float("nan")
    return sd(xs) / m


def feat_baseline(chunk):
    ts = [r["ts"] for r in chunk]
    dts = [ts[i] - ts[i - 1] for i in range(1, len(ts)) if ts[i] >= ts[i - 1]]
    if len(dts) < MIN_DTS:
        return None
    return {
        "dt_med": median(dts),
        "dt_p90": pct(dts, 0.90),
        "dt_iqr": pct(dts, 0.75) - pct(dts, 0.25),
        "dt_cv": cv(dts),
    }


def feat_decomp(chunk):
    f = {}
    ts = [r["ts"] for r in chunk]
    owns = []
    for i in range(1, len(chunk)):
        dt = ts[i] - ts[i - 1]
        if dt < 0:
            continue
        r = chunk[i]
        owns.append(max(0, dt - r["rq"] - r["steal"] - r["irq"]))
    if len(owns) < MIN_DTS:
        return None
    f["own_med"] = median(owns)
    f["own_p90"] = pct(owns, 0.90)
    f["own_iqr"] = pct(owns, 0.75) - pct(owns, 0.25)
    f["own_cv"] = cv(owns)
    cpus = [r["cpu"] for r in chunk]
    f["cpu_med"] = median(cpus)
    f["cpu_p90"] = pct(cpus, 0.90)
    cpis = [r["cyc"] / r["inst"] for r in chunk
            if (r["flags"] & FLAG_PMU) and r["inst"] > 0]
    f["cpi_med"] = median(cpis) if cpis else float("nan")
    for comp in ("steal", "irq", "rq"):
        vals = [r[comp] for r in chunk]
        f["ctx_" + comp + "_med"] = median(vals)
        f["ctx_" + comp + "_p90"] = pct(vals, 0.90)
    return f


def fmt_val(v):
    if v != v:
        return "nan"
    if isinstance(v, float) and abs(v - round(v)) < 1e-9 and abs(v) < 1e15:
        return str(int(round(v))) if abs(v) >= 1e6 else ("%.6g" % v)
    if isinstance(v, float):
        return "%.10g" % v
    return str(v)


class TidState:
    __slots__ = ("recs", "origin", "next_start")

    def __init__(self):
        self.recs = deque()
        self.origin = None
        self.next_start = None


def slice_chunk(recs, start, stop):
    # recs sorted by ts
    out = []
    for r in recs:
        if r["ts"] < start:
            continue
        if r["ts"] >= stop:
            break
        out.append(r)
    return out


def emit_tid_windows(st, window_ns, step_ns, want_base, want_dec, out_rows, final=False):
    """Phat cua so. Khop detector: start <= t_end. Moi tid ts don dieu trong luong
    => cua so [start,stop) an toan khi last_ts >= stop (hoac final=EOF)."""
    if st.origin is None or not st.recs:
        return
    t_end = st.recs[-1]["ts"]
    while st.next_start <= t_end:
        start = st.next_start
        stop = start + window_ns
        if not final and t_end < stop:
            break
        chunk = slice_chunk(st.recs, start, stop)
        if len(chunk) >= MIN_RECS:
            tid = chunk[0]["tid"]
            if want_base:
                f = feat_baseline(chunk)
                if f is not None:
                    out_rows.append(("BASELINE_dt_tho", tid, start, stop, f))
            if want_dec:
                f = feat_decomp(chunk)
                if f is not None:
                    out_rows.append(("PHANRA_5tp", tid, start, stop, f))
        st.next_start += step_ns
        while st.recs and st.recs[0]["ts"] < st.next_start:
            st.recs.popleft()


class CgroupAgg:
    """Mau 1 Hz theo cgroup: tong cpu, tong own (xap xi), so syscall, so tid."""
    __slots__ = ("sec", "cpu", "own", "n_sys", "tids")

    def __init__(self):
        # sec -> dict
        self.sec = {}

    def add(self, r, prev_ts):
        s = r["ts"] // 1_000_000_000
        slot = self.sec.get(s)
        if slot is None:
            slot = {"cpu": 0, "own": 0, "n": 0, "tids": set()}
            self.sec[s] = slot
        slot["cpu"] += r["cpu"]
        slot["n"] += 1
        slot["tids"].add(r["tid"])
        if prev_ts is not None and r["ts"] >= prev_ts:
            dt = r["ts"] - prev_ts
            own = max(0, dt - r["rq"] - r["steal"] - r["irq"])
            slot["own"] += own

    def feat_windows(self, cg, window_s, step_s, out_rows):
        if not self.sec:
            return
        secs = sorted(self.sec.keys())
        t0, t1 = secs[0], secs[-1]
        start = t0
        while start <= t1:
            stop = start + window_s
            rates_sys, rates_cpu, rates_own, tids = [], [], [], []
            for s in range(start, stop):
                slot = self.sec.get(s)
                if not slot:
                    rates_sys.append(0.0)
                    rates_cpu.append(0.0)
                    rates_own.append(0.0)
                    tids.append(0.0)
                else:
                    rates_sys.append(float(slot["n"]))
                    rates_cpu.append(float(slot["cpu"]))
                    rates_own.append(float(slot["own"]))
                    tids.append(float(len(slot["tids"])))
            # can >= 5 giay co it nhat 1 syscall? PROMPT: cua so >= 5 ban ghi
            n_rec = sum(self.sec[s]["n"] for s in range(start, stop) if s in self.sec)
            if n_rec >= MIN_RECS:
                f = {
                    "syscall_rate_mean": mean(rates_sys),
                    "syscall_rate_cv": cv(rates_sys),
                    "cpu_rate_mean": mean(rates_cpu),
                    "cpu_rate_cv": cv(rates_cpu),
                    "own_rate_mean": mean(rates_own),
                    "own_rate_cv": cv(rates_own),
                    "tids_mean": mean(tids),
                }
                out_rows.append((
                    "AGG_cgroup_giay", cg,
                    start * 1_000_000_000, stop * 1_000_000_000, f,
                ))
            start += step_s


def open_table(path):
    fh = open(path, encoding="utf-8", errors="replace", newline="")
    sample = fh.read(4096)
    fh.seek(0)
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters="\t,")
    except csv.Error:
        dialect = csv.excel_tab if "\t" in sample.split("\n", 1)[0] else csv.excel
    return fh, csv.DictReader(fh, dialect=dialect)


def parse_row(row):
    def gi(name, default=0):
        v = row.get(name, "")
        if v is None or v == "":
            return default
        return int(v)

    return {
        "ts": gi("ts_enter"),
        "tid": gi("tid"),
        "cg": gi("cgroup_id", 0),
        "flags": gi("flags"),
        "cpu": gi("cpu_ns"),
        "steal": gi("steal_ns"),
        "irq": gi("irq_ns"),
        "rq": gi("rq_ns"),
        "inst": gi("inst"),
        "cyc": gi("cyc"),
    }


def extract(path, window_s, step_s, branches, source=None):
    window_ns = window_s * 1_000_000_000
    step_ns = step_s * 1_000_000_000
    want_base = "BASELINE_dt_tho" in branches
    want_dec = "PHANRA_5tp" in branches
    want_agg = "AGG_cgroup_giay" in branches

    fh, reader = open_table(path)
    need = ["ts_enter", "tid", "flags", "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "inst", "cyc"]
    for k in need:
        if k not in reader.fieldnames:
            fh.close()
            sys.exit("TSV/CSV thieu cot '%s'. Cot co: %s" % (k, reader.fieldnames))

    tids = {}
    last_ts_tid = {}  # for own in AGG
    aggs = {}
    out_rows = []
    watermark = 0

    try:
        for row in reader:
            try:
                r = parse_row(row)
            except ValueError:
                continue
            if r["ts"] <= 0:
                continue
            watermark = max(watermark, r["ts"])
            tid = r["tid"]
            st = tids.get(tid)
            if st is None:
                st = TidState()
                tids[tid] = st
            if st.origin is None:
                st.origin = r["ts"]
                st.next_start = r["ts"]
            st.recs.append(r)
            if want_base or want_dec:
                emit_tid_windows(st, window_ns, step_ns, want_base, want_dec, out_rows, final=False)
            if want_agg:
                cg = r["cg"]
                ag = aggs.get(cg)
                if ag is None:
                    ag = CgroupAgg()
                    aggs[cg] = ag
                prev = last_ts_tid.get(tid)
                ag.add(r, prev)
                last_ts_tid[tid] = r["ts"]
    finally:
        fh.close()

    if want_base or want_dec:
        for st in tids.values():
            emit_tid_windows(st, window_ns, step_ns, want_base, want_dec, out_rows, final=True)
    if want_agg:
        for cg, ag in aggs.items():
            ag.feat_windows(cg, window_s, step_s, out_rows)

    return out_rows


def write_features(out_rows, out_path, source=None):
    # union dims theo thu tu on dinh
    dim_order = list(DIMS_BASE) + list(DIMS_DEC) + list(DIMS_AGG)
    seen = set(dim_order)
    for _, _, _, _, f in out_rows:
        for k in f:
            if k not in seen:
                dim_order.append(k)
                seen.add(k)
    header = ["branch", "tid", "start_ns", "stop_ns"] + dim_order
    if source is not None:
        header.append("nguon")

    def write(fh):
        fh.write("\t".join(header) + "\n")
        for branch, tid, start, stop, f in out_rows:
            row = [branch, str(tid), str(start), str(stop)]
            for d in dim_order:
                row.append(fmt_val(f[d]) if d in f else "nan")
            if source is not None:
                row.append(source)
            fh.write("\t".join(row) + "\n")

    if out_path:
        with open(out_path, "w", encoding="utf-8") as fh:
            write(fh)
    else:
        write(sys.stdout)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", required=True, help="CSV/TSV tu rec-export")
    ap.add_argument("--out", default=None)
    ap.add_argument("--window-s", type=int, default=WINDOW_S_DEFAULT)
    ap.add_argument("--step-s", type=int, default=STEP_S_DEFAULT)
    ap.add_argument("--branches", default="BASELINE_dt_tho,PHANRA_5tp,AGG_cgroup_giay")
    ap.add_argument("--source", default=None, help="them cot nguon")
    a = ap.parse_args(argv[1:])
    branches = [b.strip() for b in a.branches.split(",") if b.strip()]
    rows = extract(a.tsv, a.window_s, a.step_s, branches, a.source)
    write_features(rows, a.out, a.source)
    print("# c5_extract  cua_so=%ds buoc=%ds  so_cua_so=%d  nhanh=%s" %
          (a.window_s, a.step_s, len(rows), ",".join(branches)), file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
