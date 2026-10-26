#!/usr/bin/env python3
"""c5_equiv_test.py - so BASELINE/PHANRA: c5_extract.py vs detector_c5.py (sai lech tuong doi max).

Tren 3 file nho (2 tong hop + 1 G3 .bin). In so cua so, so chieu, sai lech lon nhat.
Lệch > 1e-6 tuong doi → exit 1.
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DET = os.path.join(ROOT, "analysis", "detector_c5.py")
EXT = os.path.join(ROOT, "scripts", "c5_extract.py")
EXPORT = os.path.join(ROOT, "bin", "rec-export")
REL_TOL = 1e-6
ABS_TOL = 1e-9

# nap logic tham chieu
sys.path.insert(0, os.path.join(ROOT, "analysis"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import detector_c5 as det  # noqa: E402
import c5_extract as ext  # noqa: E402


def write_synthetic(path, n_tid=2, n_rec=800, dt_ns=500_000_000, base_ts=1_000_000_000_000):
    """Sinh TSV ~ n_rec/tid, dt ~0.5s => ~400s/tid, du cho cua so 300s."""
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
                flags = (1 << 7) if i % 5 == 0 else 0  # mot so PMU
                if i == 0:
                    flags |= 1  # FIRST
                cpu = 1000 + (i % 17) * 100
                rq = (i % 3) * 50
                steal = (i % 7) * 10
                irq = (i % 2) * 5
                inst = 1000 + i
                cyc = inst * (2 + (i % 3))
                row = [ts, cg, tid, seq, 0, flags, cpu, steal, irq, rq, 0, 0, inst, cyc,
                       1 if flags & (1 << 7) else 0]
                fh.write("\t".join(str(x) for x in row) + "\n")
                ts += dt_ns + (i % 11) * 1000  # nhieu loan nhe


def write_synthetic_burst(path):
    """File 2: dt xen ke ngan/dai, nhieu tranh chap gia."""
    write_synthetic(path, n_tid=3, n_rec=700, dt_ns=400_000_000, base_ts=2_000_000_000_000)


def ref_features_from_tsv(tsv_path, window_s=300, step_s=30):
    """Dung detector_c5.read_tsv + build + feat_*."""
    # detector expects tabs; if commas, convert
    path = tsv_path
    with open(tsv_path, encoding="utf-8") as fh:
        first = fh.readline()
    if "," in first and "\t" not in first:
        # convert to tab for detector
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
    rows = ext.extract(
        tsv_path, window_s, step_s,
        ["BASELINE_dt_tho", "PHANRA_5tp"],
    )
    return rows


def rel_err(a, b):
    if a != a and b != b:
        return 0.0
    if a != a or b != b:
        return float("inf")
    den = max(abs(a), abs(b), ABS_TOL)
    return abs(a - b) / den


def compare(ref, got):
    # index by (branch, tid, start, stop)
    def key(r):
        return (r[0], r[1], r[2], r[3])

    rm = {key(r): r[4] for r in ref}
    gm = {key(r): r[4] for r in got}
    keys = sorted(set(rm) | set(gm))
    missing_r = [k for k in keys if k not in rm]
    missing_g = [k for k in keys if k not in gm]
    max_err = 0.0
    worst = None
    n_dim = 0
    n_ok = 0
    for k in keys:
        if k not in rm or k not in gm:
            continue
        fr, fg = rm[k], gm[k]
        dims = sorted(set(fr) | set(fg))
        n_dim = max(n_dim, len(dims))
        for d in dims:
            e = rel_err(fr.get(d, float("nan")), fg.get(d, float("nan")))
            if e > max_err:
                max_err = e
                worst = (k, d, fr.get(d), fg.get(d), e)
            if e <= REL_TOL:
                n_ok += 1
    return {
        "n_ref": len(rm),
        "n_got": len(gm),
        "n_keys": len(keys),
        "missing_ref": len(missing_g),  # in got but not ref
        "missing_got": len(missing_r),
        "n_dim": n_dim,
        "max_err": max_err,
        "worst": worst,
    }


def run_one(label, tsv_path):
    print("=== %s ===" % label)
    print("file: %s" % tsv_path)
    ref = ref_features_from_tsv(tsv_path)
    got = extract_features(tsv_path)
    c = compare(ref, got)
    print("so_cua_so ref=%d got=%d  so_chieu~=%d" % (c["n_ref"], c["n_got"], c["n_dim"]))
    print("thieu_tren_ref=%d thieu_tren_got=%d" % (c["missing_ref"], c["missing_got"]))
    print("sai_lech_tuong_doi_max=%.6e" % c["max_err"])
    if c["worst"]:
        k, d, a, b, e = c["worst"]
        print("worst: %s dim=%s ref=%s got=%s err=%.6e" % (k, d, a, b, e))
    ok = (c["n_ref"] == c["n_got"] and c["missing_ref"] == 0 and c["missing_got"] == 0
          and c["max_err"] <= REL_TOL and c["n_ref"] > 0)
    print("ket_qua: %s" % ("KHOP" if ok else "LECH"))
    return ok


def main():
    td = tempfile.mkdtemp(prefix="c5equiv-")
    f1 = os.path.join(td, "syn1.tsv")
    f2 = os.path.join(td, "syn2.tsv")
    write_synthetic(f1)
    write_synthetic_burst(f2)

    # G3 bin nho nhung du dai (~300s): uu tien S1-002949; neu qua lon, cat export
    g3_bin = os.path.join(ROOT, "out", "g3-S1-002949.bin")
    if not os.path.isfile(g3_bin):
        cands = [os.path.join(ROOT, "out", x) for x in os.listdir(os.path.join(ROOT, "out"))
                 if x.startswith("g3-S") and x.endswith(".bin")]
        cands.sort(key=lambda p: os.path.getsize(p))
        g3_bin = cands[-1] if cands else None
    f3 = os.path.join(td, "g3.csv")
    if g3_bin and os.path.isfile(EXPORT):
        print("# rec-export %s" % g3_bin)
        with open(f3, "w", encoding="utf-8") as out:
            subprocess.check_call([EXPORT, g3_bin], stdout=out)
    else:
        print("LOI: khong co G3 .bin / rec-export", file=sys.stderr)
        sys.exit(2)

    oks = []
    oks.append(run_one("syn1", f1))
    oks.append(run_one("syn2", f2))
    oks.append(run_one("g3", f3))
    if not all(oks):
        sys.exit(1)
    print("\nTAT_CA_KHOP tol=%g" % REL_TOL)


if __name__ == "__main__":
    main()
