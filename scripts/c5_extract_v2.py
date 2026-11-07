#!/usr/bin/env python3
"""c5_extract_v2.py - ban sao c5_extract.py + cot sieu tap x_* (M6i-c1).

GIU NGUYEN moi cot cu (thu tu, ten, gia tri). Noi them o cuoi:
  n, cgroup_id, x_vol_*, x_arr_*, x_blk, x_*_sum, x_n_pmu, x_inst_med, x_cyc_med.
BASELINE_dt_tho va PHANRA_5tp: day du cot moi (cung gia tri tren cung cua so).
AGG_cgroup_giay: chi them n va cgroup_id; cac cot x_* = nan.

Khong sua scripts/c5_extract.py (v1).
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
DIMS_EXTRA = [
    "n", "cgroup_id",
    "x_vol_med", "x_vol_p90", "x_vol_iqr", "x_vol_cv",
    "x_arr_med", "x_arr_p90", "x_arr_iqr", "x_arr_cv",
    "x_blk",
    "x_dt_sum", "x_cpu_sum", "x_rq_sum", "x_steal_sum", "x_irq_sum", "x_vol_sum",
    "x_n_pmu", "x_inst_med", "x_cyc_med",
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


def feat_extras(chunk):
    """Cot sieu tap chung cho BASELINE/PHANRA tren cung cua so."""
    n = len(chunk)
    out = {
        "n": float(n),
        "cgroup_id": float(chunk[0]["cg"]),
    }
    vols = []
    wakes = []
    n_blk = 0
    n_int = 0
    dt_sum = cpu_sum = rq_sum = steal_sum = irq_sum = vol_sum = 0
    for i in range(1, n):
        prev = chunk[i - 1]
        r = chunk[i]
        dt = r["ts"] - prev["ts"]
        if dt < 0:
            continue
        n_int += 1
        vol_ns = r["vol_us"] * 1000
        vols.append(vol_ns)
        vol_sum += vol_ns
        dt_sum += dt
        cpu_sum += r["cpu"]
        rq_sum += r["rq"]
        steal_sum += r["steal"]
        irq_sum += r["irq"]
        if r["vol_us"] > 0:
            n_blk += 1
            a = prev["ts"] + vol_ns
            if a > r["ts"]:
                a = r["ts"]
            wakes.append(a)
    if vols:
        out["x_vol_med"] = median(vols)
        out["x_vol_p90"] = pct(vols, 0.90)
        out["x_vol_iqr"] = pct(vols, 0.75) - pct(vols, 0.25)
        out["x_vol_cv"] = cv(vols)
    else:
        out["x_vol_med"] = out["x_vol_p90"] = out["x_vol_iqr"] = out["x_vol_cv"] = float("nan")
    if len(wakes) >= 5:  # >= 4 hieu => >= 5 moc
        arrs = [wakes[i] - wakes[i - 1] for i in range(1, len(wakes))]
        if len(arrs) >= 4:
            out["x_arr_med"] = median(arrs)
            out["x_arr_p90"] = pct(arrs, 0.90)
            out["x_arr_iqr"] = pct(arrs, 0.75) - pct(arrs, 0.25)
            out["x_arr_cv"] = cv(arrs)
        else:
            out["x_arr_med"] = out["x_arr_p90"] = out["x_arr_iqr"] = out["x_arr_cv"] = float("nan")
    else:
        out["x_arr_med"] = out["x_arr_p90"] = out["x_arr_iqr"] = out["x_arr_cv"] = float("nan")
    out["x_blk"] = (n_blk / n_int) if n_int else float("nan")
    out["x_dt_sum"] = float(dt_sum)
    out["x_cpu_sum"] = float(cpu_sum)
    out["x_rq_sum"] = float(rq_sum)
    out["x_steal_sum"] = float(steal_sum)
    out["x_irq_sum"] = float(irq_sum)
    out["x_vol_sum"] = float(vol_sum)
    pmu_inst = []
    pmu_cyc = []
    for r in chunk:
        if r["flags"] & FLAG_PMU:
            pmu_inst.append(r["inst"])
            pmu_cyc.append(r["cyc"])
    out["x_n_pmu"] = float(len(pmu_inst))
    out["x_inst_med"] = median(pmu_inst) if pmu_inst else float("nan")
    out["x_cyc_med"] = median(pmu_cyc) if pmu_cyc else float("nan")
    return out


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
            extras = None
            if want_base:
                f = feat_baseline(chunk)
                if f is not None:
                    if extras is None:
                        extras = feat_extras(chunk)
                    f.update(extras)
                    out_rows.append(("BASELINE_dt_tho", tid, start, stop, f))
            if want_dec:
                f = feat_decomp(chunk)
                if f is not None:
                    if extras is None:
                        extras = feat_extras(chunk)
                    f.update(extras)
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
                    "n": float(n_rec),
                    "cgroup_id": float(cg),
                }
                out_rows.append((
                    "AGG_cgroup_giay", cg,
                    start * 1_000_000_000, stop * 1_000_000_000, f,
                ))
            start += step_s


def open_table(path):
    if path == "-":
        return None, csv.DictReader(sys.stdin)
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
        "vol_us": gi("vol_us", 0),
        "inst": gi("inst"),
        "cyc": gi("cyc"),
    }


def extract(path, window_s, step_s, branches, source=None, t_min=None, t_max=None):
    window_ns = window_s * 1_000_000_000
    step_ns = step_s * 1_000_000_000
    want_base = "BASELINE_dt_tho" in branches
    want_dec = "PHANRA_5tp" in branches
    want_agg = "AGG_cgroup_giay" in branches

    fh, reader = open_table(path)
    need = ["ts_enter", "tid", "cgroup_id", "flags", "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_us", "inst", "cyc"]
    for k in need:
        if k not in reader.fieldnames:
            fh.close()
            sys.exit("TSV/CSV thieu cot '%s'. Cot co: %s" % (k, reader.fieldnames))

    tids = {}
    last_ts_tid = {}  # for own in AGG
    aggs = {}
    out_rows = []
    watermark = 0
    n_kept = 0
    n_skip_window = 0

    try:
        for row in reader:
            try:
                r = parse_row(row)
            except ValueError:
                continue
            if r["ts"] <= 0:
                continue
            if t_min is not None and r["ts"] < t_min:
                n_skip_window += 1
                continue
            if t_max is not None and r["ts"] >= t_max:
                n_skip_window += 1
                continue
            n_kept += 1
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
        if fh is not None:
            fh.close()
    print("# c5_extract_v2  giu=%d bo_qua_ngoai_7ngay=%d" % (n_kept, n_skip_window), file=sys.stderr)

    if want_base or want_dec:
        for st in tids.values():
            emit_tid_windows(st, window_ns, step_ns, want_base, want_dec, out_rows, final=True)
    if want_agg:
        for cg, ag in aggs.items():
            ag.feat_windows(cg, window_s, step_s, out_rows)

    return out_rows


def write_features(out_rows, out_path, source=None):
    # union dims theo thu tu on dinh
    dim_order = list(DIMS_BASE) + list(DIMS_DEC) + list(DIMS_AGG) + list(DIMS_EXTRA)
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
    ap.add_argument("--t-min", type=int, default=None, help="bo ban ghi ts < t-min")
    ap.add_argument("--t-max", type=int, default=None, help="bo ban ghi ts >= t-max")
    a = ap.parse_args(argv[1:])
    branches = [b.strip() for b in a.branches.split(",") if b.strip()]
    rows = extract(a.tsv, a.window_s, a.step_s, branches, a.source, a.t_min, a.t_max)
    write_features(rows, a.out, a.source)
    print("# c5_extract_v2  cua_so=%ds buoc=%ds  so_cua_so=%d  nhanh=%s" %
          (a.window_s, a.step_s, len(rows), ",".join(branches)), file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv)
