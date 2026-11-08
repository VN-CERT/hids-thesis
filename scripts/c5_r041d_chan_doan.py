#!/usr/bin/env python3
"""R041-d — bảng chẩn đoán mở rộng C5 v2 (chỉ đọc features, không chấm)."""
from __future__ import annotations

import math
import os
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path("/root/hids")
FEAT = ROOT / "out/c5-lab1/features_all_v2.tsv"
FEAT_C = ROOT / "out/c5-lab1c/features_all_v2.tsv"
QUAN = ROOT / "out/c5-lab1/dap-ung/quan_the_nen.tsv"
MUC = ROOT / "out/c5-lab1/muc-v2.tsv"
NHAN_LIEU = ROOT / "lab/nhan-lieu.tsv"
NHAN_TID = ROOT / "lab/nhan-tid-lab1c.tsv"
BK = ROOT / "validation/lab1-20261024/benign-khoi-dong.txt"
OUT = ROOT / "out/c5-lab1/dap-ung/R041-d"
TRAIN_UNTIL = 833189871480814
CG_NAME = {76058: "nginx", 75979: "postgres"}
DAY_NS = 86400 * 1_000_000_000


def median(xs):
    s = sorted(x for x in xs if x == x)
    n = len(s)
    if n == 0:
        return float("nan")
    if n % 2:
        return s[n // 2]
    return 0.5 * (s[n // 2 - 1] + s[n // 2])


def mad(xs, med=None):
    s = [x for x in xs if x == x]
    if not s:
        return float("nan")
    if med is None or med != med:
        med = median(s)
    return median([abs(x - med) for x in s])


def fnum(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return float("nan")


def cls_k(n):
    if n < 30 or n != n:
        return None
    return int(math.floor(math.log2(n / 300.0)))


def fmt(v):
    if v != v:
        return "nan"
    return "%.6g" % v


def load_start_mono():
    text = BK.read_text(encoding="utf-8")
    for line in text.splitlines():
        if line.startswith("start_mono_ns="):
            return int(line.split("=", 1)[1].strip())
    raise SystemExit("thieu start_mono_ns")


def load_muc_ranges():
    ranges = []
    if NHAN_LIEU.is_file():
        with NHAN_LIEU.open(encoding="utf-8") as fh:
            h = fh.readline().rstrip("\n").split("\t")
            ix = {k: i for i, k in enumerate(h)}
            idk = "dose_id" if "dose_id" in ix else ("id" if "id" in ix else None)
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if not idk:
                    continue
                t0 = int(p[ix["t_bat_dau_mono_ns"]] if "t_bat_dau_mono_ns" in ix else p[ix["t_bat_dau"]])
                t1 = int(p[ix["t_ket_thuc_mono_ns"]] if "t_ket_thuc_mono_ns" in ix else p[ix["t_ket_thuc"]])
                ranges.append((t0, t1, p[ix[idk]]))
    with MUC.open(encoding="utf-8") as fh:
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


def level_of(nguon, start, stop, muc, ranges):
    if nguon == "nen":
        if stop <= TRAIN_UNTIL:
            return "nen-d1-5"
        return "nen-d6-7"
    if muc.startswith("B4cu-") or muc.startswith("N4cu-"):
        return muc
    if nguon == "benign-lieu":
        for a0, b0, lab in ranges:
            if start < b0 and stop > a0 and ("BEN-" in lab or lab.startswith("D")):
                return lab
        return "lieu-" + muc
    if nguon == "bn":
        if muc.startswith("B4cu") or muc.startswith("N4cu"):
            return None
        return "bn-D1-" + muc
    return nguon + "-" + muc


def muc_keep(lvl):
    if lvl is None:
        return False
    if lvl == "nen-d6-7":
        return True
    if lvl.startswith("bn-D1-"):
        return True
    if lvl.startswith("B4cu-") or lvl.startswith("N4cu-"):
        return True
    if "-r1" in lvl or "-r2" in lvl or lvl.startswith("BEN-"):
        return True
    return False


def load_tid13():
    rows = []
    with QUAN.open(encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            rows.append({k: p[ix[k]] for k in ix})
    rows.sort(key=lambda r: -int(r["n_cua_so"]))
    top = rows[:13]
    return top, [r["tid"] for r in top]


def stream_lab_windows(ranges, start_mono):
    """Yield merged windows with n>=30 from lab features_all_v2."""
    base = {}
    phan = {}
    need = [
        "branch", "tid", "start_ns", "stop_ns", "nguon", "n", "cgroup_id",
        "dt_med", "dt_p90", "dt_cv", "own_med", "own_p90", "own_cv",
        "x_vol_med", "x_blk", "x_arr_med", "x_arr_cv",
        "cpu_med", "cpu_p90", "cpi_med",
        "x_n_pmu", "x_inst_med", "x_cyc_med",
    ]
    with FEAT.open(encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            br = p[ix["branch"]]
            if br not in ("BASELINE_dt_tho", "PHANRA_5tp"):
                continue
            n = fnum(p[ix["n"]] if "n" in ix else "nan")
            if n < 30:
                continue
            tid = p[ix["tid"]]
            start = int(p[ix["start_ns"]])
            key = (tid, start)
            row = {k: (p[ix[k]] if k in ix and ix[k] < len(p) else "nan") for k in need}
            row["start_ns"] = start
            row["stop_ns"] = int(p[ix["stop_ns"]])
            row["tid"] = tid
            row["n"] = n
            if br == "BASELINE_dt_tho":
                base[key] = row
            else:
                phan[key] = row

    print("base=%d phan=%d" % (len(base), len(phan)), flush=True)
    out = []
    for key in set(base) & set(phan):
        b = base[key]
        p = phan[key]
        kk = cls_k(b["n"])
        if kk is None:
            continue
        cg_raw = b["cgroup_id"]
        cg = int(float(cg_raw)) if cg_raw not in ("", "nan") else -1
        cg_name = CG_NAME.get(cg, str(cg))
        muc = muc_of(b["start_ns"], b["stop_ns"], ranges)
        lvl = level_of(b["nguon"], b["start_ns"], b["stop_ns"], muc, ranges)
        day = int((b["start_ns"] - start_mono) // DAY_NS) + 1
        x_n_pmu = fnum(b["x_n_pmu"])
        d = {
            "tid": b["tid"],
            "cg": cg_name,
            "k": kk,
            "lop": "%s|k=%d" % (cg_name, kk),
            "lvl": lvl,
            "day": day,
            "start": b["start_ns"],
            "stop": b["stop_ns"],
            "nguon": b["nguon"],
            "n": b["n"],
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
            "x_n_pmu": x_n_pmu,
            "x_inst_med": fnum(b["x_inst_med"]) if x_n_pmu >= 3 else float("nan"),
        }
        out.append(d)
    print("merged_n30=%d" % len(out), flush=True)
    return out


def part_a(wins, out_dir):
    buckets = defaultdict(list)
    for w in wins:
        if w["lvl"] is None:
            continue
        buckets[(w["lop"], w["lvl"])].append(w)

    # ref nen-d1-5
    ref = {}
    ref_lists = {}
    for (lop, lvl), rows in buckets.items():
        if lvl != "nen-d1-5" or len(rows) < 20:
            continue
        mets_med = ["dt_med", "dt_p90", "own_med", "own_p90", "cpu_med", "cpu_p90",
                    "cpi_med", "x_vol_med", "x_arr_med", "x_n_pmu"]
        ref[lop] = {}
        ref_lists[lop] = {}
        for m in mets_med:
            xs = [r[m] for r in rows]
            ref[lop][m] = median(xs)
            ref_lists[lop][m] = xs
        # x_inst only pmu>=3 (already nan-filtered in median)
        xs_i = [r["x_inst_med"] for r in rows]
        ref[lop]["x_inst_med"] = median(xs_i)
        ref_lists[lop]["x_inst_med"] = xs_i
        for m in ("own_cv", "dt_cv", "x_arr_cv", "x_blk"):
            xs = [r[m] for r in rows]
            ref[lop][m] = median(xs)
            ref_lists[lop][m] = xs
            ref[lop]["mad_" + m] = mad(xs, ref[lop][m])

    ratio_mets = ["dt_med", "dt_p90", "own_med", "own_p90", "cpu_med", "cpu_p90",
                  "cpi_med", "x_vol_med", "x_arr_med", "x_inst_med", "x_n_pmu"]
    z_mets = ["own_cv", "dt_cv", "x_arr_cv", "x_blk"]  # (v-med)/MAD

    path = out_dir / "ti_so_vs_nen_mo_rong.tsv"
    with path.open("w", encoding="utf-8") as fo:
        cols = ["lop", "muc", "n"]
        cols += ["ti_" + m for m in ratio_mets]
        cols += ["z_" + m for m in z_mets]
        fo.write("\t".join(cols) + "\n")
        for (lop, lvl), rows in sorted(buckets.items()):
            if lop not in ref or len(rows) < 20:
                continue
            if not muc_keep(lvl):
                continue
            r0 = ref[lop]
            fo.write(lop + "\t" + lvl + "\t" + str(len(rows)))
            for m in ratio_mets:
                v = median([r[m] for r in rows])
                den = r0[m]
                fo.write("\t" + fmt(v / den if den and den == den and den != 0 else float("nan")))
            for m in z_mets:
                v = median([r[m] for r in rows])
                m0 = r0[m]
                md = r0["mad_" + m]
                fo.write("\t" + fmt((v - m0) / md if md and md == md and md != 0 else float("nan")))
            fo.write("\n")
    print("wrote", path)
    return path


def part_b(wins, tid13, out_dir):
    targets_lop = {("nginx", 6), ("postgres", 4), ("postgres", 5), ("postgres", 6), ("postgres", 7)}
    mets = ["dt_med", "own_med", "cpu_med", "cpi_med", "x_inst_med", "x_arr_med", "n"]

    # by (kind, id, day) -> lists
    # kind=lop or tid
    store = defaultdict(lambda: defaultdict(list))  # key -> day -> list of dicts

    for w in wins:
        if w["nguon"] != "nen":
            continue
        if not (1 <= w["day"] <= 7):
            continue
        if (w["cg"], w["k"]) in targets_lop:
            store[("lop", w["lop"])][w["day"]].append(w)
        if w["tid"] in tid13:
            store[("tid", w["tid"])][w["day"]].append(w)

    path = out_dir / "troi_theo_ngay.tsv"
    with path.open("w", encoding="utf-8") as fo:
        cols = ["loai", "id"]
        for m in mets:
            for d in range(1, 8):
                cols.append("%s_d%d" % (m, d))
        fo.write("\t".join(cols) + "\n")
        for (loai, ident), byday in sorted(store.items()):
            fo.write(loai + "\t" + ident)
            for m in mets:
                for d in range(1, 8):
                    rows = byday.get(d, [])
                    fo.write("\t" + fmt(median([r[m] for r in rows])))
            fo.write("\n")
    print("wrote", path)
    return path


def part_c(tid_rows, out_dir):
    tids = [r["tid"] for r in tid_rows]
    cmd = (
        "for t in %s; do printf '%%s\\t' \"$t\"; "
        "tr '\\0' ' ' </proc/$t/cmdline 2>/dev/null || printf '(het)'; "
        "printf '\\n'; done"
    ) % " ".join(tids)
    try:
        out = subprocess.check_output(
            ["ssh", "-p", "22022", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
             "root@10.70.55.201", cmd],
            text=True, stderr=subprocess.STDOUT, timeout=60,
        )
    except Exception as e:
        out = "SSH_LOI: %s\n" % e
        for t in tids:
            out += "%s\t(het)\n" % t

    cmd_map = {}
    for line in out.splitlines():
        if not line.strip() or line.startswith("SSH_LOI"):
            continue
        parts = line.split("\t", 1)
        if len(parts) == 2:
            cmd_map[parts[0]] = parts[1].strip() or "(het)"
        elif len(parts) == 1:
            cmd_map[parts[0]] = "(het)"

    path = out_dir / "danh_tinh_13_tid.tsv"
    with path.open("w", encoding="utf-8") as fo:
        fo.write("tid\tcgroup\tk_trung_vi\tn_cua_so\tcmdline\n")
        for r in tid_rows:
            fo.write("%s\t%s\t%s\t%s\t%s\n" % (
                r["tid"], r["cgroup"], r["k_trung_vi"], r["n_cua_so"],
                cmd_map.get(r["tid"], "(het)").replace("\t", " ")))
    print("wrote", path)
    # raw ssh
    (out_dir / "danh_tinh_13_tid_ssh.txt").write_text(out)
    return path, out


def part_d(wins, out_dir):
    want = {("postgres", 2), ("postgres", 0), ("postgres", -6),
            ("nginx", 0), ("nginx", 1), ("nginx", 2)}
    by = defaultdict(lambda: defaultdict(list))  # (cg,k) -> tid -> rows
    for w in wins:
        if w["lvl"] != "nen-d1-5":
            continue
        if (w["cg"], w["k"]) not in want:
            continue
        by[(w["cg"], w["k"])][w["tid"]].append(w)

    path = out_dir / "thanh_phan_lop.tsv"
    with path.open("w", encoding="utf-8") as fo:
        fo.write("cgroup\tk\ttid\tn_cua_so\tdt_med\tx_arr_med\n")
        for (cg, k) in sorted(want, key=lambda x: (x[0], x[1])):
            tids = by.get((cg, k), {})
            ranked = sorted(tids.items(), key=lambda kv: -len(kv[1]))[:10]
            for tid, rows in ranked:
                fo.write("%s\t%d\t%s\t%d\t%s\t%s\n" % (
                    cg, k, tid, len(rows),
                    fmt(median([r["dt_med"] for r in rows])),
                    fmt(median([r["x_arr_med"] for r in rows]))))
    print("wrote", path)
    return path


def stream_lab1c_windows():
    base = {}
    phan = {}
    with FEAT_C.open(encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            br = p[ix["branch"]]
            if br not in ("BASELINE_dt_tho", "PHANRA_5tp"):
                continue
            n = fnum(p[ix["n"]])
            if n < 30:
                continue
            tid = p[ix["tid"]]
            start = int(p[ix["start_ns"]])
            key = (tid, start)
            row = {
                "tid": tid,
                "start_ns": start,
                "stop_ns": int(p[ix["stop_ns"]]),
                "nguon": p[ix["nguon"]] if "nguon" in ix else "",
                "n": n,
                "cgroup_id": p[ix["cgroup_id"]] if "cgroup_id" in ix else "nan",
                "dt_med": fnum(p[ix["dt_med"]]),
                "own_med": fnum(p[ix["own_med"]]) if "own_med" in ix else float("nan"),
                "x_arr_med": fnum(p[ix["x_arr_med"]]) if "x_arr_med" in ix else float("nan"),
                "x_arr_cv": fnum(p[ix["x_arr_cv"]]) if "x_arr_cv" in ix else float("nan"),
                "x_blk": fnum(p[ix["x_blk"]]) if "x_blk" in ix else float("nan"),
                "x_n_pmu": fnum(p[ix["x_n_pmu"]]) if "x_n_pmu" in ix else float("nan"),
                "x_inst_med": fnum(p[ix["x_inst_med"]]) if "x_inst_med" in ix else float("nan"),
                "cpu_med": fnum(p[ix["cpu_med"]]) if "cpu_med" in ix else float("nan"),
            }
            if br == "BASELINE_dt_tho":
                base[key] = row
            else:
                phan[key] = row
    out = []
    for key in set(base) & set(phan):
        b = base[key]
        p = phan[key]
        kk = cls_k(b["n"])
        if kk is None:
            continue
        x_n = b["x_n_pmu"]
        out.append({
            "tid": b["tid"],
            "nguon": b["nguon"],
            "k": kk,
            "n": b["n"],
            "dt_med": b["dt_med"],
            "own_med": p["own_med"],
            "x_arr_med": b["x_arr_med"],
            "x_arr_cv": b["x_arr_cv"],
            "x_blk": b["x_blk"],
            "x_inst_med": b["x_inst_med"] if x_n >= 3 else float("nan"),
            "start": b["start_ns"],
            "stop": b["stop_ns"],
        })
    print("lab1c_merged_n30=%d" % len(out), flush=True)
    return out


def part_e(wins_c, tid13, out_dir):
    # e1: 13 tid × nguon counts
    cnt = defaultdict(lambda: defaultdict(int))
    for w in wins_c:
        if w["tid"] in tid13:
            cnt[w["tid"]][w["nguon"]] += 1
    nguons = sorted({ng for d in cnt.values() for ng in d})
    path1 = out_dir / "lab1c_13tid_theo_nguon.tsv"
    with path1.open("w", encoding="utf-8") as fo:
        fo.write("tid\t" + "\t".join(nguons) + "\ttong\n")
        for tid in tid13:
            fo.write(tid)
            s = 0
            for ng in nguons:
                v = cnt[tid].get(ng, 0)
                s += v
                fo.write("\t" + str(v))
            fo.write("\t%d\n" % s)
    print("wrote", path1)

    # e2: per run_id attack tids
    # load nhan-tid unique run -> tids
    runs = []
    seen = set()
    with NHAN_TID.open(encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        ix = {k: i for i, k in enumerate(h)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            rid = p[ix["run_id"]]
            tid = p[ix["tid"]]
            # also load tan-cong for ghi_chu? optional
            runs.append((rid, tid, p[ix.get("lop", ix["lop"])] if "lop" in ix else ""))
    # group tids by run
    by_run = defaultdict(set)
    for rid, tid, _ in runs:
        by_run[rid].add(tid)

    # map run -> expected nguon for filtering if possible
    def nguon_for_run(rid):
        for sub in ("bn", "slow"):
            if (ROOT / "validation/lab1c-20261107" / sub / rid).is_dir():
                return "lab1c/%s/%s" % (sub, rid)
        if "nen" in rid:
            return "lab1c/nen-phu"
        return None

    path2 = out_dir / "lab1c_run_tid_metrics.tsv"
    with path2.open("w", encoding="utf-8") as fo:
        fo.write("run_id\ttid\tn_cua_so\tk_trung_vi\tdt_med\town_med\tx_arr_med\tx_arr_cv\tx_inst_med\tx_blk\n")
        for rid in sorted(by_run):
            ng = nguon_for_run(rid)
            for tid in sorted(by_run[rid]):
                rows = [w for w in wins_c if w["tid"] == tid and (ng is None or w["nguon"] == ng)]
                fo.write("%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" % (
                    rid, tid, len(rows),
                    fmt(median([w["k"] for w in rows])),
                    fmt(median([w["dt_med"] for w in rows])),
                    fmt(median([w["own_med"] for w in rows])),
                    fmt(median([w["x_arr_med"] for w in rows])),
                    fmt(median([w["x_arr_cv"] for w in rows])),
                    fmt(median([w["x_inst_med"] for w in rows])),
                    fmt(median([w["x_blk"] for w in rows])),
                ))
    print("wrote", path2)
    return path1, path2


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    start_mono = load_start_mono()
    ranges = load_muc_ranges()
    tid_rows, tid13 = load_tid13()
    tid13_set = set(tid13)
    print("start_mono", start_mono, "tid13", tid13, flush=True)

    print("=== load lab ===", flush=True)
    wins = stream_lab_windows(ranges, start_mono)
    print("=== a ===", flush=True)
    pa = part_a(wins, OUT)
    print("=== b ===", flush=True)
    pb = part_b(wins, tid13_set, OUT)
    print("=== c ===", flush=True)
    pc, ssh_raw = part_c(tid_rows, OUT)
    print("=== d ===", flush=True)
    pd = part_d(wins, OUT)
    print("=== e lab1c ===", flush=True)
    wins_c = stream_lab1c_windows()
    pe1, pe2 = part_e(wins_c, tid13, OUT)
    print("XONG_R041D", flush=True)


if __name__ == "__main__":
    main()
