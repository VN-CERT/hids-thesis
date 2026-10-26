#!/usr/bin/env python3
"""c5_score.py - cham diem C5 tu BANG DAC TRUNG theo cua so. Do kien truc su viet.
KHONG SUA TOAN HOC CHAM DIEM / DIEM DANH DOI. Cung quy tac voi detector_c5.py
(muc 3-5 o dau file do): chuan hoa median/MAD hoc tren tap huan luyen, diem =
max |z| qua cac chieu, duong danh doi quet nguong, so hai nhanh o CUNG muc phat
hien. File nay chi khac detector_c5.py o DAU VAO: doc dac trung da tinh san
(do c5_extract.py cua Cursor sinh ra theo dung dinh nghia muc 2 cua
detector_c5.py), nen chay duoc tren 7 ngay du lieu.

Dau vao (--features): TSV co tieu de, moi dong mot cua so:
  branch  tid  start_ns  stop_ns  <cac cot dac trung...>
  - branch: BASELINE_dt_tho | PHANRA_5tp | AGG_cgroup_giay (nhanh thu ba:
    dac trung moi-giay-theo-cgroup tu luong host, lop SchedBlame/PSI)
  - cot dac trung: moi cot con lai la mot chieu; gia tri "nan" = thieu.
  Dinh nghia chieu CHOT cho hai nhanh dau (phai khop detector_c5.py):
    BASELINE_dt_tho: dt_med dt_p90 dt_iqr dt_cv
    PHANRA_5tp (v1.1): own_med own_p90 own_iqr own_cv cpu_med cpu_p90 cpi_med
                     (own = Dt - rq - steal - irq). Cac cot bat dau bang ctx_
                     (ctx_rq_*, ctx_steal_*, ctx_irq_*) la boi canh, KHONG cham.
  Nhanh AGG_cgroup_giay (chot o day, 26/10/2026, truoc khi co du lieu):
    tren cua so 300 s cua MOI cgroup, tu cac mau 1 Hz cua luong host:
    cpu_some_mean cpu_some_p90 cpu_full_mean mem_some_mean io_some_mean
    thr_usec_sum nr_thr_sum usage_usec_mean
    (PSI avg10 cua cgroup; cpu.stat throttled; usage). Cua so/buoc nhu hai
    nhanh kia; don vi (cgroup, cua so) thay cho (tid, cua so).

--nhan: nhan-tan-cong.tsv (cot t_bat_dau_mono_ns, t_ket_thuc_mono_ns, lop, id);
  cua so TAN CONG = giao voi mot nhan lop khac N. --train-until: ts cat huan
  luyen (mac dinh 70% dau theo start_ns). --muc: file TSV (start_ns stop_ns
  muc) de gan "muc tranh chap" cho tung cua so benign; neu co, in them bang
  bao dong gia THEO MUC tai moi muc phat hien 50/80/90/95/100% (truc hoanh cua
  hinh trung tam C5).

Cach dung:
  python3 c5_score.py --features F.tsv [--nhan nhan.tsv] [--train-until NS]
          [--muc muc.tsv] [--out thu_muc]
Chi thu vien chuan.
"""
import argparse
import math
import os
import sys

EPS = 1e-9
DET_LEVELS = (0.5, 0.8, 0.9, 0.95, 1.0)


def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return float("nan")
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def mad(xs, m):
    return median([abs(x - m) for x in xs]) if xs else float("nan")


def read_features(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        need = ("branch", "tid", "start_ns", "stop_ns")
        for k in need:
            if k not in header:
                sys.exit("features thieu cot %s" % k)
        idx = {h: i for i, h in enumerate(header)}
        dims = [h for h in header if h not in need]
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < len(header):
                continue
            f = {}
            for d in dims:
                try:
                    f[d] = float(p[idx[d]])
                except ValueError:
                    f[d] = float("nan")
            rows.append({"branch": p[idx["branch"]], "tid": p[idx["tid"]],
                         "start": int(p[idx["start_ns"]]),
                         "stop": int(p[idx["stop_ns"]]), "f": f})
    return rows, dims


def read_ranges(path, lo_key, hi_key, tag_key=None, cls_key=None, skip_n=False):
    out = []
    if not path:
        return out
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        if lo_key not in idx or hi_key not in idx:
            return out
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) <= max(idx[lo_key], idx[hi_key]):
                continue
            try:
                lo, hi = int(p[idx[lo_key]]), int(p[idx[hi_key]])
            except ValueError:
                continue
            tag = p[idx[tag_key]] if tag_key and tag_key in idx and idx[tag_key] < len(p) else "?"
            if skip_n and cls_key and cls_key in idx and p[idx[cls_key]].upper().startswith("N"):
                continue
            out.append((lo, hi, tag))
    return out


def overlaps(w, ranges):
    for lo, hi, tag in ranges:
        if w["start"] < hi and w["stop"] > lo:
            return tag
    return None


def fit(train, dims):
    stat = {}
    for d in dims:
        xs = [w["f"][d] for w in train if w["f"].get(d, float("nan")) == w["f"].get(d, float("nan"))]
        if len(xs) < 8:
            stat[d] = None
            continue
        m = median(xs)
        a = mad(xs, m)
        stat[d] = (m, a if a > 0 else EPS)
    return stat


def score(w, stat, dims):
    best, used = 0.0, 0
    for d in dims:
        if stat.get(d) is None:
            continue
        v = w["f"].get(d, float("nan"))
        if v != v:
            continue
        m, a = stat[d]
        best = max(best, abs(v - m) / (1.4826 * a))
        used += 1
    return best if used else float("nan")


def f4(v):
    return "nan" if v != v else "%.4f" % v


def tradeoff(scored):
    """scored: list (score, is_attack, muc). Tra ve list (thr, far, det_rate, n_b, n_a)."""
    benign = [s for s, a, _ in scored if not a]
    attack = [s for s, a, _ in scored if a]
    nb, na = len(benign) or 1, len(attack)
    out = []
    for thr in sorted({round(s, 4) for s, _, _ in scored}, reverse=True):
        fa = sum(1 for s in benign if s >= thr)
        det = sum(1 for s in attack if s >= thr)
        out.append((thr, fa / nb, (det / na if na else float("nan")), fa, det))
    return out


def thr_at_detection(tb, level):
    """Nguong THAP NHAT con dat >= level ty le phat hien (tuc ngưỡng cao nhất
    mà tỉ lệ phát hiện >= level): tb sap giam dan theo thr."""
    for thr, far, det, fa, d in tb:
        if det == det and det >= level:
            return thr, far
    return float("nan"), float("nan")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", required=True)
    ap.add_argument("--nhan", default=None)
    ap.add_argument("--muc", default=None, help="TSV start_ns stop_ns muc (muc tranh chap cua cua so benign)")
    ap.add_argument("--train-until", type=int, default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv[1:])

    rows, dims_all = read_features(a.features)
    if not rows:
        sys.exit("khong co cua so")
    atk = read_ranges(a.nhan, "t_bat_dau_mono_ns", "t_ket_thuc_mono_ns", "id", "lop", skip_n=True)
    muc = read_ranges(a.muc, "start_ns", "stop_ns", "muc")
    tmin = min(w["start"] for w in rows)
    tmax = max(w["start"] for w in rows)
    cut = a.train_until if a.train_until else tmin + int(0.7 * (tmax - tmin))
    outdir = a.out
    if outdir:
        os.makedirs(outdir, exist_ok=True)

    print("# c5_score  cat_huan_luyen=%d  cua_so=%d  nhan_tan_cong=%d  muc=%d" % (cut, len(rows), len(atk), len(muc)))
    branches = sorted({w["branch"] for w in rows})
    summary = []
    for b in branches:
        rb = [w for w in rows if w["branch"] == b]
        dims = [d for d in dims_all if not d.startswith("ctx_")
            and any(w["f"].get(d, float("nan")) == w["f"].get(d, float("nan")) for w in rb)]
        train = [w for w in rb if w["stop"] <= cut and overlaps(w, atk) is None]
        test = [w for w in rb if w["start"] >= cut]
        stat = fit(train, dims)
        active = [d for d in dims if stat.get(d) is not None]
        scored = []
        for w in (test if test else rb):
            s = score(w, stat, dims)
            if s != s:
                continue
            scored.append((s, overlaps(w, atk) is not None, overlaps(w, muc)))
        tb = tradeoff(scored)
        print("\n=== %s === huan_luyen=%d kiem_tra=%d chieu=%s" % (b, len(train), len(test), ",".join(active)))
        if not tb:
            print("khong cham duoc")
            continue
        print("muc_phat_hien\tnguong\tbao_dong_gia")
        for lv in DET_LEVELS:
            thr, far = thr_at_detection(tb, lv)
            print("%.2f\t%s\t%s" % (lv, f4(thr), f4(far)))
            summary.append((b, lv, thr, far))
            if muc:
                # bao dong gia theo muc tranh chap tai nguong nay
                by = {}
                for s, is_a, m in scored:
                    if is_a:
                        continue
                    key = m if m is not None else "0"
                    n, h = by.get(key, (0, 0))
                    by[key] = (n + 1, h + (1 if (thr == thr and s >= thr) else 0))
                print("  theo muc: " + "  ".join("%s:%s(%d)" % (k, f4(h / n if n else float("nan")), n)
                                                for k, (n, h) in sorted(by.items())))
        if outdir:
            with open(os.path.join(outdir, "tradeoff_%s.tsv" % b), "w") as fh:
                fh.write("nguong\tbao_dong_gia\tty_le_phat_hien\tn_bdg\tn_bat\n")
                for thr, far, det, fa, d in tb:
                    fh.write("%s\t%s\t%s\t%d\t%d\n" % (f4(thr), f4(far), f4(det), fa, d))
    if outdir and summary:
        with open(os.path.join(outdir, "tom_tat.tsv"), "w") as fh:
            fh.write("branch\tmuc_phat_hien\tnguong\tbao_dong_gia\n")
            for b, lv, thr, far in summary:
                fh.write("%s\t%.2f\t%s\t%s\n" % (b, lv, f4(thr), f4(far)))
    print("\n(Doc: tai cung muc phat hien, so bao_dong_gia giua cac nhanh; "
          "bang 'theo muc' la truc hoanh hinh C5.)")


if __name__ == "__main__":
    main(sys.argv)

# === NHAT KY ===
# 1.0  26/10/2026  ban dau; toan hoc = detector_c5.py 1.1; cot ctx_* khong cham; them nhanh AGG_cgroup_giay (chot truoc du lieu).
