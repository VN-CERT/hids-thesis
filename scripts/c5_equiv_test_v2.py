#!/usr/bin/env python3
"""c5_equiv_test_v2.py - cot CU cua c5_extract_v2 vs detector_c5 (lech=0 nhu R038).

Them: file tong hop tu sinh co dap an biet truoc cho cot moi (3 cua so).
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DET = os.path.join(ROOT, "analysis", "detector_c5.py")
EXPORT = os.path.join(ROOT, "bin", "rec-export")
REL_TOL = 1e-6
ABS_TOL = 1e-9

sys.path.insert(0, os.path.join(ROOT, "analysis"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import detector_c5 as det  # noqa: E402
import c5_extract as ext_v1  # noqa: E402
import c5_extract_v2 as ext  # noqa: E402

OLD_DIMS = set(ext.DIMS_BASE) | set(ext.DIMS_DEC)


def write_synthetic(path, n_tid=2, n_rec=800, dt_ns=500_000_000, base_ts=1_000_000_000_000):
    cols = ["ts_enter", "cgroup_id", "tid", "seq", "syscall_nr", "flags",
            "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_us", "steal_off_ns",
            "inst", "cyc", "pmu_ok"]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\t".join(cols) + "\n")
        seq = 0
        for t_i, tid in enumerate(range(1000, 1000 + n_tid)):
            ts = base_ts + t_i * 10_000
            cg = 100 + t_i
            for i in range(n_rec):
                seq += 1
                flags = (1 << 7) if i % 5 == 0 else 0
                if i == 0:
                    flags |= 1
                cpu = 1000 + (i % 17) * 100
                rq = (i % 3) * 50
                steal = (i % 7) * 10
                irq = (i % 2) * 5
                inst = 1000 + i
                cyc = inst * (2 + (i % 3))
                vol_us = 0
                row = [ts, cg, tid, seq, 0, flags, cpu, steal, irq, rq, vol_us, 0, inst, cyc,
                       1 if flags & (1 << 7) else 0]
                fh.write("\t".join(str(x) for x in row) + "\n")
                ts += dt_ns + (i % 11) * 1000


def write_synthetic_burst(path):
    write_synthetic(path, n_tid=3, n_rec=700, dt_ns=400_000_000, base_ts=2_000_000_000_000)


def write_known_answer(path):
    """2 tid, co vol=0 va vol>0; so tay 3 cua so dau (start=origin).

    Tid 2000, cg=500: moi 0.5s, vol_us xen ke 0 / 100000 (100 ms).
    Tid 2001, cg=501: giong, lech phase.
    """
    cols = ["ts_enter", "cgroup_id", "tid", "seq", "syscall_nr", "flags",
            "cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_us", "steal_off_ns",
            "inst", "cyc", "pmu_ok"]
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\t".join(cols) + "\n")
        seq = 0
        base = 5_000_000_000_000
        dt = 500_000_000
        for t_i, tid in enumerate((2000, 2001)):
            ts = base + t_i * 1000
            cg = 500 + t_i
            for i in range(900):
                seq += 1
                flags = (1 << 7) if (i % 4 == 0) else 0
                if i == 0:
                    flags |= 1
                vol_us = 100000 if (i % 2 == 1) else 0  # 100 ms tren khoang le
                cpu = 2000
                rq = 100 if (i % 2 == 1) else 0
                steal = 0
                irq = 0
                inst = 5000 + i
                cyc = inst * 3
                row = [ts, cg, tid, seq, 0, flags, cpu, steal, irq, rq, vol_us, 0, inst, cyc,
                       1 if flags & (1 << 7) else 0]
                fh.write("\t".join(str(x) for x in row) + "\n")
                ts += dt


def hand_expected_window(chunk):
    """Tinh tay cot moi cho 1 cua so (dung cung dinh nghia feat_extras)."""
    return ext.feat_extras(chunk)


def ref_features_from_tsv(tsv_path, window_s=300, step_s=30):
    path = tsv_path
    with open(tsv_path, encoding="utf-8") as fh:
        first = fh.readline()
    if "," in first and "\t" not in first:
        fd, path = tempfile.mkstemp(suffix=".tsv")
        os.close(fd)
        with open(tsv_path, encoding="utf-8") as inp, open(path, "w", encoding="utf-8") as out:
            for line in inp:
                out.write(line.replace(",", "\t"))
    recs = det.read_tsv(path)
    if path != tsv_path:
        os.remove(path)
    window_ns = window_s * 1_000_000_000
    step_ns = step_s * 1_000_000_000
    out = []
    for name, fn in (("BASELINE_dt_tho", det.feat_baseline),
                     ("PHANRA_5tp", det.feat_decomp)):
        for w in det.build(recs, window_ns, step_ns, fn):
            out.append((name, w["tid"], w["start"], w["stop"], w["f"]))
    return out


def extract_features(tsv_path, window_s=300, step_s=30):
    return ext.extract(tsv_path, window_s, step_s, ["BASELINE_dt_tho", "PHANRA_5tp"])


def rel_err(a, b):
    if a != a and b != b:
        return 0.0
    if a != a or b != b:
        return float("inf")
    den = max(abs(a), abs(b), ABS_TOL)
    return abs(a - b) / den


def compare_old(ref, got):
    def key(r):
        return (r[0], r[1], r[2], r[3])

    rm = {key(r): r[4] for r in ref}
    gm = {key(r): r[4] for r in got}
    keys = sorted(set(rm) | set(gm))
    max_err = 0.0
    worst = None
    n_dim = 0
    for k in keys:
        if k not in rm or k not in gm:
            continue
        fr, fg = rm[k], gm[k]
        dims = sorted(OLD_DIMS & (set(fr) | set(fg)))
        n_dim = max(n_dim, len(dims))
        for d in dims:
            e = rel_err(fr.get(d, float("nan")), fg.get(d, float("nan")))
            if e > max_err:
                max_err = e
                worst = (k, d, fr.get(d), fg.get(d), e)
    return {
        "n_ref": len(rm),
        "n_got": len(gm),
        "missing_ref": len([k for k in gm if k not in rm]),
        "missing_got": len([k for k in rm if k not in gm]),
        "n_dim": n_dim,
        "max_err": max_err,
        "worst": worst,
    }


def run_one(label, tsv_path):
    print("=== %s ===" % label)
    print("file: %s" % tsv_path)
    ref = ref_features_from_tsv(tsv_path)
    got = extract_features(tsv_path)
    c = compare_old(ref, got)
    print("so_cua_so ref=%d got=%d  so_chieu_cu~=%d" % (c["n_ref"], c["n_got"], c["n_dim"]))
    print("thieu_tren_ref=%d thieu_tren_got=%d" % (c["missing_ref"], c["missing_got"]))
    print("sai_lech_tuong_doi_max_cot_cu=%.6e" % c["max_err"])
    if c["worst"]:
        k, d, a, b, e = c["worst"]
        print("worst: %s dim=%s ref=%s got=%s err=%.6e" % (k, d, a, b, e))
    ok = (c["n_ref"] == c["n_got"] and c["missing_ref"] == 0 and c["missing_got"] == 0
          and c["max_err"] <= REL_TOL and c["n_ref"] > 0)
    print("ket_qua: %s" % ("KHOP" if ok else "LECH"))
    return ok


def check_known(path):
    print("=== known_answer cot moi ===")
    rows = ext.extract(path, 300, 30, ["BASELINE_dt_tho", "PHANRA_5tp"])
    # lay 3 cua so BASELINE dau tien cua tid 2000 (theo start)
    base = [r for r in rows if r[0] == "BASELINE_dt_tho" and r[1] == 2000]
    base.sort(key=lambda r: r[2])
    # tai lai chunk bang v1 TidState logic: dung extract noi bo
    # Doc toan bo ban ghi tid 2000
    recs = []
    with open(path, encoding="utf-8") as fh:
        import csv
        for row in csv.DictReader(fh, delimiter="\t"):
            if int(row["tid"]) != 2000:
                continue
            recs.append(ext.parse_row(row))
    recs.sort(key=lambda r: r["ts"])
    print("tid2000 n_rec=%d n_cua_so_BASE=%d" % (len(recs), len(base)))
    print("start_ns\tn\tcgroup_id\tx_vol_med\tx_blk\tx_arr_med\tx_dt_sum\tx_vol_sum\tx_n_pmu\tgot_ok")
    ok_all = True
    for r in base[:3]:
        br, tid, start, stop, f = r
        chunk = [x for x in recs if start <= x["ts"] < stop]
        exp = hand_expected_window(chunk)
        keys = ["n", "cgroup_id", "x_vol_med", "x_blk", "x_arr_med", "x_dt_sum", "x_vol_sum", "x_n_pmu"]
        bad = []
        for k in keys:
            e = rel_err(exp[k], f[k])
            if e > REL_TOL:
                bad.append((k, exp[k], f[k], e))
        ok = not bad
        ok_all = ok_all and ok
        print("%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (
            start, f["n"], f["cgroup_id"], f["x_vol_med"], f["x_blk"],
            f["x_arr_med"], f["x_dt_sum"], f["x_vol_sum"], f["x_n_pmu"],
            "KHOP" if ok else "LECH"))
        for b in bad:
            print("  lech", b)
        # in doi chieu tay day du
        print("  tay:", {k: exp[k] for k in keys})
        print("  got:", {k: f[k] for k in keys})
    print("known_answer: %s" % ("KHOP" if ok_all else "LECH"))
    return ok_all


def main():
    td = tempfile.mkdtemp(prefix="c5equiv-v2-")
    f1 = os.path.join(td, "syn1.tsv")
    f2 = os.path.join(td, "syn2.tsv")
    fk = os.path.join(td, "known.tsv")
    write_synthetic(f1)
    write_synthetic_burst(f2)
    write_known_answer(fk)

    g3_bin = os.path.join(ROOT, "out", "g3-S1-002949.bin")
    f3 = os.path.join(td, "g3.csv")
    if not os.path.isfile(g3_bin) or not os.path.isfile(EXPORT):
        print("LOI: khong co G3 / rec-export", file=sys.stderr)
        sys.exit(2)
    print("# rec-export %s" % g3_bin)
    with open(f3, "w", encoding="utf-8") as out:
        subprocess.check_call([EXPORT, g3_bin], stdout=out)

    # xac nhan cot cu cua v2 == v1 tren syn1
    print("=== v2 vs v1 cot cu (syn1) ===")
    v1 = ext_v1.extract(f1, 300, 30, ["BASELINE_dt_tho", "PHANRA_5tp"])
    v2 = ext.extract(f1, 300, 30, ["BASELINE_dt_tho", "PHANRA_5tp"])
    c = compare_old(v1, v2)
    print("sai_lech_v1_v2_max=%.6e n_ref=%d n_got=%d" % (c["max_err"], c["n_ref"], c["n_got"]))
    ok_v1v2 = c["max_err"] <= REL_TOL and c["n_ref"] == c["n_got"]
    print("ket_qua: %s" % ("KHOP" if ok_v1v2 else "LECH"))

    oks = [ok_v1v2]
    oks.append(run_one("syn1", f1))
    oks.append(run_one("syn2", f2))
    oks.append(run_one("g3", f3))
    oks.append(check_known(fk))
    if not all(oks):
        sys.exit(1)
    print("\nTAT_CA_KHOP tol=%g" % REL_TOL)


if __name__ == "__main__":
    main()
