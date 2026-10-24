#!/usr/bin/env python3
"""Thong ke trung vi / ti le tong + Spearman/Pearson cho bo lieu LAB-1. Chi thu vien chuan."""
from __future__ import annotations

import csv
import math
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path


def median(xs):
    if not xs:
        return float("nan")
    return statistics.median(xs)


def p90(xs):
    if not xs:
        return float("nan")
    if len(xs) == 1:
        return float(xs[0])
    # statistics.quantiles n=10 → 9 cut points; index 8 = p90
    return float(statistics.quantiles(xs, n=10)[8])


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
    # Δt: uu tien cot dt_ns; khong co thi tong 5 thanh phan
    if "dt_ns" in use[0] and use[0].get("dt_ns", "") != "":
        dt = [int(r["dt_ns"]) for r in use]
    else:
        dt = [c + s + i + q + v for c, s, i, q, v in zip(cpu, steal, irq, rq, vol)]
    sum_cpu, sum_steal, sum_irq, sum_rq, sum_vol, sum_dt = (
        sum(cpu),
        sum(steal),
        sum(irq),
        sum(rq),
        sum(vol),
        sum(dt),
    )
    out = {
        "n": len(use),
        "cpu_med": median(cpu),
        "steal_med": median(steal),
        "irq_med": median(irq),
        "rq_med": median(rq),
        "vol_ns_med": median(vol),
        "rq_p90": p90(rq),
        "steal_p90": p90(steal),
        "sum_cpu_ns": sum_cpu,
        "sum_steal_ns": sum_steal,
        "sum_irq_ns": sum_irq,
        "sum_rq_ns": sum_rq,
        "sum_vol_ns": sum_vol,
        "sum_dt_ns": sum_dt,
        # Phu luc 1.6: ti le tong tren ca luot
        "cpu_ratio": (sum_cpu / sum_dt) if sum_dt else float("nan"),
        "steal_ratio": (sum_steal / sum_dt) if sum_dt else float("nan"),
        "irq_ratio": (sum_irq / sum_dt) if sum_dt else float("nan"),
        "rq_ratio": (sum_rq / sum_dt) if sum_dt else float("nan"),
        "vol_ratio": (sum_vol / sum_dt) if sum_dt else float("nan"),
        "steal_over_rq": (abs(sum_steal) / sum_rq) if sum_rq else float("nan"),
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


def check_table(path, ratio_mode=False):
    # table.tsv: muc \t expected \t other
    # Phu luc 1.2 (trung vi, don vi ns): |Δ other| < max(10% * expected_hi, 100 µs)
    # Phu luc 1.6 (ti le tong, khong thuoc ns): |Δ other| < max(10% * expected_hi, 1e-5)
    rows = []
    with open(path) as f:
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
    floor = 1e-5 if ratio_mode else 100_000.0
    thresh = max(0.10 * abs(exp_hi), floor)
    print(f"spearman_expected\t{rho}")
    if ratio_mode:
        print(f"delta_other_ratio\t{delta_other}")
        print(f"expected_hi_ratio\t{exp_hi}")
        print(f"thresh_ratio\t{thresh}")
    else:
        print(f"delta_other_ns\t{delta_other}")
        print(f"expected_hi_ns\t{exp_hi}")
        print(f"thresh_ns\t{thresh}")
    print(f"other_lo\t{other_lo}")
    print(f"other_hi\t{other_hi}")
    ok_s = rho >= 0.9
    ok_o = delta_other < thresh
    print(f"tieu_chi_spearman>=0.9\t{'DAT' if ok_s else 'KHONG_DAT'}")
    print(f"tieu_chi_other_phuluc12\t{'DAT' if ok_o else 'KHONG_DAT'}")
    return ok_s and ok_o


def rescore_d4_e5_v16(d4_root: Path):
    """Cham lai D4 + E5 tu 12 luot D4 (phu luc 1.6)."""
    tags = [("nolimit", 0, "none"), ("q75", 1, "75"), ("q50", 2, "50"), ("q25", 3, "25")]
    run_rows = []
    for tag, muc, quota in tags:
        for run in (1, 2, 3):
            d = d4_root / tag / f"run{run}"
            exp = d / "export.csv"
            kq = d / "ketqua.txt"
            if not exp.is_file():
                raise SystemExit(f"thieu {exp}")
            # tid tu dong dau export
            with exp.open() as f:
                r0 = next(csv.DictReader(f))
            tid = int(r0["tid"])
            s = summarize_export(str(exp), tid, want_pmu=False)
            if not s:
                raise SystemExit(f"EMPTY {exp}")
            thr = 0
            nr = 0
            if kq.is_file():
                for line in kq.read_text().splitlines():
                    if line.startswith("throttled_usec_delta="):
                        thr = int(line.split("=", 1)[1])
                    if line.startswith("nr_throttled_delta="):
                        nr = int(line.split("=", 1)[1])
            run_rows.append(
                {
                    "tag": tag,
                    "muc": muc,
                    "quota": quota,
                    "run": run,
                    "rq_ratio": s["rq_ratio"],
                    "steal_ratio": s["steal_ratio"],
                    "rq_p90": s["rq_p90"],
                    "sum_rq_ns": s["sum_rq_ns"],
                    "sum_steal_ns": s["sum_steal_ns"],
                    "sum_dt_ns": s["sum_dt_ns"],
                    "steal_over_rq": s["steal_over_rq"],
                    "thr_usec": thr,
                    "nr_thr": nr,
                    "n": s["n"],
                }
            )

    # bang theo muc: median ti le 3 luot; p90 = median p90
    by = defaultdict(list)
    for r in run_rows:
        by[r["muc"]].append(r)
    bang_lines = ["muc\texpected\tother\truns\tquota\trq_ratio_pct\trq_p90_med\tthr_usec_med"]
    check_rows = []
    for muc in sorted(by):
        rs = by[muc]
        exp = median([x["rq_ratio"] for x in rs])
        oth = median([x["steal_ratio"] for x in rs])
        p90m = median([x["rq_p90"] for x in rs])
        thr_m = median([x["thr_usec"] for x in rs])
        quota = rs[0]["quota"]
        bang_lines.append(
            f"{muc}\t{exp}\t{oth}\t{len(rs)}\t{quota}\t{100.0 * exp:.4f}\t{p90m}\t{thr_m}"
        )
        check_rows.append({"muc": str(muc), "expected": str(exp), "other": str(oth)})

    out_dir = d4_root
    (out_dir / "bang-ratio.tsv").write_text("\n".join(bang_lines) + "\n")
    check_path = out_dir / "bang-ratio-check.tsv"
    with check_path.open("w") as f:
        f.write("muc\texpected\tother\n")
        for r in check_rows:
            f.write(f"{r['muc']}\t{r['expected']}\t{r['other']}\n")

    print("=== D4 bang (ti le tong, phu luc 1.6) ===")
    print("\n".join(bang_lines))
    print("=== D4 tieu chi ===")
    import io
    from contextlib import redirect_stdout

    buf = io.StringIO()
    with redirect_stdout(buf):
        ok_d4 = check_table(str(check_path), ratio_mode=True)
    d4_tc = buf.getvalue()
    print(d4_tc, end="")
    (out_dir / "tieu-chi-ratio.txt").write_text(d4_tc)
    (d4_root.parent / "D4-bang-ratio.txt").write_text(
        "\n".join(bang_lines) + "\n" + d4_tc
    )

    # E5 (phu luc 1.6): Pearson tong rq vs thr tren 12 luot;
    # |steal|/rq < 2 % — ti le tong tren ca 12 luot (1.6 khong viet "o moi muc").
    print("=== E5 tren 12 luot D4v15 ===")
    e5_lines = [
        "muc\tquota\trun\tsum_rq_ns\tsum_steal_ns\tthr_usec\tsteal_over_rq_pct"
    ]
    for r in run_rows:
        pct = (
            (abs(r["sum_steal_ns"]) / r["sum_rq_ns"] * 100.0)
            if r["sum_rq_ns"]
            else float("nan")
        )
        e5_lines.append(
            f"{r['muc']}\t{r['quota']}\t{r['run']}\t{r['sum_rq_ns']}\t"
            f"{r['sum_steal_ns']}\t{r['thr_usec']}\t{pct:.6f}"
        )
    for muc in sorted(by):
        rs = by[muc]
        sum_rq_m = sum(x["sum_rq_ns"] for x in rs)
        sum_st_m = sum(x["sum_steal_ns"] for x in rs)
        pct_m = (abs(sum_st_m) / sum_rq_m * 100.0) if sum_rq_m else float("nan")
        print(f"muc={muc} steal/rq_pct_muc={pct_m:.6f} (mo ta)")
    sum_rq_all = sum(x["sum_rq_ns"] for x in run_rows)
    sum_st_all = sum(x["sum_steal_ns"] for x in run_rows)
    steal_pct_all = (
        (abs(sum_st_all) / sum_rq_all * 100.0) if sum_rq_all else float("inf")
    )
    steal_ok = steal_pct_all < 2.0
    print(f"steal_over_rq_pct_12luot\t{steal_pct_all}")
    xs = [float(r["thr_usec"]) for r in run_rows]
    ys = [float(r["sum_rq_ns"]) for r in run_rows]
    r_pe = pearson(xs, ys)
    ok_p = (not math.isnan(r_pe)) and r_pe >= 0.8
    print(f"pearson_sum_rq_vs_throttled_usec\t{r_pe}")
    print(f"tieu_chi_pearson>=0.8\t{'DAT' if ok_p else 'KHONG_DAT'}")
    print(f"tieu_chi_steal_pct<2\t{'DAT' if steal_ok else 'KHONG_DAT'}")
    e5_dir = d4_root.parent / "E5-from-D4v15"
    e5_dir.mkdir(parents=True, exist_ok=True)
    (e5_dir / "runs-ratio.tsv").write_text("\n".join(e5_lines) + "\n")
    tc = (
        f"pearson_sum_rq_vs_throttled_usec\t{r_pe}\n"
        f"steal_over_rq_pct_12luot\t{steal_pct_all}\n"
        f"tieu_chi_pearson>=0.8\t{'DAT' if ok_p else 'KHONG_DAT'}\n"
        f"tieu_chi_steal_pct<2\t{'DAT' if steal_ok else 'KHONG_DAT'}\n"
    )
    (e5_dir / "tieu-chi.txt").write_text(tc)
    (e5_dir / "bang.tsv").write_text("\n".join(e5_lines) + "\n")
    (d4_root.parent / "E5-bang.txt").write_text("\n".join(e5_lines) + "\n" + tc)

    ok_e5 = ok_p and steal_ok
    print(f"D4_DAT\t{ok_d4}")
    print(f"E5_DAT\t{ok_e5}")
    return 0 if (ok_d4 and ok_e5) else 1


def main():
    if len(sys.argv) < 2:
        print(
            "cach dung:\n"
            "  lab1_lieu_stats.py summarize <export.csv> <tid> [--pmu]\n"
            "  lab1_lieu_stats.py spearman <levels.csv>  # cot: muc,metric\n"
            "  lab1_lieu_stats.py pearson <pairs.csv>    # cot: x,y\n"
            "  lab1_lieu_stats.py check-d1|check-d3|check-d4|check-e5 <table.tsv>\n"
            "  lab1_lieu_stats.py check-d4-ratio <table.tsv>\n"
            "  lab1_lieu_stats.py rescore-d4e5-v16 <D4_dir>",
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
    if cmd == "rescore-d4e5-v16":
        sys.exit(rescore_d4_e5_v16(Path(sys.argv[2])))
    if cmd == "check-d4-ratio":
        ok = check_table(sys.argv[2], ratio_mode=True)
        sys.exit(0 if ok else 1)
    if cmd.startswith("check-"):
        ok = check_table(sys.argv[2], ratio_mode=False)
        sys.exit(0 if ok else 1)
    print(f"lenh khong biet: {cmd}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
