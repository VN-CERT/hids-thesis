#!/usr/bin/env python3
"""detector_c5.py - detector THAM CHIEU cho C5 cua Bai 1. Do kien truc su viet.
KHONG SUA DAC TRUNG / DIEM DANH DOI SAU KHI DA THAY DU LIEU MO HINH.

Muc dich: so phat hien bat thuong nhip thoi gian khi (A) chi dung Dt tho (thoi
gian giua hai sys_enter lien tiep cua mot tien trinh) voi (B) dung 5 thanh phan
da phan ra (cpu, steal, irq, rq, + CPI khi co mau PMU). Chung minh luan diem C5:
duoi tranh chap, baseline Dt-tho bao dong gia tang; ban phan ra on dinh hon o
cung mot diem tren duong danh doi.

Day la detector DON GIAN co chu dich (khong hoc sau), de C5 cua Bai 1 co mot moc
re, minh bach, cung dau vao. Mo hinh manh (DeepLog, THP, ban co dieu kien) la
cua Bai 2.

=== CHOT TRUOC KHI THAY DU LIEU (phien ban 1.0, 22/10/2026) ===
Dac trung va quy tac duoi day duoc co dinh TRUOC khi chay tren du lieu LAB-1.
Moi thay doi phai ghi ro ly do + ngay o cuoi file, giu ban cu.

1. Don vi cham diem: (tien trinh tid, cua so truot). Cua so = 300 giay, buoc =
   30 giay (trong khoang khoi diem 60/300/600 cua giao thuc danh gia; 300 chon
   vi khop D=300 giay cua moi de doa "cham va thua", du dai de thay >= 2-3 chu
   ky beacon 60-300 giay). CHOT, khong doi theo ket qua.

2. Dac trung cua mot cua so, cho MOI nhanh:
   - Nhanh BASELINE (chi Dt tho): vector [median(dt), p90(dt), iqr(dt),
     cv(dt)=sd/mean] tren cac khoang Dt = ts_enter[i] - ts_enter[i-1] (ns) cua
     tien trinh trong cua so. (dt tho da GOM het cpu+steal+irq+rq+ngu; day la
     cach cac phuong phap thoi gian hien co nhin.)
   - Nhanh PHANRA: lay median va p90 cua TUNG thanh phan trong cua so:
     cpu_ns, rq_ns, steal_ns, irq_ns (4 thanh phan x 2 thong ke = 8 chieu), cong
     them median(CPI) va ty le ban ghi co co PMU neu co mau. CPI = cyc/inst tren
     cac ban ghi co co PMU (bit7); neu khong co ban ghi co co trong cua so thi
     CPI = NaN va bo chieu do (danh dau thieu).

3. Mo hinh nen: khoang cach Mahalanobis theo duong cheo (bo qua tuong quan de re
   va on dinh voi it mau) tren tung chieu, chuan hoa bang median va MAD (trung vi
   do lech tuyet doi) hoc CHI tren tap huan luyen. Diem bat thuong cua cua so =
   max |x_i - median_i| / (1.4826 * MAD_i) qua cac chieu (max thay vi tong de mot
   thanh phan bat thuong manh khong bi pha loang; day la lua chon CHOT).
   MAD = 0 thi thay bang epsilon = 1e-9 de khoi chia 0.

4. Diem danh doi (de so hai nhanh CONG BANG, giao thuc danh gia muc 2):
   quet nguong tren diem bat thuong; voi moi nguong, tinh (bao dong gia / cua so
   benign) va (co bat it nhat mot bao dong trong cua so tan cong khong). So SANH
   hai nhanh tai CUNG muc phat hien (cung ty le cua so tan cong bi bat), doc ra
   bao dong gia cua moi nhanh. KHONG so o cung nguong tho.

5. Chuan hoa (median, MAD) va nguong chi tinh/chon tren tap HUAN LUYEN (giao
   thuc danh gia muc 4). Script nhan --train-until <ns> de cat.

Cach dung:
  # Xuat TSV bang rec-export (cot theo thu tu duoi), roi:
  python3 detector_c5.py --tsv FILE.tsv [--nhan nhan-tan-cong.tsv]
          [--train-until MONO_NS] [--window-s 300] [--step-s 30]

TSV dau vao: dong tieu de cua rec-export, cac cot (thu tu hien tai cua
rec-export, doc theo TEN cot chu khong theo vi tri):
  ts_enter cgroup_id tid seq syscall_nr flags cpu_ns steal_ns irq_ns rq_ns
  vol_us steal_off_ns inst cyc pmu_ok
(neu rec-export doi thu tu/ten cot, sua ham doc o DUOI, khong sua dac trung.)

Chi dung thu vien chuan cua Python.
"""
import argparse
import math
import sys

WINDOW_S_DEFAULT = 300
STEP_S_DEFAULT = 30
EPS = 1e-9
FLAG_PMU = 1 << 7


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


def mad(xs, med=None):
    if not xs:
        return float("nan")
    m = median(xs) if med is None else med
    return median([abs(x - m) for x in xs])


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


def read_tsv(path):
    """Tra ve list ban ghi: dict cac truong can dung, da ep kieu so.
    Doc theo TEN cot trong dong tieu de (khong theo vi tri)."""
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        need = ["ts_enter", "tid", "flags", "cpu_ns", "steal_ns", "irq_ns",
                "rq_ns", "inst", "cyc"]
        for k in need:
            if k not in idx:
                sys.exit("TSV thieu cot '%s'. Cot co: %s" % (k, header))
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < len(header):
                continue
            try:
                rows.append({
                    "ts": int(p[idx["ts_enter"]]),
                    "tid": int(p[idx["tid"]]),
                    "flags": int(p[idx["flags"]]),
                    "cpu": int(p[idx["cpu_ns"]]),
                    "steal": int(p[idx["steal_ns"]]),
                    "irq": int(p[idx["irq_ns"]]),
                    "rq": int(p[idx["rq_ns"]]),
                    "inst": int(p[idx["inst"]]),
                    "cyc": int(p[idx["cyc"]]),
                })
            except (ValueError, IndexError):
                continue
    rows.sort(key=lambda r: (r["tid"], r["ts"]))
    return rows


def windows_for_tid(recs, window_ns, step_ns):
    """Sinh cac cua so truot cho mot tien trinh (da sap theo ts)."""
    if not recs:
        return
    t0 = recs[0]["ts"]
    t_end = recs[-1]["ts"]
    start = t0
    i0 = 0
    while start <= t_end:
        stop = start + window_ns
        while i0 < len(recs) and recs[i0]["ts"] < start:
            i0 += 1
        j = i0
        chunk = []
        while j < len(recs) and recs[j]["ts"] < stop:
            chunk.append(recs[j])
            j += 1
        if len(chunk) >= 5:
            yield start, stop, chunk
        start += step_ns


def feat_baseline(chunk):
    ts = [r["ts"] for r in chunk]
    dts = [ts[i] - ts[i - 1] for i in range(1, len(ts)) if ts[i] >= ts[i - 1]]
    if len(dts) < 4:
        return None
    return {
        "dt_med": median(dts),
        "dt_p90": pct(dts, 0.90),
        "dt_iqr": pct(dts, 0.75) - pct(dts, 0.25),
        "dt_cv": cv(dts),
    }


def feat_decomp(chunk):
    f = {}
    for comp in ("cpu", "steal", "irq", "rq"):
        vals = [r[comp] for r in chunk]
        f[comp + "_med"] = median(vals)
        f[comp + "_p90"] = pct(vals, 0.90)
    cpis = [r["cyc"] / r["inst"] for r in chunk
            if (r["flags"] & FLAG_PMU) and r["inst"] > 0]
    f["cpi_med"] = median(cpis) if cpis else float("nan")
    return f


def build(recs, window_ns, step_ns, branch_fn):
    """Tra ve list (start, stop, tids, featdict) cho mot nhanh."""
    out = []
    by_tid = {}
    for r in recs:
        by_tid.setdefault(r["tid"], []).append(r)
    for tid, rs in by_tid.items():
        rs.sort(key=lambda r: r["ts"])
        for start, stop, chunk in windows_for_tid(rs, window_ns, step_ns):
            f = branch_fn(chunk)
            if f is None:
                continue
            out.append({"start": start, "stop": stop, "tid": tid, "f": f})
    return out


def fit_norm(train_rows, dims):
    stat = {}
    for d in dims:
        xs = [w["f"][d] for w in train_rows
              if d in w["f"] and w["f"][d] == w["f"][d]]
        if len(xs) < 8:
            stat[d] = None
            continue
        m = median(xs)
        a = mad(xs, m)
        stat[d] = (m, a if a > 0 else EPS)
    return stat


def score(w, stat, dims):
    best = 0.0
    used = 0
    for d in dims:
        if stat.get(d) is None:
            continue
        v = w["f"].get(d, float("nan"))
        if v != v:
            continue
        m, a = stat[d]
        z = abs(v - m) / (1.4826 * a)
        best = max(best, z)
        used += 1
    return best if used else float("nan")


def load_attack_windows(path):
    """Doc nhan-tan-cong.tsv, tra ve list (t_bat_dau_mono_ns, t_ket_thuc_mono_ns, id)."""
    out = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {name: i for i, name in enumerate(header)}
        a = idx.get("t_bat_dau_mono_ns")
        b = idx.get("t_ket_thuc_mono_ns")
        lop = idx.get("lop")
        ident = idx.get("id")
        if a is None or b is None:
            return out
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) <= b:
                continue
            try:
                lo = int(p[a]); hi = int(p[b])
            except ValueError:
                continue
            tag = p[ident] if ident is not None and ident < len(p) else "?"
            cls = p[lop] if lop is not None and lop < len(p) else "?"
            # Chi cua so tan cong THAT (lop B hoac A), khong phai benign song sinh (N).
            if cls.upper().startswith("N"):
                continue
            out.append((lo, hi, tag))
    return out


def win_in_attack(w, atk):
    for lo, hi, _ in atk:
        if w["start"] < hi and w["stop"] > lo:
            return True
    return False


def tradeoff(rows, stat, dims, atk):
    """Quet nguong; in bang (nguong, bao_dong_gia_tren_cua_so_benign, bat_tan_cong)."""
    scored = []
    for w in rows:
        s = score(w, stat, dims)
        if s != s:
            continue
        scored.append((s, win_in_attack(w, atk)))
    if not scored:
        return []
    benign = [s for s, a in scored if not a]
    attack = [s for s, a in scored if a]
    n_benign = len(benign) or 1
    n_attack = len(attack)
    out = []
    cand = sorted({round(s, 3) for s, _ in scored}, reverse=True)
    for thr in cand:
        fa = sum(1 for s in benign if s >= thr)
        det = sum(1 for s in attack if s >= thr)
        out.append((thr, fa, fa / n_benign, det, n_attack,
                    (det / n_attack if n_attack else float("nan"))))
    return out


def f(v):
    return "nan" if v != v else ("%.4f" % v)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", required=True)
    ap.add_argument("--nhan", default=None, help="nhan-tan-cong.tsv (tuy chon)")
    ap.add_argument("--train-until", type=int, default=None,
                    help="ts_enter (ns) cat tap huan luyen; mac dinh 70%% dau")
    ap.add_argument("--window-s", type=int, default=WINDOW_S_DEFAULT)
    ap.add_argument("--step-s", type=int, default=STEP_S_DEFAULT)
    args = ap.parse_args(argv[1:])

    recs = read_tsv(args.tsv)
    if not recs:
        sys.exit("TSV rong hoac khong doc duoc ban ghi.")
    window_ns = args.window_s * 1_000_000_000
    step_ns = args.step_s * 1_000_000_000

    tmin = recs[0]["ts"]
    tmax = recs[-1]["ts"]
    cut = args.train_until if args.train_until else tmin + int(0.7 * (tmax - tmin))

    atk = load_attack_windows(args.nhan) if args.nhan else []

    dims_base = ["dt_med", "dt_p90", "dt_iqr", "dt_cv"]
    dims_dec = ["cpu_med", "cpu_p90", "steal_med", "steal_p90",
                "irq_med", "irq_p90", "rq_med", "rq_p90", "cpi_med"]

    print("# detector_c5  cua_so=%ds buoc=%ds  cat_huan_luyen_ts=%d" %
          (args.window_s, args.step_s, cut))
    print("# so ban ghi=%d  tmin=%d tmax=%d  so cua so tan cong(nhan)=%d" %
          (len(recs), tmin, tmax, len(atk)))

    for name, branch_fn, dims in (("BASELINE_dt_tho", feat_baseline, dims_base),
                                  ("PHANRA_5tp", feat_decomp, dims_dec)):
        rows = build(recs, window_ns, step_ns, branch_fn)
        train = [w for w in rows if w["stop"] <= cut]
        test = [w for w in rows if w["start"] >= cut]
        stat = fit_norm(train, dims)
        print("\n=== %s ===" % name)
        print("so cua so: huan_luyen=%d kiem_tra=%d (tong=%d)" %
              (len(train), len(test), len(rows)))
        active = [d for d in dims if stat.get(d) is not None]
        print("chieu dung duoc (MAD>0, >=8 mau huan luyen): %s" % ",".join(active))
        pool = test if test else rows
        tb = tradeoff(pool, stat, dims, atk)
        if not tb:
            print("khong cham diem duoc (thieu mau).")
            continue
        print("nguong\tbao_dong_gia\tty_le_bdg\tbat_tc\tn_tc\tty_le_phat_hien")
        # In thua: moi 10 muc nguong + cac muc co thay doi ty le phat hien.
        last_det = None
        step = max(1, len(tb) // 20)
        for i, (thr, fa, far, det, ntc, dr) in enumerate(tb):
            if i % step == 0 or det != last_det:
                print("%s\t%d\t%s\t%d\t%d\t%s" %
                      (f(thr), fa, f(far), det, ntc, f(dr)))
                last_det = det

    if not atk:
        print("\n(Khong co nhan tan cong -> chi in duong bao dong gia; "
              "so sanh phat hien can --nhan.)")


if __name__ == "__main__":
    main(sys.argv)

# === NHAT KY THAY DOI (ghi khi buoc phai sua, kem ly do + ngay) ===
# 1.0  22/10/2026  ban dau, chot truoc khi thay du lieu LAB-1.
