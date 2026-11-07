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
   - Nhanh PHANRA (v1.1): chi cham diem cac dai luong do CHINH tien trinh
     quyet dinh, tuc da tru phan can thiep cua may chu/lich bieu:
       own = Dt - rq - steal - irq  (= cpu + ngu tu nguyen), theo tung khoang;
       chieu: own_med own_p90 own_iqr own_cv cpu_med cpu_p90 cpi_med.
     rq/steal/irq KHONG la chieu cham diem (chung la boi canh tranh chap, duoc
     tinh va in kem de doi chieu, khong tao bao dong). CPI = cyc/inst tren ban
     ghi co co PMU (bit7); khong co ban ghi co co thi cpi_med = NaN va bo chieu.
     (v1.0 cham ca rq/steal/irq: thu nghiem tren du lieu TONG HOP 26/10 cho thay
     thiet ke do bao dong theo chinh tranh chap - trai muc dich cua phan ra -
     nen sua TRUOC khi cham bat ky du lieu thuc nao; xem nhat ky cuoi file.)

3. Mo hinh nen: khoang cach Mahalanobis theo duong cheo (bo qua tuong quan de re
   va on dinh voi it mau) tren tung chieu, chuan hoa bang median va MAD (trung vi
   do lech tuyet doi) hoc CHI tren tap huan luyen. Diem bat thuong cua cua so =
   max |x_i - median_i| / (1.4826 * MAD_i) qua cac chieu (max thay vi tong de mot
   thanh phan bat thuong manh khong bi pha loang; day la lua chon CHOT).
   MAD = 0 thi thay bang epsilon = 1e-9 de khoi chia 0.
   (v1.2) median/MAD hoc RIENG cho tung DAI TAI (xem muc 3b); cong thuc z va
   max|z| khong doi.

3b. (v1.2, 07/11/2026) Dai tai - chuan hoa phan tang. R039 tren du lieu that
   cho thay mot nen tinh (median/MAD hoc tren ca 5 ngay) that bai tren nen co
   nhip ngay/dem: bao dong gia nen 0,88-0,97 moi nhanh. Vi vay nen duoc hoc
   theo "dai tai" la mot tin hieu NGOAI chieu cham diem cua tung tid:
   - che do toc_do (mac dinh): toc do ban ghi TONG cua moi tid trong file
     (ban ghi/giay trong [start, stop) cua cua so); dai r_k <=> toc do trong
     [2^k, 2^(k+1)) (he so 2, chot truoc).
   - che do nhip (lab): muc tai cua generator tu nhip-benign.tsv (dich_vu+muc,
     muc so gan ve muc danh dinh gan nhat), theo diem giua cua so.
   - che do khong: nhu 1.1.
   Dai thieu mau (< 8 cua so huan luyen cho mot chieu): dai so dung dai ke can
   (k+-1..3), con lai dung nen gop "*".

4. Diem danh doi (de so hai nhanh CONG BANG, giao thuc danh gia muc 2):
   quet nguong tren diem bat thuong; voi moi nguong, tinh (bao dong gia / cua so
   benign) va (co bat it nhat mot bao dong trong cua so tan cong khong). So SANH
   hai nhanh tai CUNG muc phat hien (cung ty le cua so tan cong bi bat), doc ra
   bao dong gia cua moi nhanh. KHONG so o cung nguong tho.

5. Chuan hoa (median, MAD) va nguong chi tinh/chon tren tap HUAN LUYEN (giao
   thuc danh gia muc 4). Script nhan --train-until <ns> de cat.
   (v1.2) Quy tac cat: cua so giao voi BAT KY nhan nao (tan cong A/B/C hay song
   sinh N) luon thuoc tap KIEM TRA bat ke thoi diem; huan luyen = cua so khong
   giao nhan, stop <= moc cat. (R039: B1-60s/B1-300s chay tren nen ngay 1-5
   nen bi xep vao huan luyen va mat khoi kiem tra.)
   (v1.2) Cua so TAN CONG = cua so cua CHINH tid tan cong (--nhan-tid: run_id
   id lop tid t_bat_dau_mono_ns t_ket_thuc_mono_ns) giao voi khoang nhan; cua
   so cua cac tid khac trong khoang do la benign. Khong co --nhan-tid thi nhu
   1.1: moi (tid, cua so) giao khoang nhan la tan cong - cach nay ep muc phat
   hien 0,90 phai bat ca cac tid dich vu benign nen nguong ve ~0 (R039).

Cach dung:
  # Xuat TSV bang rec-export (cot theo thu tu duoi), roi:
  python3 detector_c5.py --tsv FILE.tsv [--nhan nhan-tan-cong.tsv]
          [--train-until MONO_NS] [--window-s 300] [--step-s 30]
          [--dai-che-do toc_do|nhip|khong] [--dai-nhip nhip-benign.tsv]
          [--nhan-tid nhan-tid.tsv]

TSV dau vao: dong tieu de cua rec-export, cac cot (thu tu hien tai cua
rec-export, doc theo TEN cot chu khong theo vi tri):
  ts_enter cgroup_id tid seq syscall_nr flags cpu_ns steal_ns irq_ns rq_ns
  vol_us steal_off_ns inst cyc pmu_ok
(neu rec-export doi thu tu/ten cot, sua ham doc o DUOI, khong sua dac trung.)

Chi dung thu vien chuan cua Python.
"""
import argparse
import bisect
import math
import sys

WINDOW_S_DEFAULT = 300
STEP_S_DEFAULT = 30
EPS = 1e-9
FLAG_PMU = 1 << 7
NHIP_TOL_NS = 900 * 10**9
NAN = float("nan")


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
    """v1.1: chieu cham diem = own_* , cpu_* , cpi_med. rq/steal/irq chi la boi canh
    (van tinh, tra ve voi tien to ctx_, KHONG nam trong DIMS_DEC)."""
    f = {}
    ts = [r["ts"] for r in chunk]
    owns = []
    for i in range(1, len(chunk)):
        dt = ts[i] - ts[i - 1]
        if dt < 0:
            continue
        r = chunk[i]
        owns.append(max(0, dt - r["rq"] - r["steal"] - r["irq"]))
    if len(owns) < 4:
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
            out.append({"start": start, "stop": stop, "tid": tid, "f": f,
                        "band": None, "rate": float("nan")})
    return out


# ---------------- dai tai (v1.2) ----------------

class TocDo(object):
    """Toc do ban ghi tong (moi tid trong file) trong [start, stop), tu mang dem theo giay."""

    def __init__(self, recs):
        if not recs:
            self.n = 0
            return
        ss = [r["ts"] // 10**9 for r in recs]
        self.s0 = min(ss)
        self.n = max(ss) - self.s0 + 1
        cnt = [0] * self.n
        for s in ss:
            cnt[s - self.s0] += 1
        self.pre = [0] * (self.n + 1)
        for i in range(self.n):
            self.pre[i + 1] = self.pre[i] + cnt[i]

    def rate(self, start, stop):
        if self.n == 0:
            return float("nan")
        a = max(0, min(self.n, start // 10**9 - self.s0))
        b = max(0, min(self.n, (stop + 10**9 - 1) // 10**9 - self.s0))
        if b <= a:
            return float("nan")
        return (self.pre[b] - self.pre[a]) / float(b - a)


def band_rate(rate, he_so):
    if rate != rate or rate <= 0:
        return None
    return "r%d" % int(math.floor(math.log(rate) / math.log(he_so) + 1e-12))


def band_k(label):
    try:
        return int(label[1:]) if label and label[0] == "r" else None
    except ValueError:
        return None


class Nhip(object):
    """nhip-benign.tsv -> dai = ghep dich_vu+muc tai diem giua cua so (nhu c5_score 1.3)."""

    def __init__(self, path, muc_spec):
        self.nominal = {}
        for part in (muc_spec or "").split(";"):
            if ":" in part:
                svc, vals = part.split(":", 1)
                try:
                    self.nominal[svc.strip().lower()] = sorted(float(v) for v in vals.split(",") if v.strip())
                except ValueError:
                    pass
        self.union = sorted({v for vs in self.nominal.values() for v in vs})
        per = {}
        with open(path, encoding="utf-8", errors="replace") as fh:
            header = [h.strip() for h in fh.readline().rstrip("\n").split("\t")]
            idx = {h: i for i, h in enumerate(header)}
            a = idx.get("t_bat_dau_mono_ns", idx.get("start_ns"))
            b = idx.get("t_ket_thuc_mono_ns", idx.get("stop_ns"))
            isv = idx.get("dich_vu")
            im = idx.get("muc")
            if a is None or b is None or im is None:
                sys.exit("nhip-benign.tsv thieu cot")
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) <= max(a, b, im) or line.startswith("#"):
                    continue
                try:
                    lo, hi = int(p[a]), int(p[b])
                except ValueError:
                    continue
                svc = p[isv].strip() if isv is not None and isv < len(p) else "svc"
                svc, lvl = self.chuan_muc(svc, p[im].strip())
                per.setdefault(svc, []).append((lo, hi, lvl))
        self.svc = {}
        for s, v in per.items():
            v.sort()
            self.svc[s] = (v, [x[0] for x in v])

    def chuan_muc(self, svc, muc):
        m = muc.replace(" ", "")
        s = svc.lower()
        if not any(ch.isdigit() for ch in m):
            return s, m
        head = m.rstrip("0123456789.")
        num = m[len(head):]
        if head and head.lower() not in ("", s) and s in ("svc", ""):
            s = head.lower()
        try:
            v = float(num if num else m)
        except ValueError:
            return s, m
        cand = self.nominal.get(s) or self.union
        if not cand or v <= 0:
            return s, ("%g" % v)
        best = min(cand, key=lambda c: abs(math.log(v / c)) if c > 0 else 1e9)
        return s, ("%g" % best)

    def band(self, w):
        mid = (w["start"] + w["stop"]) // 2
        parts = []
        for s in sorted(self.svc):
            v, starts = self.svc[s]
            i = bisect.bisect_right(starts, mid) - 1
            lvl = None
            if i >= 0 and v[i][0] <= mid < v[i][1]:
                lvl = v[i][2]
            else:
                best = None
                for j in (i, i + 1):
                    if 0 <= j < len(v):
                        d = min(abs(mid - v[j][0]), abs(mid - v[j][1]))
                        if d <= NHIP_TOL_NS and (best is None or d < best[0]):
                            best = (d, v[j][2])
                if best:
                    lvl = best[1]
            parts.append("%s%s" % (s, lvl if lvl is not None else "?"))
        if all(p.endswith("?") for p in parts):
            return None
        return "|".join(parts)


def fit_norm(train_rows, dims, toi_thieu=8):
    stat = {}
    for d in dims:
        xs = [w["f"][d] for w in train_rows
              if d in w["f"] and w["f"][d] == w["f"][d]]
        if len(xs) < toi_thieu:
            stat[d] = None
            continue
        m = median(xs)
        a = mad(xs, m)
        stat[d] = (m, a if a > 0 else EPS)
    return stat


def fit_bands(train_rows, dims, toi_thieu=8):
    groups = {"*": train_rows}
    for w in train_rows:
        if w["band"] is not None:
            groups.setdefault(w["band"], []).append(w)
    return {b: fit_norm(ws, dims, toi_thieu) for b, ws in groups.items()}


def thu_tu_du_phong(band):
    if band is None:
        return ["*"]
    k = band_k(band)
    if k is None:
        return [band, "*"]
    return [band, "r%d" % (k - 1), "r%d" % (k + 1), "r%d" % (k - 2), "r%d" % (k + 2),
            "r%d" % (k - 3), "r%d" % (k + 3), "*"]


def score(w, stats, dims):
    best = 0.0
    used = 0
    for d in dims:
        v = w["f"].get(d, float("nan"))
        if v != v:
            continue
        for b in thu_tu_du_phong(w["band"]):
            st = stats.get(b)
            if st is None or st.get(d) is None:
                continue
            m, a = st[d]
            z = abs(v - m) / (1.4826 * a)
            best = max(best, z)
            used += 1
            break
    return best if used else float("nan")


def load_labels(path):
    """Doc nhan-tan-cong.tsv, tra ve list (t_bat_dau_mono_ns, t_ket_thuc_mono_ns, id, la_song_sinh)."""
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
            out.append((lo, hi, tag, cls.upper().startswith("N")))
    return out


def load_tid_labels(path):
    """nhan-tid.tsv -> dict tid(int) -> list (lo, hi, id, la_song_sinh)."""
    out = {}
    if not path:
        return out
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = [h.strip() for h in fh.readline().rstrip("\n").split("\t")]
        idx = {h: i for i, h in enumerate(header)}
        a, b, it = idx.get("t_bat_dau_mono_ns"), idx.get("t_ket_thuc_mono_ns"), idx.get("tid")
        lop, ident = idx.get("lop"), idx.get("id")
        if a is None or b is None or it is None:
            sys.exit("nhan-tid.tsv thieu cot (tid, t_bat_dau_mono_ns, t_ket_thuc_mono_ns)")
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) <= max(a, b, it):
                continue
            try:
                lo, hi, tid = int(p[a]), int(p[b]), int(p[it])
            except ValueError:
                continue
            tag = p[ident] if ident is not None and ident < len(p) else "?"
            cls = p[lop] if lop is not None and lop < len(p) else "?"
            out.setdefault(tid, []).append((lo, hi, tag, cls.upper().startswith("N")))
    return out


def win_in(w, labels, twin, tid_labels=None):
    """tid_labels (dict) co -> chi cua so cua tid co nhan moi la tan cong/song sinh."""
    cands = labels if tid_labels is None else tid_labels.get(w["tid"], ())
    for lo, hi, _, tw in cands:
        if tw == twin and w["start"] < hi and w["stop"] > lo:
            return True
    return False


def tradeoff(rows, stats, dims, labels, tid_labels=None):
    """Quet nguong; in bang (nguong, bao_dong_gia_tren_cua_so_benign, bat_tan_cong).
    (v1.2: tinh bang mang sap xep + bisect; ket qua nhu 1.1.)"""
    scored = []
    for w in rows:
        s = score(w, stats, dims)
        if s != s:
            continue
        scored.append((s, win_in(w, labels, False, tid_labels)))
    if not scored:
        return []
    benign = sorted(s for s, a in scored if not a)
    attack = sorted(s for s, a in scored if a)
    n_benign = len(benign) or 1
    n_attack = len(attack)
    out = []
    cand = sorted({round(s, 3) for s, _ in scored}, reverse=True)
    for thr in cand:
        fa = len(benign) - bisect.bisect_left(benign, thr)
        det = n_attack - bisect.bisect_left(attack, thr)
        out.append((thr, fa, fa / n_benign, det, n_attack,
                    (det / n_attack if n_attack else float("nan"))))
    return out


def f(v):
    return "nan" if v != v else ("%.4f" % v)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--tsv", required=True)
    ap.add_argument("--nhan", default=None, help="nhan-tan-cong.tsv (tuy chon)")
    ap.add_argument("--nhan-tid", default=None, help="nhan theo tid (tuy chon; xem muc 5)")
    ap.add_argument("--train-until", type=int, default=None,
                    help="ts_enter (ns) cat tap huan luyen; mac dinh 70%% dau")
    ap.add_argument("--window-s", type=int, default=WINDOW_S_DEFAULT)
    ap.add_argument("--step-s", type=int, default=STEP_S_DEFAULT)
    ap.add_argument("--dai-che-do", default="toc_do", choices=("toc_do", "nhip", "khong"))
    ap.add_argument("--dai-he-so", type=float, default=2.0)
    ap.add_argument("--dai-nhip", default=None)
    ap.add_argument("--nhip-muc", default="nginx:20,50,120,200;postgres:15,40,100;pg:15,40,100;pgsql:15,40,100")
    args = ap.parse_args(argv[1:])

    recs = read_tsv(args.tsv)
    if not recs:
        sys.exit("TSV rong hoac khong doc duoc ban ghi.")
    window_ns = args.window_s * 1_000_000_000
    step_ns = args.step_s * 1_000_000_000

    tmin = min(r["ts"] for r in recs)
    tmax = max(r["ts"] for r in recs)
    cut = args.train_until if args.train_until else tmin + int(0.7 * (tmax - tmin))

    labels = load_labels(args.nhan) if args.nhan else []
    atk = [l for l in labels if not l[3]]
    tid_labels = load_tid_labels(args.nhan_tid) if args.nhan_tid else None
    if labels and tid_labels is None:
        print("# CANH BAO: khong co --nhan-tid -> moi (tid, cua so) giao khoang nhan la tan cong (cach 1.1)")
    toc_do = TocDo(recs)
    nhip = Nhip(args.dai_nhip, args.nhip_muc) if args.dai_nhip else None
    che_do = args.dai_che_do
    if che_do == "nhip" and nhip is None:
        sys.exit("--dai-che-do nhip can --dai-nhip")

    dims_base = ["dt_med", "dt_p90", "dt_iqr", "dt_cv"]
    dims_dec = ["own_med", "own_p90", "own_iqr", "own_cv",
                "cpu_med", "cpu_p90", "cpi_med"]  # v1.1; ctx_* khong cham diem

    print("# detector_c5 1.2  cua_so=%ds buoc=%ds  cat_huan_luyen_ts=%d  dai_che_do=%s he_so=%g" %
          (args.window_s, args.step_s, cut, che_do, args.dai_he_so))
    print("# so ban ghi=%d  tmin=%d tmax=%d  nhan tan cong=%d  song sinh=%d  tid co nhan=%d  toc do tong trung binh=%.1f/s" %
          (len(recs), tmin, tmax, len(atk), len(labels) - len(atk),
           len(tid_labels) if tid_labels else 0, len(recs) / max(1.0, (tmax - tmin) / 1e9)))

    for name, branch_fn, dims in (("BASELINE_dt_tho", feat_baseline, dims_base),
                                  ("PHANRA_5tp", feat_decomp, dims_dec)):
        rows = build(recs, window_ns, step_ns, branch_fn)
        for w in rows:
            w["rate"] = toc_do.rate(w["start"], w["stop"])
            if che_do == "toc_do":
                w["band"] = band_rate(w["rate"], args.dai_he_so)
            elif che_do == "nhip":
                w["band"] = nhip.band(w)
        # quy tac cat 1.2: giao nhan (tan cong hoac song sinh) -> luon kiem tra
        co_nhan = [w for w in rows if win_in(w, labels, False) or win_in(w, labels, True)]
        khong_nhan = [w for w in rows if not (win_in(w, labels, False) or win_in(w, labels, True))]
        train = [w for w in khong_nhan if w["stop"] <= cut]
        test = [w for w in khong_nhan if w["start"] >= cut] + co_nhan
        stats = fit_bands(train, dims)
        print("\n=== %s ===" % name)
        print("so cua so: huan_luyen=%d kiem_tra=%d (co nhan=%d) (tong=%d)" %
              (len(train), len(test), len(co_nhan), len(rows)))
        active = [d for d in dims if stats["*"].get(d) is not None]
        print("chieu dung duoc (MAD>0, >=8 mau huan luyen): %s" % ",".join(active))
        bands = {}
        for w in train:
            bands[w["band"] or "-"] = bands.get(w["band"] or "-", 0) + 1
        print("dai huan luyen: %s" % "  ".join("%s:%d" % kv for kv in sorted(bands.items())))
        pool = test if test else rows
        if tid_labels is not None:
            print("cua so tan cong theo tid=%d (theo thoi gian se la %d)" % (
                sum(1 for w in pool if win_in(w, labels, False, tid_labels)),
                sum(1 for w in pool if win_in(w, labels, False))))
        tb = tradeoff(pool, stats, dims, labels, tid_labels)
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
# 1.1  26/10/2026  PHANRA: bo rq/steal/irq khoi chieu cham diem, them own =
#      Dt - rq - steal - irq (med/p90/iqr/cv). Ly do: kiem tren du lieu TONG HOP
#      (c5_score.py) cho thay v1.0 bao dong theo muc tranh chap vi rq la chieu
#      cham diem - mau thuan voi muc dich "tru can thiep truoc khi phat hien".
#      Sua truoc khi cham bat ky du lieu LAB-1/production nao (buoc 5 chua chay).
#      Cua so, buoc, chuan hoa, diem max|z|, duong danh doi: KHONG doi.
# 1.2  07/11/2026  Sau R039 (du lieu that LAB-1 + production, M6h): (a) chuan hoa
#      PHAN TANG theo dai tai (muc 3b): median/MAD hoc rieng cho moi dai, dai
#      = toc do ban ghi tong theo he so 2 (hoac muc generator tu nhip-benign);
#      ly do bang so: bao dong gia nen 0,8789/0,9661/0,9633 o muc phat hien
#      0,90 vi nen da nhip ngay/dem (~5-8k vs ~800 ban ghi/giay) ma nen hoc
#      tinh. (b) quy tac cat: cua so giao nhan luon la kiem tra (B1-60s/
#      B1-300s = 0 cua so kiem tra trong R039 vi nam tren nen ngay 1-5).
#      (c) --nhan-tid: cua so tan cong = cua so cua tid tan cong (1.1 tinh moi
#      tid giao khoang nhan). (d) tradeoff tinh bang bisect (ket qua nhu cu).
#      (e) moc cat mac dinh 70 % tinh tren min/max ts TOAN BO (1.1 lay ban ghi
#      dau/cuoi sau khi sap theo tid -> sai khi nhieu tid); duong ong luon
#      truyen --train-until nen khong anh huong so da bao cao. DAC TRUNG (muc 2), cua
#      so/buoc, cong thuc z, max|z|, duong danh doi: KHONG doi -> c5_extract
#      cua M6g van tuong duong (kiem lai bang c5_equiv_test.py).
#      --dai-che-do khong = hanh vi 1.1.
