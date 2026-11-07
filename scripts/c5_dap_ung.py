#!/usr/bin/env python3
"""c5_dap_ung.py - bang dap ung tranh chap tu features_all_v2 (M6i-c1 muc 4)."""
from __future__ import annotations

import argparse
import math
import os
from collections import defaultdict

# Anh xa cgroup_id lab collector (R040 / benign-khoi-dong)
CG_NAME = {76058: "nginx", 75979: "postgres"}


def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return float("nan")
    if n % 2:
        return s[n // 2]
    return 0.5 * (s[n // 2 - 1] + s[n // 2])


def fnum(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return float("nan")
    return v


def load_muc_ranges(muc_path, nhan_lieu_path=None):
    """Tra ve list (start, stop, label) - thu tu uu tien (dong dau thang)."""
    ranges = []
    # Prefer explicit nhan-lieu rows for r1/r2 if present
    if nhan_lieu_path and os.path.isfile(nhan_lieu_path):
        with open(nhan_lieu_path, encoding="utf-8") as fh:
            h = fh.readline().rstrip("\n").split("\t")
            ix = {k: i for i, k in enumerate(h)}
            idk = "dose_id" if "dose_id" in ix else ("id" if "id" in ix else None)
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if not idk:
                    continue
                rid = p[ix[idk]]
                t0 = int(p[ix["t_bat_dau_mono_ns"]] if "t_bat_dau_mono_ns" in ix else p[ix["t_bat_dau"]])
                t1 = int(p[ix["t_ket_thuc_mono_ns"]] if "t_ket_thuc_mono_ns" in ix else p[ix["t_ket_thuc"]])
                ranges.append((t0, t1, rid))
    with open(muc_path, encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            ranges.append((int(p[ix["start_ns"]]), int(p[ix["stop_ns"]]), p[ix["muc"]]))
    return ranges


def muc_of(start, stop, ranges):
    for a, b, m in ranges:
        if start < b and stop > a:
            return m
    return "0"


def cls_k(n):
    if n <= 0 or n != n:
        return None
    return int(math.floor(math.log2(n / 300.0)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", required=True)
    ap.add_argument("--muc", required=True)
    ap.add_argument("--nhan-lieu", default=None)
    ap.add_argument("--train-until", type=int, required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ranges = load_muc_ranges(a.muc, a.nhan_lieu)

    # Doc BASELINE + PHANRA, ghep theo (tid,start_ns)
    base = {}
    phan = {}
    agg = []
    with open(a.features, encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        need = ["branch", "tid", "start_ns", "stop_ns", "nguon", "n", "cgroup_id",
                "dt_med", "dt_p90", "dt_cv", "own_med", "own_p90", "own_cv",
                "x_vol_med", "x_blk", "x_arr_med", "x_arr_cv",
                "cpu_med", "cpu_p90", "cpi_med",
                "x_rq_sum", "x_steal_sum", "x_vol_sum", "x_cpu_sum", "x_dt_sum"]
        for line in fh:
            p = line.rstrip("\n").split("\t")
            br = p[ix["branch"]]
            row = {k: (p[ix[k]] if k in ix and ix[k] < len(p) else "nan") for k in need}
            row["start_ns"] = int(p[ix["start_ns"]])
            row["stop_ns"] = int(p[ix["stop_ns"]])
            row["tid"] = p[ix["tid"]]
            if br == "BASELINE_dt_tho":
                base[(row["tid"], row["start_ns"])] = row
            elif br == "PHANRA_5tp":
                phan[(row["tid"], row["start_ns"])] = row
            elif br == "AGG_cgroup_giay":
                agg.append(row)

    # Ghep
    keys = sorted(set(base) & set(phan))
    print("ghep BASELINE+PHANRA n=%d (base=%d phan=%d)" % (len(keys), len(base), len(phan)))

    def level_of(row):
        nguon = row["nguon"]
        start, stop = row["start_ns"], row["stop_ns"]
        muc = muc_of(start, stop, ranges)
        # nen ngay 1-5 / 6-7
        if nguon == "nen":
            if stop <= a.train_until:
                return "nen-d1-5"
            return "nen-d6-7"
        # B4cu/N4cu take muc label
        if muc.startswith("B4cu-") or muc.startswith("N4cu-"):
            return muc
        # dose sessions: prefer dose_id from nhan-lieu if muc is D1-8 etc.
        if nguon == "benign-lieu":
            # find overlapping dose_id first in ranges (nhan-lieu came first)
            for a0, b0, lab in ranges:
                if start < b0 and stop > a0 and ("BEN-" in lab or "D1-" in lab or "D3-" in lab):
                    if lab.startswith("BEN-") or lab.startswith("D"):
                        return lab
            return "lieu-" + muc
        if nguon == "bn":
            # only windows outside B4/N4: if muc is B4cu/N4cu skip; else D1 level 0/2/4
            if muc.startswith("B4cu") or muc.startswith("N4cu"):
                return None
            return "bn-D1-" + muc
        return nguon + "-" + muc

    # metrics
    MET = ["n", "dt_med", "dt_p90", "dt_cv", "own_med", "own_p90", "own_cv",
           "x_vol_med", "x_blk", "x_arr_med", "x_arr_cv", "cpu_med", "cpu_p90", "cpi_med"]
    RAT = ["rq_over_dt", "steal_over_dt", "vol_over_dt", "cpu_over_dt"]

    buckets = defaultdict(list)  # (lop, muc) -> list dict
    tid_info = {}  # for population

    for k in keys:
        b = base[k]
        p = phan[k]
        n = fnum(b["n"])
        kk = cls_k(n)
        if kk is None:
            continue
        cg = int(float(b["cgroup_id"])) if b["cgroup_id"] not in ("", "nan") else -1
        cg_name = CG_NAME.get(cg, str(cg))
        lop = "%s|k=%d" % (cg_name, kk)
        lvl = level_of(b)
        if lvl is None:
            continue
        d = {
            "n": n,
            "dt_med": fnum(b["dt_med"]),
            "dt_p90": fnum(b["dt_p90"]),
            "dt_cv": fnum(b["dt_cv"]),
            "own_med": fnum(p["own_med"]),
            "own_p90": fnum(p["own_p90"]),
            "own_cv": fnum(p["own_cv"]),
            "x_vol_med": fnum(b["x_vol_med"]),
            "x_blk": fnum(b["x_blk"]),
            "x_arr_med": fnum(b["x_arr_med"]),
            "x_arr_cv": fnum(b["x_arr_cv"]),
            "cpu_med": fnum(p["cpu_med"]),
            "cpu_p90": fnum(p["cpu_p90"]),
            "cpi_med": fnum(p["cpi_med"]),
            "rq_over_dt": fnum(b["x_rq_sum"]) / fnum(b["x_dt_sum"]) if fnum(b["x_dt_sum"]) else float("nan"),
            "steal_over_dt": fnum(b["x_steal_sum"]) / fnum(b["x_dt_sum"]) if fnum(b["x_dt_sum"]) else float("nan"),
            "vol_over_dt": fnum(b["x_vol_sum"]) / fnum(b["x_dt_sum"]) if fnum(b["x_dt_sum"]) else float("nan"),
            "cpu_over_dt": fnum(b["x_cpu_sum"]) / fnum(b["x_dt_sum"]) if fnum(b["x_dt_sum"]) else float("nan"),
            "tid": b["tid"],
            "cg": cg_name,
            "k": kk,
            "start": b["start_ns"],
            "stop": b["stop_ns"],
        }
        buckets[(lop, lvl)].append(d)
        # tid population only nen-d1-5
        if lvl == "nen-d1-5":
            st = tid_info.get(b["tid"])
            if st is None:
                tid_info[b["tid"]] = {"cg": cg_name, "t0": b["start_ns"], "t1": b["stop_ns"],
                                      "n": 0, "ks": []}
                st = tid_info[b["tid"]]
            st["n"] += 1
            st["t0"] = min(st["t0"], b["start_ns"])
            st["t1"] = max(st["t1"], b["stop_ns"])
            st["ks"].append(kk)

    # a. table
    path_a = os.path.join(a.out, "theo_lop_muc.tsv")
    with open(path_a, "w", encoding="utf-8") as fo:
        cols = ["lop", "muc", "n_cua_so", "n_tid"] + MET + RAT
        fo.write("\t".join(cols) + "\n")
        for (lop, lvl), rows in sorted(buckets.items()):
            if len(rows) < 20:
                continue
            n_tid = len({r["tid"] for r in rows})
            fo.write(lop + "\t" + lvl + "\t" + str(len(rows)) + "\t" + str(n_tid))
            for m in MET + RAT:
                fo.write("\t" + ("%.6g" % median([r[m] for r in rows])))
            fo.write("\n")
    print("wrote", path_a)

    # b. ratios vs nen-d1-5 same class
    path_b = os.path.join(a.out, "ti_so_vs_nen.tsv")
    ref = {}
    for (lop, lvl), rows in buckets.items():
        if lvl == "nen-d1-5" and len(rows) >= 20:
            ref[lop] = {m: median([r[m] for r in rows]) for m in
                        ["dt_med", "dt_p90", "own_med", "x_vol_med", "x_arr_med", "cpu_med", "cpi_med", "rq_over_dt"]}
    lieu_lvls = sorted({lvl for _, lvl in buckets if lvl not in ("nen-d1-5", "nen-d6-7") and not lvl.startswith("bn-")})
    # focus dose + B4cu
    with open(path_b, "w", encoding="utf-8") as fo:
        mets = ["dt_med", "dt_p90", "own_med", "x_vol_med", "x_arr_med", "cpu_med", "cpi_med"]
        fo.write("lop\tmuc\t" + "\t".join("ti_" + m for m in mets) + "\tdelta_rq_over_dt\tn\n")
        for (lop, lvl), rows in sorted(buckets.items()):
            if lop not in ref or len(rows) < 20:
                continue
            if lvl == "nen-d1-5":
                continue
            r0 = ref[lop]
            fo.write(lop + "\t" + lvl)
            for m in mets:
                v = median([r[m] for r in rows])
                fo.write("\t" + ("%.6g" % (v / r0[m] if r0[m] else float("nan"))))
            vq = median([r["rq_over_dt"] for r in rows])
            fo.write("\t" + ("%.6g" % (vq - r0["rq_over_dt"])) + "\t" + str(len(rows)) + "\n")
    print("wrote", path_b)

    # c. population
    path_c = os.path.join(a.out, "quan_the_nen.tsv")
    with open(path_c, "w", encoding="utf-8") as fo:
        fo.write("tid\tcgroup\tts_dau\tts_cuoi\tn_cua_so\tk_trung_vi\n")
        for tid, st in sorted(tid_info.items(), key=lambda x: -x[1]["n"]):
            fo.write("%s\t%s\t%d\t%d\t%d\t%d\n" % (
                tid, st["cg"], st["t0"], st["t1"], st["n"], int(median(st["ks"]))))
    # summary
    path_cs = os.path.join(a.out, "quan_the_nen_tomtat.tsv")
    cnt = defaultdict(lambda: {"tid": set(), "n": 0})
    for tid, st in tid_info.items():
        k = int(median(st["ks"]))
        key = (st["cg"], k)
        cnt[key]["tid"].add(tid)
        cnt[key]["n"] += st["n"]
    with open(path_cs, "w", encoding="utf-8") as fo:
        fo.write("cgroup\tk\tn_tid\tn_cua_so\n")
        for (cg, k), v in sorted(cnt.items()):
            fo.write("%s\t%d\t%d\t%d\n" % (cg, k, len(v["tid"]), v["n"]))
    path_top = os.path.join(a.out, "quan_the_nen_top20.tsv")
    with open(path_top, "w", encoding="utf-8") as fo:
        fo.write("tid\tcgroup\tn_cua_so\tk_trung_vi\tts_dau\tts_cuoi\n")
        for tid, st in sorted(tid_info.items(), key=lambda x: -x[1]["n"])[:20]:
            fo.write("%s\t%s\t%d\t%d\t%d\t%d\n" % (
                tid, st["cg"], st["n"], int(median(st["ks"])), st["t0"], st["t1"]))
    print("wrote", path_c, path_cs, path_top)

    # d. AGG compact
    path_d = os.path.join(a.out, "agg_theo_cgroup_muc.tsv")
    ab = defaultdict(list)
    for row in agg:
        cg = int(float(row["cgroup_id"])) if row["cgroup_id"] not in ("", "nan") else -1
        cg_name = CG_NAME.get(cg, str(cg))
        lvl = level_of(row)
        if lvl is None:
            continue
        n = fnum(row["n"])
        ab[(cg_name, lvl)].append({
            "n": n,
            "dt_med": fnum(row.get("dt_med", "nan")),  # AGG may not have dt - use nan
            "own_med": float("nan"),
            "x_vol_med": fnum(row.get("x_vol_med", "nan")),
            "x_arr_med": fnum(row.get("x_arr_med", "nan")),
            "cpu_med": float("nan"),
            "rq_over_dt": fnum(row["x_rq_sum"]) / fnum(row["x_dt_sum"]) if fnum(row.get("x_dt_sum", "nan")) else float("nan"),
            # AGG has rates - put syscall_rate as stand-in? Prompt: n, dt_med, own_med, x_vol_med, x_arr_med, cpu_med, rq ratio
            # AGG only has n, cgroup_id extras; old cols are rates. Use n and rates where possible.
            "syscall_rate_mean": fnum(row.get("syscall_rate_mean", "nan")) if "syscall_rate_mean" in row else float("nan"),
        })
    # Re-read AGG with rate cols
    # Actually reload properly
    ab = defaultdict(list)
    with open(a.features, encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if p[ix["branch"]] != "AGG_cgroup_giay":
                continue
            row = {k: p[ix[k]] if k in ix else "nan" for k in h}
            row["start_ns"] = int(p[ix["start_ns"]])
            row["stop_ns"] = int(p[ix["stop_ns"]])
            cg = int(float(row["cgroup_id"])) if row.get("cgroup_id", "nan") not in ("", "nan") else -1
            cg_name = CG_NAME.get(cg, str(cg))
            lvl = level_of(row)
            if lvl is None:
                continue
            dt = fnum(row.get("x_dt_sum", "nan"))
            ab[(cg_name, lvl)].append({
                "n": fnum(row["n"]),
                "x_vol_med": fnum(row.get("x_vol_med", "nan")),
                "x_arr_med": fnum(row.get("x_arr_med", "nan")),
                "rq_over_dt": fnum(row.get("x_rq_sum", "nan")) / dt if dt else float("nan"),
                "syscall_rate_mean": fnum(row.get("syscall_rate_mean", "nan")),
                "cpu_rate_mean": fnum(row.get("cpu_rate_mean", "nan")),
                "own_rate_mean": fnum(row.get("own_rate_mean", "nan")),
            })
    with open(path_d, "w", encoding="utf-8") as fo:
        fo.write("cgroup\tmuc\tn_cua_so\tn_med\tx_vol_med\tx_arr_med\trq_over_dt\tsyscall_rate_mean\tcpu_rate_mean\town_rate_mean\n")
        for (cg, lvl), rows in sorted(ab.items()):
            if len(rows) < 20:
                continue
            fo.write("%s\t%s\t%d" % (cg, lvl, len(rows)))
            for m in ("n", "x_vol_med", "x_arr_med", "rq_over_dt", "syscall_rate_mean", "cpu_rate_mean", "own_rate_mean"):
                fo.write("\t%.6g" % median([r[m] for r in rows]))
            fo.write("\n")
    print("wrote", path_d)
    print("CG_MAP", CG_NAME)


if __name__ == "__main__":
    main()
