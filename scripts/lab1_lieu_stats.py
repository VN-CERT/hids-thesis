#!/usr/bin/env python3
"""Thong ke trung vi thanh phan + Spearman/Pearson cho bo lieu LAB-1. Chi thu vien chuan."""
from __future__ import annotations

import csv
import math
import statistics
import sys
from collections import Counter, defaultdict


def median(xs):
    if not xs:
        return float("nan")
    return statistics.median(xs)


def spearman(xs, ys):
    """Spearman rho; xs, ys cung do dai, khong NaN."""
    n = len(xs)
    if n < 2:
        return float("nan")

    def ranks(a):
        # average ranks for ties
        order = sorted(range(n), key=lambda i: a[i])
        r = [0.0] * n
        i = 0
        while i < n:
            j = i
            while j + 1 < n and a[order[j + 1]] == a[order[i]]:
                j += 1
            avg = (i + j) / 2.0 + 1.0
            for k in range(i, j + 1):
                r[order[k]] = avg
            i = j + 1
        return r

    rx, ry = ranks(xs), ranks(ys)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    denx = math.sqrt(sum((a - mx) ** 2 for a in rx))
    deny = math.sqrt(sum((b - my) ** 2 for b in ry))
    if denx == 0 or deny == 0:
        return float("nan")
    return num / (denx * deny)


def pearson(xs, ys):
    n = len(xs)
    if n < 2:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    num = sum((a - mx) * (b - my) for a, b in zip(xs, ys))
    denx = math.sqrt(sum((a - mx) ** 2 for a in xs))
    deny = math.sqrt(sum((b - my) ** 2 for b in ys))
    if denx == 0 or deny == 0:
        return float("nan")
    return num / (denx * deny)


def summarize_export(path, tid, want_pmu=False):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f):
            if int(r["tid"]) != tid:
                continue
            if int(r["flags"]) & 1:  # FIRST
                continue
            rows.append(r)
    if not rows:
        return None
    cnt = Counter(int(r["syscall_nr"]) for r in rows)
    # uu tien khoang dot: getppid (110, wl cpu) hoac nanosleep (230/35)
    burn_nr = None
    if cnt.get(110, 0) >= 50:
        burn_nr = 110
    elif cnt.get(230, 0) >= 50 or cnt.get(35, 0) >= 50:
        burn_nr = 230 if cnt.get(230, 0) >= cnt.get(35, 0) else 35
    use = [r for r in rows if burn_nr is None or int(r["syscall_nr"]) == burn_nr]
    if want_pmu:
        use = [r for r in use if int(r.get("pmu_ok", 0)) == 1]
    if not use:
        return None
    cpu = [int(r["cpu_ns"]) for r in use]
    steal = [int(r["steal_ns"]) for r in use]
    irq = [int(r["irq_ns"]) for r in use]
    rq = [int(r["rq_ns"]) for r in use]
    # rec-export dung vol_ns (ns); ban cu co the la vol_us
    if "vol_ns" in use[0]:
        vol = [int(r["vol_ns"]) for r in use]
    else:
        vol = [int(r["vol_us"]) * 1000 for r in use]
    out = {
        "n": len(use),
        "cpu_med": median(cpu),
        "steal_med": median(steal),
        "irq_med": median(irq),
        "rq_med": median(rq),
        "vol_ns_med": median(vol),
        "burn_nr": burn_nr,
        "syscall_counts": dict(cnt),
    }
    if want_pmu:
        inst = [int(r["inst"]) for r in use]
        cyc = [int(r["cyc"]) for r in use]
        cpi = [c / i for c, i in zip(cyc, inst) if i > 0]
        out["cpi_med"] = median(cpi) if cpi else float("nan")
        out["inst_med"] = median(inst)
        out["cyc_med"] = median(cyc)
    return out


def main():
    if len(sys.argv) < 2:
        print(
            "cach dung:\n"
            "  lab1_lieu_stats.py summarize <export.csv> <tid> [--pmu]\n"
            "  lab1_lieu_stats.py spearman <levels.csv>  # cot: muc,metric\n"
            "  lab1_lieu_stats.py pearson <pairs.csv>    # cot: x,y\n"
            "  lab1_lieu_stats.py check-d1|check-d3|check-d4|check-e5 <table.tsv>",
            file=sys.stderr,
        )
        sys.exit(2)
    cmd = sys.argv[1]
    if cmd == "summarize":
        path, tid = sys.argv[2], int(sys.argv[3])
        want = "--pmu" in sys.argv
        s = summarize_export(path, tid, want_pmu=want)
        if not s:
            print("EMPTY")
            sys.exit(1)
        for k, v in s.items():
            print(f"{k}\t{v}")
        return
    if cmd == "spearman":
        xs, ys = [], []
        with open(sys.argv[2]) as f:
            for r in csv.DictReader(f, delimiter="\t"):
                xs.append(float(r["muc"]))
                ys.append(float(r["metric"]))
        print(f"spearman\t{spearman(xs, ys)}")
        return
    if cmd == "pearson":
        xs, ys = [], []
        with open(sys.argv[2]) as f:
            for r in csv.DictReader(f, delimiter="\t"):
                xs.append(float(r["x"]))
                ys.append(float(r["y"]))
        print(f"pearson\t{pearson(xs, ys)}")
        return
    if cmd.startswith("check-"):
        # table.tsv: muc \t expected \t other
        # Phu luc 1.2: |Δ other| < max(10% * expected_hi, 100 µs = 100000 ns)
        # expected/other cung don vi ns (D3: expected=cpu_ns, other=rq_ns).
        rows = []
        with open(sys.argv[2]) as f:
            for r in csv.DictReader(f, delimiter="\t"):
                rows.append(r)
        levels = [float(r["muc"]) for r in rows]
        exp = [float(r["expected"]) for r in rows]
        others = [float(r["other"]) for r in rows]
        rho = spearman(levels, exp)
        other_lo = others[0]
        other_hi = others[-1]
        delta_other = abs(other_hi - other_lo)
        exp_hi = exp[-1]
        thresh = max(0.10 * abs(exp_hi), 100_000.0)  # 100 µs
        print(f"spearman_expected\t{rho}")
        print(f"delta_other_ns\t{delta_other}")
        print(f"expected_hi_ns\t{exp_hi}")
        print(f"thresh_ns\t{thresh}")
        print(f"other_lo\t{other_lo}")
        print(f"other_hi\t{other_hi}")
        ok_s = rho >= 0.9
        ok_o = delta_other < thresh
        print(f"tieu_chi_spearman>=0.9\t{'DAT' if ok_s else 'KHONG_DAT'}")
        print(f"tieu_chi_other_phuluc12\t{'DAT' if ok_o else 'KHONG_DAT'}")
        sys.exit(0 if (ok_s and ok_o) else 1)
    print(f"lenh khong biet: {cmd}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
