#!/usr/bin/env python3
"""c5_score.py - cham diem C5 tu BANG DAC TRUNG theo cua so. Do kien truc su viet.
KHONG SUA TOAN HOC CHAM DIEM / DIEM DANH DOI. Cung quy tac voi detector_c5.py
(muc 3-5 o dau file do): chuan hoa median/MAD hoc tren tap huan luyen, diem =
max |z| qua cac chieu, duong danh doi quet nguong, so hai nhanh o CUNG muc phat
hien. File nay chi khac detector_c5.py o DAU VAO: doc dac trung da tinh san
(do c5_extract.py cua Cursor sinh ra theo dung dinh nghia muc 2 cua
detector_c5.py), nen chay duoc tren 7 ngay du lieu.

=== PHIEN BAN 1.3 (07/11/2026) - hai sua doi phuong phap, ghi ly do bang so ===
R039 (M6h, du lieu that LAB-1 + production) cho thay:
 (1) bao dong gia tren NEN (muc 0) = 0,88 / 0,97 / 0,96 cho ba nhanh o muc phat
     hien 0,90, production 0,93 / 0,91 / 0,84. Nguyen nhan: nen co nhip ngay/dem
     do generator co y tao (nhip-benign.tsv: nginx 120 -> 20 rps, pg 100 -> 15
     tps; ~5-8 nghin ban ghi/giay ban ngay, ~800 ban dem). median/MAD hoc TINH
     tren ca 5 ngay nen mot nguong z khong vua ca ngay lan dem: ban dem moi cua
     so thanh "bat thuong". Production (23 CSDL, nhip gio manh) cung benh.
     => CHUAN HOA PHAN TANG THEO MUC TAI ("dai"): median/MAD hoc RIENG cho moi
     dai tai tren tap huan luyen; moi cua so cham so voi nen CUNG DAI. Dai duoc
     xac dinh tu mot tin hieu NGOAI chieu cham diem cua tid:
       - che do "toc_do" (mac dinh, dung duoc ca lab lan production): toc do
         ban ghi TONG cua cac cgroup duoc giam sat trong cua so (ban ghi/giay),
         lay tu nhanh AGG_cgroup_giay cua chinh bang dac trung (cong
         syscall_rate_mean cua cac cgroup tai cua so AGG gan nhat) hoac tu file
         dem theo giay (--toc-do-giay). Dai = bac luy thua cua he so 2:
         dai r_k <=> toc do trong [2^k, 2^(k+1)) ban ghi/giay. He so 2 chot
         truoc khi chay; khong tinh chinh theo ket qua.
       - che do "nhip" (chi lab, kiem cheo): muc tai THAT cua generator doc tu
         nhip-benign.tsv theo moc thoi gian cua so (ghep dich_vu+muc, muc so
         duoc gan ve muc danh dinh gan nhat de bo jitter +-20 %).
       - che do "khong": nhu 1.2 (mot nen tinh) - de hoi quy/doi chieu.
     Dai thieu mau (< 8 cua so huan luyen cho mot chieu): dai so r_k dung dai
     ke can (k+-1, +-2, +-3), con lai dung nen gop "*"; cot dai_dung ghi ro.
 (2) B1-60s va B1-300s = 0 cua so kiem tra: hai dot chay TREN NEN ngay 1-5 nen
     nguon = nen va start < moc cat -> bi loai khoi ca huan luyen lan kiem tra.
     => QUY TAC CAT 1.3: moi cua so giao voi BAT KY nhan nao trong
     nhan-tan-cong.tsv (lop A/B/C = tan cong; lop N = benign song sinh) hoac
     nam trong phien benign-duoi-lieu (muc != 0) LUON thuoc tap KIEM TRA, bat
     ke ngay va nguon; tap huan luyen = cua so nen, stop <= moc cat, khong giao
     nhan nao, muc 0.
 (3) Cua so "tan cong" trong 1.2 = MOI (tid, cua so) giao voi khoang thoi gian
     cua nhan, ke ca cac tid dich vu benign dang chay trong luc do (voi B1 chi
     1 trong ~7 tid la beacon). Muc phat hien 0,90 vi vay doi gan 90 % moi cua
     so trong khoang tan cong phai vuot nguong -> nguong bi ep xuong gan 0 va
     bao dong gia nen ~0,9 o moi nhanh (R039). Dieu nay SAI so voi dinh nghia
     da chot cua detector_c5.py muc 4 ("co bat it nhat mot bao dong trong cua
     so tan cong") va don vi cham diem (tien trinh, cua so).
     => NHAN THEO TID (--nhan-tid): cua so tan cong = cua so cua CHINH tid tan
     cong (tu luong proc / nhat ky phien) giao voi khoang nhan; cua so cua cac
     tid khac trong khoang do la BENIGN (bao cao rieng: "nen trong luc tan
     cong"). Song sinh N theo tid tuong tu. Nhanh AGG (don vi cgroup) van theo
     thoi gian vi khong co tid. Khong co --nhan-tid -> hanh vi 1.2 (canh bao).
 Toan cham diem (max|z| voi median/MAD, duong danh doi quet nguong, so o cung
 muc phat hien, bao dong gia theo muc tranh chap) GIU NGUYEN. Them bao cao (khong
 doi dinh nghia): bao dong gia rieng tren nen kiem tra (ngay 6-7) va tren song
 sinh; bao dong gia theo dai; phat hien theo tung id; phat hien theo tung dot
 trong D = 300 s va do tre (giao thuc danh gia muc 3).

=== 1.3.1 (07/11/2026) - diem danh doi thu hai: NGAN SACH BAO DONG GIA ===
R040 (ban dung): LAB-1 KHONG co ban ghi syscall cua tien trinh tan cong (chung
chay tren host, ngoai hai cgroup duoc loc) -> chua co nhan theo tid de co dinh
muc phat hien. Giao thuc danh gia muc 2 cho phep so sanh o "cung ngan sach bao
dong gia"; muc 4: nguong chon tren tap huan luyen. Vi vay them, KHONG thay the:
 - --ngan-sach b1,b2,...: nguong moi nhanh = phan vi (1-b) cua diem tren chinh
   tap HUAN LUYEN (trong mau, "trien khai duoc"); in bdg thuc dat tren huan
   luyen, nen kiem tra (ngay 6-7), theo muc, theo dai, song sinh, theo id/dot
   neu co nhan -> tom_tat_ngan_sach.tsv, theo_muc_ns_/theo_dai_ns_<branch>.tsv.
 - duong_tranh_chap_<branch>.tsv: voi luoi bdg nen-kiem-tra sach (0,05 %..20 %),
   nguong = phan vi diem nen kiem tra, cot = bdg tai tung muc tranh chap. Day la
   du lieu hinh trung tam C5 doc lap voi tan cong: truc hoanh bdg nen sach, truc
   tung bdg duoi tranh chap, moi nhanh mot duong.
 Toan hoc, dinh nghia cua so, chuan hoa, muc phat hien: KHONG doi.

=== 1.3.2 (07/11/2026) - chan doan, khong doi diem ===
R040 (M6i-b): nguong tai ngan sach <= 5 % la 1e5..4e7 o ca ba cach chuan hoa,
tuc |x-m| ~ 0,06 chia cho MAD = EPS = 1e-9 -> co chieu MAD = 0 trong dai/nen,
va diem cua cua so vuot nguong chi den tu chieu do. De nhin thay: (a) cot
chieu_max (chieu cho max|z|) trong scores_*.tsv; (b) chuan_<branch>.tsv: moi
(dai, chieu): n, median, MAD, mad0; (c) tom tat chieu_max cua 1 % diem huan
luyen cao nhat va cua cua so vuot nguong moi ngan sach. (d) --dai-che-do khong
van GAN nhan dai (chi de bao cao theo dai), thong ke van gop "*". (e) cot bat
dau bang x_ (thong ke ung vien do c5_extract v2 sinh) la boi canh, KHONG cham.
Diem so, tradeoff, tom_tat: giong het 1.3.1.

=== PHIEN BAN 1.4 (08/11/2026) - C5 v2, theo TIEN DANG KY v1.1 ===
Sau R041-b/R041-d (du lieu BENIGN): (F1) D1 hog CPU lam dich vu NHANH hon 10-20 %
(DVFS), rq chi +0,1-0,2 % -> tien de "Dt gian duoi tranh chap CPU" sai voi dich
vu I/O-bound; (F2) D3 (tranh chap bo nho/cache) moi lam gian (dt x1,7-1,9, own
x1,1-1,3); (F3) nen ngay 6-7 troi +10-15 % khong chu y (lang gieng ESXi, steal
= 0); (F4) 13 tid song lau (5 daemon pg + 8 worker nginx) chiem 33 % cua so, con
lai la backend pgbench 5 phut; (F5) x_inst (so lenh) gan nhu HANG SO qua 7 ngay
va moi lop/tid trong khi cpu/cpi troi theo DVFS+cache -> dem lenh tach hanh vi
tien trinh khoi trang thai may; cpu_time thi khong. Thay doi (ly do ghi o day va
o dau detector_c5.py 1.3):
 R1. Cua so hop le: n >= 30 ban ghi (>= 29 khoang). It hon -> KHONG cham, dem
     rieng "thua" (--n-toi-thieu, mac dinh 30).
 R2. Mien log cho dai luong ns: chieu TEN BAT DAU dt_/own_/cpu_/x_vol_/x_arr_
     va KHONG phai _cv (med/p90/iqr) duoc chuan hoa tren f = ln(gia_tri + 1000).
     _cv, x_blk, cpi_med, x_inst_* giu nguyen. Ly do: quan the chenh nhieu bac;
     z do ti le. (c5_extract KHONG doi; bien doi nam trong c5_score.)
 R3. Ho so nen theo LOP tien trinh: khoa = (cgroup_id, k=floor(log2(n/300))).
     R3b: tid co >= --tid-toi-thieu (mac dinh 200) cua so huan luyen -> ho so
     RIENG theo tid; con lai theo lop. Thieu mau (< --dai-toi-thieu): lop ke can
     k+-1..3 cung cgroup -> gop cgroup -> gop toan bo "*". Dai tai may (toc_do/
     nhip) TAT mac dinh (--phan-tang-tai de bat lai de hoi quy/doi chieu).
 R4. Hai cach hoc nen, bao cao CA HAI moi nhanh: "tinh" (median/MAD tren ca tap
     huan luyen) va "truot" (median/MAD cua cung ho so tren cua so khong giao
     nhan trong 24 gio lien truoc moc cua so; --nen-truot-gio 24). Diem/tradeoff
     chinh dung "tinh"; bang rieng cho "truot".
 R5. Tap chieu PHANRA chon trong {A,B,C,D,E} boi tieu chi bat bien tren r1 (ben
     ngoai script, ghi trong tien dang ky); --chieu-phanra chon bo. Mac dinh D =
     {x_arr_med, x_arr_p90, x_arr_iqr, x_arr_cv, x_inst_med, own_cv}. BASELINE
     giu {dt_med, dt_p90, dt_iqr, dt_cv}. AGG giu nguyen. Bo khac: A (own+cpu+cpi
     1.1), B (arr+cpu+cpi), C (A+arr), E (own+inst).
 Toan cham diem (max|z|, duong danh doi, ngan sach, muc phat hien, duong tranh
 chap, nhan theo tid) GIU NGUYEN. --mien-tuyen-tinh + --chieu-phanra A + khong
 phan tang + nen tinh = tuong duong 1.3.2 (de hoi quy).

Dau vao (--features): TSV co tieu de, moi dong mot cua so:
  branch  tid  start_ns  stop_ns  [nguon]  <cac cot dac trung...>
  - branch: BASELINE_dt_tho | PHANRA_5tp | AGG_cgroup_giay
  - cot dac trung: moi cot con lai la mot chieu; "nan" = thieu. Cot bat dau
    bang ctx_ la boi canh, KHONG cham. Cac cot n, n_banghi, cgroup_id, dai,
    toc_do (neu c5_extract sau nay them) la sieu du lieu, KHONG cham.
  Dinh nghia chieu CHOT (phai khop detector_c5.py):
    BASELINE_dt_tho: dt_med dt_p90 dt_iqr dt_cv
    PHANRA_5tp (v1.1): own_med own_p90 own_iqr own_cv cpu_med cpu_p90 cpi_med
    AGG_cgroup_giay (M6g): syscall_rate_mean syscall_rate_cv cpu_rate_mean
                     cpu_rate_cv own_rate_mean own_rate_cv tids_mean
  Cot `nguon` (chuoi): nen | bn | benign-lieu | slow (khong co -> nen).

--nhan nhan-tan-cong.tsv: cot t_bat_dau_mono_ns, t_ket_thuc_mono_ns, lop, id
  (tuy chon run_id, muc_tranh_chap). lop N = song sinh benign (kiem tra, tinh
  vao bao dong gia, bao cao rieng); lop khac = tan cong.
--nhan-tid nhan-tid.tsv: cot run_id, id, lop, tid, t_bat_dau_mono_ns,
  t_ket_thuc_mono_ns (mot dong moi tid; nhieu tid cho mot dot duoc). Tag cua
  dot = id[@muc_tranh_chap] lay tu dong --nhan co cung run_id (hoac cung id +
  khoang giao nhau), de hai bang khop ten.
--muc muc.tsv: start_ns stop_ns muc - muc tranh chap cua cua so (0 = nen).
--train-until NS: moc cat (mac dinh 70 % dau theo start_ns).
--dai-che-do toc_do|nhip|khong (mac dinh toc_do; khong co nguon toc do -> khong,
  co canh bao).  --dai-he-so 2  --dai-toi-thieu 8
--toc-do-giay FILE: TSV "giay n" (giay = ts_enter // 1e9) dem MOI ban ghi; neu
  co thi uu tien hon AGG.  --dai-nhip FILE: nhip-benign.tsv (nhip_id dich_vu
  muc t_bat_dau_mono_ns t_ket_thuc_mono_ns).  --nhip-muc "nginx:20,50,120,200;
  postgres:15,40,100" muc danh dinh de gan.  --D 300 (giay, do tre phat hien).  --ngan-sach 0.001,0.01,0.05 (1.3.1).
--out DIR: scores_<branch>.tsv (7 cot dau nhu 1.2 + song_sinh dai dai_dung
  toc_do), tradeoff_<branch>.tsv, tom_tat.tsv (4 cot dau nhu 1.2 + cot them),
  theo_muc_/theo_dai_/phat_hien_id_/do_tre_/dai_<branch>.tsv, nhip_kiem.tsv.

Cach dung:
  python3 c5_score.py --features F.tsv [--nhan nhan.tsv] [--nhan-tid nhan-tid.tsv]
          [--muc muc.tsv] [--train-until NS] [--dai-che-do toc_do|nhip|khong]
          [--dai-nhip nhip-benign.tsv] [--toc-do-giay giay.tsv] [--out DIR]
Chi thu vien chuan.
"""
import argparse
import bisect
import math
import os
import sys
from array import array

VERSION = "1.4.1"
EPS = 1e-9
DET_LEVELS = (0.5, 0.8, 0.9, 0.95, 1.0)
NGAN_SACH_MAC_DINH = "0.001,0.01,0.05"
LUOI_NEN = (0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2)
META_COLS = ("branch", "tid", "start_ns", "stop_ns", "nguon", "n", "n_banghi",
             "cgroup_id", "dai", "toc_do", "x_n_pmu")
LOG_SHIFT = 1000.0  # ns: f = ln(x + 1000) cho dai luong ns
N_TOI_THIEU_MD = 30
TID_TOI_THIEU_MD = 200
CHIEU_PHANRA = {
    "A": ["own_med", "own_p90", "own_iqr", "own_cv", "cpu_med", "cpu_p90", "cpi_med"],
    "B": ["x_arr_med", "x_arr_p90", "x_arr_iqr", "x_arr_cv", "cpu_med", "cpu_p90", "cpi_med"],
    "C": ["own_med", "own_p90", "own_iqr", "own_cv", "cpu_med", "cpu_p90", "cpi_med",
          "x_arr_med", "x_arr_p90", "x_arr_iqr", "x_arr_cv"],
    "D": ["x_arr_med", "x_arr_p90", "x_arr_iqr", "x_arr_cv", "x_inst_med", "own_cv"],
    "E": ["own_med", "own_p90", "own_iqr", "own_cv", "x_inst_med"],
}


def la_ns_dim(name):
    """True neu chieu la dai luong ns can mien log (khong gom _cv, x_blk, cpi, x_inst, x_n_pmu)."""
    if name.endswith("_cv") or name in ("x_blk",) or name.startswith("cpi") or name.startswith("x_inst") or name.startswith("x_n"):
        return False
    return name.startswith("dt_") or name.startswith("own_") or name.startswith("cpu_") or name.startswith("x_vol_") or name.startswith("x_arr_")
AGG_BRANCH = "AGG_cgroup_giay"
RATE_DIM = "syscall_rate_mean"
AGG_TOL_GAN_NS = 16 * 10**9      # cua so AGG "gan": |delta start| <= 16 s (buoc 30 s)
AGG_TOL_XA_NS = 300 * 10**9      # con chap nhan toi 300 s, dem rieng
NHIP_TOL_NS = 900 * 10**9        # nhip gan nhat trong 15 phut
NAN = float("nan")


def median(xs):
    s = sorted(xs)
    n = len(s)
    if n == 0:
        return NAN
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def mad(xs, m):
    return median([abs(x - m) for x in xs]) if xs else NAN


def f4(v):
    return "nan" if v != v else "%.4f" % v


class Row(object):
    __slots__ = ("branch", "tid", "start", "stop", "nguon", "f", "band", "rate",
                 "score", "used", "atk", "twin", "muc", "trong", "cmax", "khoa", "k", "cg", "npmu", "nrec", "tid_rieng")

    def __init__(self, branch, tid, start, stop, nguon, f):
        self.branch = branch
        self.tid = tid
        self.start = start
        self.stop = stop
        self.nguon = nguon
        self.f = f
        self.band = None
        self.rate = NAN
        self.score = NAN
        self.used = ""
        self.atk = None
        self.twin = None
        self.muc = None
        self.trong = False   # benign nhung nam trong khoang thoi gian cua mot dot tan cong
        self.cmax = -1       # chi so chieu cho max|z| (1.3.2)
        self.khoa = None     # khoa ho so nen (1.4): tid rieng hoac (cgroup,k)
        self.k = None        # lop hoat dong floor(log2(n/300))
        self.cg = None       # cgroup_id
        self.npmu = 0        # x_n_pmu cua cua so
        self.nrec = None     # n ban ghi cua cua so (cot n); None = khong co
        self.tid_rieng = False


def read_features(path, mien_log=True):
    rows = []
    intern = {}

    def it(s):
        return intern.setdefault(s, s)

    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        for k in ("branch", "tid", "start_ns", "stop_ns"):
            if k not in header:
                sys.exit("features thieu cot %s" % k)
        idx = {h: i for i, h in enumerate(header)}
        has_nguon = "nguon" in idx
        dims = [h for h in header if h not in META_COLS]
        dim_idx = [idx[d] for d in dims]
        is_log = [la_ns_dim(d) and mien_log for d in dims]   # 1.4: mien log cho dai luong ns (tat khi mien_tuyen_tinh)
        ib, itid, ist, isp = idx["branch"], idx["tid"], idx["start_ns"], idx["stop_ns"]
        inn = idx["nguon"] if has_nguon else -1
        icg = idx.get("cgroup_id", -1)
        inr = idx.get("n", -1)
        ipm = idx.get("x_n_pmu", -1)
        nh = len(header)
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < nh:
                continue
            f = array("d")
            for j, i in enumerate(dim_idx):
                try:
                    v = float(p[i])
                    if is_log[j] and v == v:
                        v = math.log(v + LOG_SHIFT) if v > -LOG_SHIFT else NAN
                except ValueError:
                    v = NAN
                f.append(v)
            try:
                r = Row(it(p[ib]), it(p[itid]), int(p[ist]), int(p[isp]),
                        it(p[inn]) if has_nguon else "nen", f)
                if icg >= 0 and icg < len(p):
                    r.cg = it(p[icg])
                if inr >= 0 and inr < len(p):
                    try:
                        nv = float(p[inr])
                        r.nrec = int(nv)
                        r.k = int(math.floor(math.log(nv / 300.0) / math.log(2))) if nv > 0 else None
                    except ValueError:
                        r.nrec = None
                        r.k = None
                if ipm >= 0 and ipm < len(p):
                    try:
                        r.npmu = int(float(p[ipm]))
                    except ValueError:
                        r.npmu = 0
                rows.append(r)
            except ValueError:
                continue
    return rows, dims


def read_table(path):
    """Doc TSV co tieu de -> (header, list cac dong da tach)."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        out = []
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            out.append(line.rstrip("\n").split("\t"))
    return header, out


def col(header, *names):
    idx = {h.strip(): i for i, h in enumerate(header)}
    for n in names:
        if n in idx:
            return idx[n]
    return None


def read_nhan(path):
    """-> list dict(lo, hi, tag, lop, twin). Tag = id[@muc_tranh_chap][#run_id neu trung]."""
    out = []
    if not path:
        return out
    header, lines = read_table(path)
    a = col(header, "t_bat_dau_mono_ns")
    b = col(header, "t_ket_thuc_mono_ns")
    il = col(header, "lop")
    ii = col(header, "id")
    ir = col(header, "run_id")
    im = col(header, "muc_tranh_chap")
    if a is None or b is None:
        sys.exit("nhan-tan-cong.tsv thieu cot t_bat_dau_mono_ns/t_ket_thuc_mono_ns")
    for p in lines:
        if len(p) <= max(a, b):
            continue
        try:
            lo, hi = int(p[a]), int(p[b])
        except ValueError:
            continue
        lop = p[il].strip() if il is not None and il < len(p) else "?"
        ident = p[ii].strip() if ii is not None and ii < len(p) else "?"
        muc = p[im].strip() if im is not None and im < len(p) else ""
        run = p[ir].strip() if ir is not None and ir < len(p) else ""
        tag = ident + ("@" + muc if muc else "")
        out.append({"lo": lo, "hi": hi, "tag": tag, "lop": lop, "run": run,
                    "twin": lop.upper().startswith("N")})
    seen = {}
    for lb in out:
        seen[lb["tag"]] = seen.get(lb["tag"], 0) + 1
    for lb in out:
        if seen[lb["tag"]] > 1 and lb["run"]:
            lb["tag"] = lb["tag"] + "#" + lb["run"]
    return out


def chuan_tid(t):
    t = t.strip()
    try:
        return str(int(t))
    except ValueError:
        return t


def read_nhan_tid(path, labels):
    """-> dict tid -> list dict(lo, hi, tag, twin). Tag khop voi --nhan qua run_id,
    neu khong co run_id thi qua id + khoang giao nhau."""
    out = {}
    if not path:
        return out
    header, lines = read_table(path)
    a = col(header, "t_bat_dau_mono_ns")
    b = col(header, "t_ket_thuc_mono_ns")
    it = col(header, "tid")
    il = col(header, "lop")
    ii = col(header, "id")
    ir = col(header, "run_id")
    if a is None or b is None or it is None:
        sys.exit("nhan-tid.tsv thieu cot (can tid, t_bat_dau_mono_ns, t_ket_thuc_mono_ns)")
    n = 0
    for p in lines:
        if len(p) <= max(a, b, it):
            continue
        try:
            lo, hi = int(p[a]), int(p[b])
        except ValueError:
            continue
        tid = chuan_tid(p[it])
        lop = p[il].strip() if il is not None and il < len(p) else "?"
        ident = p[ii].strip() if ii is not None and ii < len(p) else "?"
        run = p[ir].strip() if ir is not None and ir < len(p) else ""
        tag = None
        for lb in labels:
            if run and lb["run"] == run:
                tag = lb["tag"]
                break
        if tag is None:
            for lb in labels:
                if lb["tag"].split("@")[0].split("#")[0] == ident and lb["lo"] < hi and lb["hi"] > lo:
                    tag = lb["tag"]
                    break
        if tag is None:
            tag = ident + ("#" + run if run else "")
        out.setdefault(tid, []).append({"lo": lo, "hi": hi, "tag": tag,
                                        "twin": lop.upper().startswith("N")})
        n += 1
    return out


def read_muc(path):
    out = []
    if not path:
        return out
    header, lines = read_table(path)
    a, b, m = col(header, "start_ns"), col(header, "stop_ns"), col(header, "muc")
    if a is None or b is None or m is None:
        return out
    for p in lines:
        if len(p) <= max(a, b, m):
            continue
        try:
            out.append((int(p[a]), int(p[b]), p[m].strip()))
        except ValueError:
            continue
    return out


def overlap_len(w, lo, hi):
    return min(w.stop, hi) - max(w.start, lo)


def _gan(w, cands):
    best_a, best_al, best_t, best_tl = None, 0, None, 0
    for lb in cands:
        ol = overlap_len(w, lb["lo"], lb["hi"])
        if ol <= 0:
            continue
        if lb["twin"]:
            if ol > best_tl:
                best_t, best_tl = lb["tag"], ol
        elif ol > best_al:
            best_a, best_al = lb["tag"], ol
    return best_a, (best_t if best_a is None else None)


def gan_nhan(w, labels, tid_labels, theo_tid):
    """Gan atk (tag tan cong) / twin (tag song sinh) / trong (benign trong khoang tan cong).
    theo_tid va nhanh khac AGG: chi cua so cua tid trong nhan-tid la tan cong/song sinh;
    nguoc lai (1.2): moi cua so giao khoang nhan."""
    a_time, t_time = _gan(w, labels)
    if theo_tid and w.branch != AGG_BRANCH:
        a, t = _gan(w, tid_labels.get(chuan_tid(w.tid), ()))
        w.atk, w.twin = a, t
        w.trong = (a is None and a_time is not None)
    else:
        w.atk, w.twin = a_time, t_time
        w.trong = False


def gan_muc(w, muc):
    for lo, hi, m in muc:
        if w.start < hi and w.stop > lo:
            w.muc = m
            return
    w.muc = None


# ---------------- nguon toc do (ban ghi/giay tong) ----------------

class TocDoGiay(object):
    """Tu file dem theo giay: toc do chinh xac trong [start, stop)."""

    def __init__(self, path):
        header, lines = read_table(path)
        pairs = []
        hl = [h.strip() for h in header]
        try:  # tieu de co the la so (file khong tieu de)
            pairs.append((int(hl[0]), int(hl[1])))
        except (ValueError, IndexError):
            pass
        for p in lines:
            try:
                pairs.append((int(p[0]), int(p[1])))
            except (ValueError, IndexError):
                continue
        pairs.sort()
        if not pairs:
            sys.exit("file dem theo giay rong")
        self.s0 = pairs[0][0]
        n = pairs[-1][0] - self.s0 + 1
        cnt = [0] * n
        for s, c in pairs:
            cnt[s - self.s0] += c
        pre = [0] * (n + 1)
        for i in range(n):
            pre[i + 1] = pre[i] + cnt[i]
        self.pre = pre
        self.n = n
        self.tong = pre[-1]
        self.thieu = 0

    def rate(self, start, stop):
        a = max(0, min(self.n, start // 10**9 - self.s0))
        b = max(0, min(self.n, (stop + 10**9 - 1) // 10**9 - self.s0))
        if b <= a:
            self.thieu += 1
            return NAN
        return (self.pre[b] - self.pre[a]) / float(b - a)

    def mo_ta(self):
        return "dem theo giay: %d giay, %d ban ghi" % (self.n, self.tong)


class TocDoAGG(object):
    """Tu nhanh AGG_cgroup_giay: cong syscall_rate_mean cua moi cgroup tai cua
    so AGG co start gan nhat (<= 16 s; 300 s thi dem 'xa'; khong co -> thieu)."""

    def __init__(self, rows, dims):
        di = dims.index(RATE_DIM) if RATE_DIM in dims else None
        self.cg = {}
        if di is not None:
            for w in rows:
                if w.branch == AGG_BRANCH and w.f[di] == w.f[di]:
                    self.cg.setdefault(w.tid, []).append((w.start, w.f[di]))
        for k in self.cg:
            self.cg[k].sort()
        self.starts = {k: [s for s, _ in v] for k, v in self.cg.items()}
        self.n_gan = self.n_xa = self.n_thieu = 0

    def ok(self):
        return bool(self.cg)

    def rate(self, start, stop):
        tot, used = 0.0, 0
        for k, st in self.starts.items():
            i = bisect.bisect_left(st, start)
            cand = []
            if i < len(st):
                cand.append(i)
            if i > 0:
                cand.append(i - 1)
            j = min(cand, key=lambda q: abs(st[q] - start)) if cand else None
            if j is None:
                self.n_thieu += 1
                continue
            d = abs(st[j] - start)
            if d <= AGG_TOL_GAN_NS:
                self.n_gan += 1
            elif d <= AGG_TOL_XA_NS:
                self.n_xa += 1
            else:
                self.n_thieu += 1
                continue
            tot += self.cg[k][j][1]
            used += 1
        return tot if used else NAN

    def mo_ta(self):
        return "AGG: %d cgroup, %s cua so AGG" % (
            len(self.cg), "+".join(str(len(v)) for v in self.cg.values()))


def band_rate(rate, he_so):
    if rate != rate or rate <= 0:
        return None
    return "r%d" % int(math.floor(math.log(rate) / math.log(he_so) + 1e-12))


def band_k(label):
    try:
        return int(label[1:]) if label and label[0] == "r" else None
    except ValueError:
        return None


# ---------------- nhip generator (lab) ----------------

class Nhip(object):
    def __init__(self, path, muc_spec):
        self.nominal = {}
        for part in (muc_spec or "").split(";"):
            if ":" not in part:
                continue
            svc, vals = part.split(":", 1)
            try:
                self.nominal[svc.strip().lower()] = sorted(float(v) for v in vals.split(",") if v.strip())
            except ValueError:
                pass
        self.union = sorted({v for vs in self.nominal.values() for v in vs})
        header, lines = read_table(path)
        a = col(header, "t_bat_dau_mono_ns", "t_bat_dau", "start_ns")
        b = col(header, "t_ket_thuc_mono_ns", "t_ket_thuc", "stop_ns")
        isv = col(header, "dich_vu", "dichvu", "service")
        im = col(header, "muc", "level")
        if a is None or b is None or im is None:
            sys.exit("nhip-benign.tsv thieu cot (can t_bat_dau_mono_ns, t_ket_thuc_mono_ns, muc; dich_vu tuy chon)")
        per = {}
        self.rows = []
        for p in lines:
            if len(p) <= max(a, b, im):
                continue
            try:
                lo, hi = int(p[a]), int(p[b])
            except ValueError:
                continue
            svc = p[isv].strip() if isv is not None and isv < len(p) else "svc"
            svc, lvl = self.chuan_muc(svc, p[im].strip())
            per.setdefault(svc, []).append((lo, hi, lvl))
            self.rows.append((svc, lvl, lo, hi))
        self.svc = {}
        for s, v in per.items():
            v.sort()
            self.svc[s] = (v, [x[0] for x in v])
        self.n_thieu = 0

    def chuan_muc(self, svc, muc):
        """muc so -> gan ve muc danh dinh gan nhat (khoang cach log); muc chu -> giu.
        muc dang 'nginx120' -> tach dich vu + so."""
        m = muc.replace(" ", "")
        s = svc.lower()
        if not any(ch.isdigit() for ch in m):
            return s, m
        head = m.rstrip("0123456789.")
        num = m[len(head):]
        if head and head.lower() not in ("", s):
            s = head.lower() if s in ("svc", "") else s
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
        mid = (w.start + w.stop) // 2
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
                        d = 0 if v[j][0] <= mid < v[j][1] else min(abs(mid - v[j][0]), abs(mid - v[j][1]))
                        if d <= NHIP_TOL_NS and (best is None or d < best[0]):
                            best = (d, v[j][2])
                if best:
                    lvl = best[1]
            parts.append("%s%s" % (s, lvl if lvl is not None else "?"))
        if all(p.endswith("?") for p in parts):
            self.n_thieu += 1
            return None
        return "|".join(parts)


# ---------------- chuan hoa va cham diem ----------------

def fit_stats(train, dims_idx, toi_thieu, phan_tang=True, dung_khoa=False, bo_mad0=False):
    """-> {label: {di: (m,a,n,mad0) or None}}. dung_khoa=True: nhom theo w.khoa (1.4)
    va them nhom gop cgroup 'cg:<cg>|k:*'; nguoc lai nhom theo w.band (compat)."""
    groups = {"*": train}
    if dung_khoa:
        for w in train:
            if w.khoa is not None:
                groups.setdefault(w.khoa, []).append(w)
                if w.khoa.startswith("cg:") and w.cg is not None:
                    groups.setdefault("cg:%s|k:*" % w.cg, []).append(w)
    elif phan_tang:
        for w in train:
            if w.band is not None:
                groups.setdefault(w.band, []).append(w)
    stats = {}
    for b, ws in groups.items():
        st = {}
        for di in dims_idx:
            xs = [w.f[di] for w in ws if w.f[di] == w.f[di]]
            if len(xs) < toi_thieu:
                st[di] = None
                continue
            m = median(xs)
            a = mad(xs, m)
            if a <= 0:
                # MAD=0: chieu khong mang thong tin trong ho so nay.
                # bo_mad0 (mien log 1.4.1): BO chieu khoi cham (a=NAN -> score bo qua),
                # tranh z khong lo do chia EPS. Che do tuong thich (khong bo_mad0): giu EPS nhu 1.3.2.
                st[di] = (m, (NAN if bo_mad0 else EPS), len(xs), 1)
            else:
                st[di] = (m, a, len(xs), 0)
        stats[b] = st
    return stats


def thu_tu_du_phong(band, phan_tang=True):
    if band is None or not phan_tang:
        return ["*"]
    k = band_k(band)
    if k is None:
        return [band, "*"]
    return [band, "r%d" % (k - 1), "r%d" % (k + 1), "r%d" % (k - 2), "r%d" % (k + 2),
            "r%d" % (k - 3), "r%d" % (k + 3), "*"]


def khoa_ho_so(w, ho_so):
    """1.4: khoa ho so nen. ho_so='tid_lop' -> tid rieng neu du mau, khong thi (cg,k);
    ho_so='lop' -> luon (cg,k); ho_so='tat' -> None (dung band cu / '*')."""
    if ho_so == "tat":
        return None
    if ho_so == "tid_lop" and getattr(w, "tid_rieng", False):
        return "tid:" + w.tid
    cg = w.cg if w.cg is not None else "?"
    kk = w.k
    return "cg:%s|k:%s" % (cg, kk if kk is not None else "?")


def thu_tu_khoa(khoa):
    """Du phong cho khoa 1.4: tid rieng -> lop cua tid -> lop ke can -> gop cgroup -> '*'."""
    if khoa is None:
        return ["*"]
    if khoa.startswith("tid:"):
        # tid rieng khong co du phong theo tid khac; roi ve '*' (lop gan duoc dat qua khoa_lop)
        return [khoa, "*"]
    # khoa dang cg:<cg>|k:<k>
    try:
        cgpart, kpart = khoa.split("|")
        cg = cgpart[3:]
        k = int(kpart[2:]) if kpart[2:] not in ("None", "?") else None
    except (ValueError, IndexError):
        return [khoa, "*"]
    out = [khoa]
    if k is not None:
        for d in (1, -1, 2, -2, 3, -3):
            out.append("cg:%s|k:%s" % (cg, k + d))
    out.append("cg:%s|k:*" % cg)   # gop moi k cua cgroup
    out.append("*")
    return out


def score(w, stats, dims_idx, order_cache, phan_tang=True, dung_khoa=False):
    key = w.khoa if dung_khoa else w.band
    order = order_cache.get(("k" if dung_khoa else "b", key))
    if order is None:
        order = thu_tu_khoa(key) if dung_khoa else thu_tu_du_phong(w.band, phan_tang)
        order_cache[("k" if dung_khoa else "b", key)] = order
    best, used, bands, cmax = 0.0, 0, set(), -1
    for di in dims_idx:
        v = w.f[di]
        if v != v:
            continue
        for b in order:
            st = stats.get(b)
            if st is None:
                continue
            ma = st.get(di)
            if ma is None:
                continue
            m, a = ma[0], ma[1]
            if a != a:          # a=NAN: chieu MAD=0 bi bo (1.4.1 mien log)
                break
            z = abs(v - m) / (1.4826 * a)
            if z > best or used == 0:
                best, cmax = max(best, z), di
            used += 1
            bands.add(b)
            break
    w.score = best if used else NAN
    w.used = "+".join(sorted(bands)) if bands else ""
    w.cmax = cmax if used else -1
    return w.score


def tradeoff(scored):
    """scored: list Row da cham. Nhu 1.2 (nguong = diem lam tron 4 chu so, giam dan;
    dem s >= thr) nhung tinh bang mang sap xep + bisect."""
    benign = sorted(w.score for w in scored if w.atk is None)
    attack = sorted(w.score for w in scored if w.atk is not None)
    nb, na = len(benign) or 1, len(attack)
    out = []
    for thr in sorted({round(w.score, 4) for w in scored}, reverse=True):
        fa = len(benign) - bisect.bisect_left(benign, thr)
        det = na - bisect.bisect_left(attack, thr)
        out.append((thr, fa / nb, (det / na if na else NAN), fa, det))
    return out


def thr_at_detection(tb, level):
    for thr, far, det, fa, d in tb:
        if det == det and det >= level:
            return thr, far
    return NAN, NAN


def ti_le(ws, thr):
    n = len(ws)
    if n == 0 or thr != thr:
        return NAN, n, 0
    h = sum(1 for w in ws if w.score >= thr)
    return h / n, n, h


def nguong_ngan_sach(scores_desc, b):
    """scores_desc: list diem giam dan. Nguong sao cho ti le diem >= nguong <= b
    (xap xi: lay diem lon thu floor(b*n); b*n < 1 -> cao hon diem lon nhat)."""
    n = len(scores_desc)
    if n == 0:
        return NAN
    k = int(b * n)
    if k <= 0:
        return scores_desc[0] * (1 + 1e-9) + 1e-12
    return scores_desc[k - 1]


def xep_dai(items):
    return sorted(items, key=lambda kv: (band_k(kv[0]) is None, band_k(kv[0]) or 0, kv[0]))


def dem_theo(ws, key):
    by = {}
    for w in ws:
        by.setdefault(key(w), []).append(w)
    return by


def bao_cao_nguong(nhan_dong, thr, ctx, sink):
    """In va ghi cac bang tai mot nguong. ctx: dict cac tap; sink: dict ten -> list dong."""
    benign_all, nen_kt, twins, trong = ctx["benign_all"], ctx["nen_kt"], ctx["twins"], ctx["trong"]
    atk_by, twin_by, labels, che_do, D, D_ns, scored = (ctx["atk_by"], ctx["twin_by"], ctx["labels"],
                                                       ctx["che_do"], ctx["D"], ctx["D_ns"], ctx["scored"])
    by = dem_theo(benign_all, lambda w: w.muc if w.muc is not None else "0")
    print("  theo muc: " + "  ".join("%s:%s(%d)" % (k, f4(ti_le(v, thr)[0]), len(v)) for k, v in sorted(by.items())))
    for k, v in sorted(by.items()):
        r, n, h = ti_le(v, thr)
        sink["theo_muc"].append("%s\t%s\t%s\t%s\t%d\t%d" % (nhan_dong, f4(thr), k, f4(r), h, n))
    if any(w.band is not None for w in nen_kt):
        byd = dem_theo(nen_kt, lambda w: w.band or "-")
        print("  theo dai (nen kiem tra): " + "  ".join(
            "%s:%s(%d)" % (k, f4(ti_le(v, thr)[0]), len(v)) for k, v in xep_dai(byd.items())))
        for k, v in sorted(byd.items()):
            r, n, h = ti_le(v, thr)
            sink["theo_dai"].append("%s\t%s\t%s\t%s\t%d\t%d" % (nhan_dong, f4(thr), k, f4(r), h, n))
    parts = []
    for k, v in sorted(atk_by.items()):
        r, n, h = ti_le(v, thr)
        parts.append("%s:%s(%d)" % (k, f4(r), n))
        sink["id"].append("%s\t%s\ttan_cong\t%s\t%s\t%d\t%d" % (nhan_dong, f4(thr), k, f4(r), h, n))
    for k, v in sorted(twin_by.items()):
        r, n, h = ti_le(v, thr)
        parts.append("%s(song sinh):%s(%d)" % (k, f4(r), n))
        sink["id"].append("%s\t%s\tsong_sinh\t%s\t%s\t%d\t%d" % (nhan_dong, f4(thr), k, f4(r), h, n))
    if parts:
        print("  theo id: " + "  ".join(parts))
    parts = []
    for lb in labels:
        if lb["twin"]:
            continue
        ws_all = atk_by.get(lb["tag"], [])
        ws = [w for w in ws_all if w.score >= thr]
        if ws:
            first = min(w.stop for w in ws)
            tre = (first - lb["lo"]) / 1e9
            ok = "co" if (first - lb["lo"]) <= D_ns else "tre"
        else:
            tre, ok = NAN, ("khong" if ws_all else "khong_cua_so")
        parts.append("%s:%s%s" % (lb["tag"], ok, ("(%.0fs)" % tre) if tre == tre else ""))
        sink["tre"].append("%s\t%s\t%s\t%s\t%s" % (nhan_dong, f4(thr), lb["tag"], ok, f4(tre)))
    if parts:
        print("  dot trong D=%.0fs: " % D + "  ".join(parts))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", required=True)
    ap.add_argument("--nhan", default=None)
    ap.add_argument("--nhan-tid", default=None, help="nhan theo tid (run_id id lop tid t_bat_dau_mono_ns t_ket_thuc_mono_ns)")
    ap.add_argument("--muc", default=None, help="TSV start_ns stop_ns muc")
    ap.add_argument("--train-until", type=int, default=None)
    ap.add_argument("--dai-che-do", default="toc_do", choices=("toc_do", "nhip", "khong"))
    ap.add_argument("--dai-he-so", type=float, default=2.0)
    ap.add_argument("--dai-toi-thieu", type=int, default=8)
    ap.add_argument("--toc-do-giay", default=None, help="TSV giay n (dem moi ban ghi)")
    ap.add_argument("--dai-nhip", default=None, help="nhip-benign.tsv")
    ap.add_argument("--nhip-muc", default="nginx:20,50,120,200;postgres:15,40,100;pg:15,40,100;pgsql:15,40,100")
    ap.add_argument("--D", type=float, default=300.0, help="giay: do tre phat hien toi da (giao thuc)")
    ap.add_argument("--ngan-sach", default=NGAN_SACH_MAC_DINH,
                    help="cac ngan sach bao dong gia (ti le cua so huan luyen vuot nguong), vd 0.001,0.01,0.05")
    # --- 1.4 ---
    ap.add_argument("--chieu-phanra", default="D", choices=sorted(CHIEU_PHANRA),
                    help="bo chieu PHANRA (1.4): A own+cpu+cpi(1.1) | B arr+cpu+cpi | C A+arr | D arr+inst+own_cv(mac dinh) | E own+inst")
    ap.add_argument("--ho-so", default="tid_lop", choices=("tid_lop", "lop", "tat"),
                    help="ho so nen (1.4): tid_lop (tid rieng neu du mau, khong thi lop cgroup-k) | lop | tat (nhu band cu)")
    ap.add_argument("--n-toi-thieu", type=int, default=N_TOI_THIEU_MD, help="cua so hop le phai co n>=N (1.4)")
    ap.add_argument("--tid-toi-thieu", type=int, default=TID_TOI_THIEU_MD, help="tid co >=N cua so huan luyen -> ho so rieng (1.4)")
    ap.add_argument("--nen-truot-gio", type=float, default=0.0, help="neu >0: bao cao them nen truot trong cua so N gio truoc (1.4)")
    ap.add_argument("--mien-tuyen-tinh", action="store_true", help="TAT mien log (de hoi quy 1.3.2)")
    ap.add_argument("--phan-tang-tai", action="store_true", help="BAT dai tai may (toc_do/nhip) lam ho so (mac dinh TAT o 1.4)")
    ap.add_argument("--giu-mad0", action="store_true", help="GIU chieu MAD=0 (thay EPS) thay vi bo; mac dinh BO khi mien log (1.4.1)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv[1:])

    rows, dims_all = read_features(a.features, mien_log=(not a.mien_tuyen_tinh))
    if not rows:
        sys.exit("khong co cua so")
    # 1.4: loc cua so hop le theo n ban ghi that (cot n); AGG giu nguyen (don vi cgroup).
    n_thua = 0
    if a.n_toi_thieu > 0:
        keep = []
        for w in rows:
            if w.branch != AGG_BRANCH and w.nrec is not None and w.nrec < a.n_toi_thieu:
                n_thua += 1
            else:
                keep.append(w)
        rows = keep
    if n_thua:
        print("# 1.4: loai %d cua so 'thua' (n < %d); AGG giu nguyen" % (n_thua, a.n_toi_thieu))
    labels = read_nhan(a.nhan)
    tid_labels = read_nhan_tid(a.nhan_tid, labels)
    theo_tid = bool(tid_labels)
    if labels and not theo_tid:
        print("# CANH BAO: khong co --nhan-tid -> cua so tan cong = moi tid giao khoang nhan (hanh vi 1.2, xem dau file muc (3))")
    muc = read_muc(a.muc)
    for w in rows:
        if labels:
            gan_nhan(w, labels, tid_labels, theo_tid)
        if muc:
            gan_muc(w, muc)
    tmin = min(w.start for w in rows)
    tmax = max(w.start for w in rows)
    cut = a.train_until if a.train_until else tmin + int(0.7 * (tmax - tmin))
    outdir = a.out
    if outdir:
        os.makedirs(outdir, exist_ok=True)
    D_ns = int(a.D * 1e9)
    try:
        ngan_sach = [float(x) for x in a.ngan_sach.split(",") if x.strip()]
    except ValueError:
        sys.exit("--ngan-sach khong hop le")

    # --- nguon toc do va dai ---
    che_do = a.dai_che_do
    toc_do = None
    nhip = None
    if a.toc_do_giay:
        toc_do = TocDoGiay(a.toc_do_giay)
    else:
        toc_do = TocDoAGG(rows, dims_all)
        if not toc_do.ok():
            toc_do = None
    if a.dai_nhip:
        nhip = Nhip(a.dai_nhip, a.nhip_muc)
    if che_do == "toc_do" and toc_do is None:
        print("# CANH BAO: khong co nguon toc do (khong AGG_cgroup_giay, khong --toc-do-giay) -> dai-che-do=khong")
        che_do = "khong"
    if che_do == "nhip" and nhip is None:
        sys.exit("--dai-che-do nhip can --dai-nhip")
    if toc_do is not None:
        for w in rows:
            w.rate = toc_do.rate(w.start, w.stop)
    phan_tang = che_do != "khong"
    if che_do == "nhip":
        for w in rows:
            w.band = nhip.band(w)
    elif toc_do is not None:   # toc_do, hoac khong (chi gan nhan de bao cao theo dai)
        for w in rows:
            w.band = band_rate(w.rate, a.dai_he_so)

    print("# c5_score %s  cat_huan_luyen=%d  cua_so=%d  nhan=%d (tan_cong=%d song_sinh=%d)  muc=%d" % (
        VERSION, cut, len(rows), len(labels), sum(1 for l in labels if not l["twin"]),
        sum(1 for l in labels if l["twin"]), len(muc)))
    print("# nhan theo tid: %s (%d tid co nhan)" % ("co" if theo_tid else "KHONG", len(tid_labels)))
    print("# dai_che_do=%s he_so=%g toi_thieu=%d | toc_do: %s | nhip: %s" % (
        che_do, a.dai_he_so, a.dai_toi_thieu,
        toc_do.mo_ta() if toc_do else "khong", ("%d dong, dich_vu=%s" % (len(nhip.rows), ",".join(sorted(nhip.svc))) if nhip else "khong")))
    if isinstance(toc_do, TocDoAGG):
        print("# ghep AGG: gan(<=16s)=%d xa(<=300s)=%d thieu=%d (dem theo cgroup x cua so)" % (
            toc_do.n_gan, toc_do.n_xa, toc_do.n_thieu))
    if che_do == "nhip":
        print("# nhip: cua so khong tim duoc nhip nao trong 15 phut = %d" % nhip.n_thieu)

    # --- kiem khop nhip <-> toc do (khi co ca hai) ---
    if nhip is not None and toc_do is not None:
        by_lv = {}
        n_co = 0
        for svc, lvl, lo, hi in nhip.rows:
            r = toc_do.rate(lo, hi)
            if r == r:
                n_co += 1
                by_lv.setdefault((svc, lvl), []).append(r)
        print("\n# KIEM KHOP nhip-benign <-> toc do tong (ban ghi/giay) trong tung nhip: "
              "%d/%d nhip co du lieu; ky vong toc do tang theo muc cua moi dich vu" % (n_co, len(nhip.rows)))
        print("dich_vu\tmuc\tn_nhip\ttoc_do_trung_vi\ttoc_do_p10\ttoc_do_p90")
        lines_k = []
        for (svc, lvl), rs in sorted(by_lv.items(), key=lambda kv: (kv[0][0], float(kv[0][1]) if kv[0][1].replace(".", "", 1).isdigit() else 0)):
            s = sorted(rs)
            p10, p90 = s[int(0.1 * (len(s) - 1))], s[int(0.9 * (len(s) - 1))]
            line = "%s\t%s\t%d\t%.1f\t%.1f\t%.1f" % (svc, lvl, len(rs), median(rs), p10, p90)
            print(line)
            lines_k.append(line)
        if outdir:
            with open(os.path.join(outdir, "nhip_kiem.tsv"), "w") as fh:
                fh.write("dich_vu\tmuc\tn_nhip\ttoc_do_trung_vi\ttoc_do_p10\ttoc_do_p90\n")
                fh.write("\n".join(lines_k) + ("\n" if lines_k else ""))
        if n_co == 0:
            print("# CANH BAO: khong nhip nao giao voi du lieu -> moc mono_ns cua nhip-benign KHONG cung he voi ban ghi?")

    branches = sorted({w.branch for w in rows})
    summary = []
    summary_ns = []
    order_cache = {}
    # 1.4: tap chieu cho tung nhanh
    phanra_set = CHIEU_PHANRA[a.chieu_phanra]
    base_set = ["dt_med", "dt_p90", "dt_iqr", "dt_cv"]
    dung_khoa = (a.ho_so != "tat")
    bo_mad0 = (not a.mien_tuyen_tinh) and (not a.giu_mad0)   # 1.4.1: bo chieu MAD=0 khi mien log
    if a.phan_tang_tai and dung_khoa:
        print("# CANH BAO: --phan-tang-tai bo qua khi --ho-so != tat (1.4 dung ho so tien trinh)")
    print("# 1.4: chieu_phanra=%s (%s) | ho_so=%s | mien_log=%s | n_toi_thieu=%d tid_toi_thieu=%d" % (
        a.chieu_phanra, "+".join(phanra_set), a.ho_so, "khong" if a.mien_tuyen_tinh else "co",
        a.n_toi_thieu, a.tid_toi_thieu))
    print("# 1.4.1: bo_chieu_MAD0=%s (mien log); nguong ngan sach khong con bi z khong lo do EPS" % ("co" if bo_mad0 else "khong"))
    if a.nen_truot_gio > 0:
        print("# CHU Y: --nen-truot-gio=%g duoc KHAI BAO nhung chua cai trong 1.4; nen 'tinh' van la nen chinh. "
              "Nen truot se lam o M6i-c2 (bang bao cao rieng). Bo qua o lan chay nay." % a.nen_truot_gio)
    for b in branches:
        rb = [w for w in rows if w.branch == b]
        # 1.4: chon chieu theo nhanh; cho phep x_arr_*/x_inst_* khi bo chieu yeu cau
        if b == "BASELINE_dt_tho":
            want = base_set
        elif b == "PHANRA_5tp":
            want = phanra_set
        else:
            want = None   # AGG: dung moi chieu khong phai ctx_/x_ (nhu cu)
        if want is not None:
            dims_idx = [i for i, d in enumerate(dims_all) if d in want
                        and any(w.f[i] == w.f[i] for w in rb)]
        else:
            dims_idx = [i for i, d in enumerate(dims_all) if not d.startswith("ctx_") and not d.startswith("x_")
                        and any(w.f[i] == w.f[i] for w in rb)]
        # QUY TAC CAT 1.3
        train = [w for w in rb if w.nguon == "nen" and w.stop <= cut and w.atk is None
                 and w.twin is None and (w.muc is None or w.muc == "0")]
        test = [w for w in rb if w.nguon != "nen" or w.start >= cut or w.atk is not None
                or w.twin is not None or (w.muc is not None and w.muc != "0")]
        # 1.4: danh dau tid song lau (>= tid_toi_thieu cua so huan luyen) -> ho so rieng; gan khoa
        if dung_khoa:
            cnt = {}
            for w in train:
                cnt[w.tid] = cnt.get(w.tid, 0) + 1
            big = {t for t, c in cnt.items() if c >= a.tid_toi_thieu} if b != AGG_BRANCH else set()
            for w in rb:
                w.tid_rieng = (w.tid in big)
                w.khoa = khoa_ho_so(w, a.ho_so)
        else:
            for w in rb:
                w.tid_rieng = False
                w.khoa = None
        stats = fit_stats(train, dims_idx, a.dai_toi_thieu, phan_tang, dung_khoa, bo_mad0)
        active = [dims_all[i] for i in dims_idx if stats["*"].get(i) is not None]
        pool = test if test else rb
        scored = []
        for w in pool:
            s = score(w, stats, dims_idx, order_cache, phan_tang, dung_khoa)
            if s == s:
                scored.append(w)
        # 1.3.2: chan doan chuan hoa
        mad0 = [(bnd, dims_all[di]) for bnd, st in stats.items() for di, ma in st.items() if ma is not None and ma[3]]
        print("chieu co MAD=0 (dung EPS=1e-9) theo dai: %d%s" % (
            len(mad0), (" -> " + "  ".join("%s:%s" % x for x in sorted(mad0)[:40]) + (" ..." if len(mad0) > 40 else "")) if mad0 else ""))
        if outdir:
            with open(os.path.join(outdir, "chuan_%s.tsv" % b), "w") as fh:
                fh.write("dai\tchieu\tn\tmedian\tMAD\tmad0\n")
                for bnd in sorted(stats, key=lambda x: (x != "*", band_k(x) is None, band_k(x) or 0, x)):
                    for di in dims_idx:
                        ma = stats[bnd].get(di)
                        if ma is None:
                            fh.write("%s\t%s\t0\tnan\tnan\t-\n" % (bnd, dims_all[di]))
                        else:
                            fh.write("%s\t%s\t%d\t%.9g\t%.9g\t%d\n" % (bnd, dims_all[di], ma[2], ma[0], ma[1], ma[3]))
        src = dem_theo(test, lambda w: w.nguon)
        print("\n=== %s === huan_luyen=%d kiem_tra=%d (%s) chieu=%s" % (
            b, len(train), len(test), " ".join("%s:%d" % (k, len(v)) for k, v in sorted(src.items())), ",".join(active)))
        # bang dai
        tr_b = dem_theo(train, lambda w: w.band or "-")
        te_b = dem_theo(scored, lambda w: w.band or "-")
        print("dai\tkhoang_toc_do\thuan_luyen\tkiem_tra\tkt_nen\tkt_tan_cong\tdu_mau")
        dai_lines = []
        for d in sorted(set(tr_b) | set(te_b), key=lambda x: (band_k(x) is None, band_k(x) or 0, x)):
            k = band_k(d)
            kho = ("[%g,%g)" % (a.dai_he_so ** k, a.dai_he_so ** (k + 1))) if k is not None else "-"
            ws = te_b.get(d, [])
            dk = "*" if (d == "-" or not phan_tang) else d
            du = "co" if dk in stats and all(stats[dk].get(i) is not None for i in dims_idx
                                              if stats["*"].get(i) is not None) else "khong"
            line = "%s\t%s\t%d\t%d\t%d\t%d\t%s" % (
                d, kho, len(tr_b.get(d, [])), len(ws),
                sum(1 for w in ws if w.nguon == "nen" and w.atk is None and w.twin is None),
                sum(1 for w in ws if w.atk is not None), du)
            print(line)
            dai_lines.append(line)
        n_dp = sum(1 for w in scored if w.used and w.used != (w.band or "*"))
        print("cua so kiem tra dung du phong (dai ke can hoac '*'): %d / %d" % (n_dp, len(scored)))
        if outdir:
            with open(os.path.join(outdir, "dai_%s.tsv" % b), "w") as fh:
                fh.write("dai\tkhoang_toc_do\thuan_luyen\tkiem_tra\tkt_nen\tkt_tan_cong\tdu_mau\n")
                fh.write("\n".join(dai_lines) + "\n")
            with open(os.path.join(outdir, "scores_%s.tsv" % b), "w") as fh:
                fh.write("start_ns\tstop_ns\ttid\tnguon\tdiem\tnhan_tan_cong\tmuc\tsong_sinh\tdai\tdai_dung\ttoc_do\ttrong_tan_cong\tchieu_max\n")
                for w in scored:
                    fh.write("%d\t%d\t%s\t%s\t%.6f\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%s\n" % (
                        w.start, w.stop, w.tid, w.nguon, w.score, w.atk or "",
                        w.muc if w.muc is not None else "0", w.twin or "", w.band or "",
                        w.used, ("%.1f" % w.rate) if w.rate == w.rate else "", 1 if w.trong else 0,
                        dims_all[w.cmax] if w.cmax >= 0 else ""))
        tb = tradeoff(scored)
        if not tb:
            print("khong cham duoc")
            continue
        benign_all = [w for w in scored if w.atk is None]
        nen_kt = [w for w in benign_all if w.nguon == "nen" and w.twin is None
                  and (w.muc is None or w.muc == "0") and w.start >= cut and not w.trong]
        twins = [w for w in benign_all if w.twin is not None]
        trong = [w for w in benign_all if w.trong]
        if theo_tid and b != AGG_BRANCH:
            n_time = sum(1 for w in scored if w.atk is not None or w.trong)
            print("cua so tan cong theo tid=%d; theo thoi gian (cach 1.2) se la %d (trong do benign-tid-khac=%d)" % (
                len(scored) - len(benign_all), n_time, len(trong)))
        atk_by = dem_theo([w for w in scored if w.atk is not None], lambda w: w.atk)
        twin_by = dem_theo(twins, lambda w: w.twin)
        ctx = {"benign_all": benign_all, "nen_kt": nen_kt, "twins": twins, "trong": trong,
               "atk_by": atk_by, "twin_by": twin_by, "labels": labels, "che_do": che_do,
               "D": a.D, "D_ns": D_ns, "scored": scored}
        sink = {"theo_muc": [], "theo_dai": [], "id": [], "tre": []}
        sink_ns = {"theo_muc": [], "theo_dai": [], "id": [], "tre": []}
        # (A) diem danh doi theo MUC PHAT HIEN (nhu 1.2)
        print("muc_phat_hien\tnguong\tbao_dong_gia\tbdg_nen_kiem_tra(n=%d)\tbdg_song_sinh(n=%d)\tbdg_nen_trong_tan_cong(n=%d)" % (
            len(nen_kt), len(twins), len(trong)))
        for lv in DET_LEVELS:
            thr, far = thr_at_detection(tb, lv)
            far_nen = ti_le(nen_kt, thr)[0]
            far_tw = ti_le(twins, thr)[0]
            far_tr = ti_le(trong, thr)[0]
            print("%.2f\t%s\t%s\t%s\t%s\t%s" % (lv, f4(thr), f4(far), f4(far_nen), f4(far_tw), f4(far_tr)))
            summary.append((b, lv, thr, far, far_nen, far_tw, far_tr, len(benign_all), len(nen_kt), len(twins), len(trong)))
            if thr == thr:
                bao_cao_nguong("%.2f" % lv, thr, ctx, sink)
        # (B) diem danh doi theo NGAN SACH bao dong gia tren tap huan luyen (1.3.1)
        train_scored = [w for w in train if score(w, stats, dims_idx, order_cache, phan_tang, dung_khoa) == w.score and w.score == w.score]
        train_scores = sorted((w.score for w in train_scored), reverse=True)
        train_asc = train_scores[::-1]
        if train_scores:
            q99 = train_scores[max(0, int(0.01 * len(train_scores)) - 1)]
            top = dem_theo([w for w in train_scored if w.score >= q99], lambda w: dims_all[w.cmax] if w.cmax >= 0 else "-")
            print("chieu_max cua 1 %% diem huan luyen cao nhat (>= %s): %s" % (
                f4(q99), "  ".join("%s:%d" % (k, len(v)) for k, v in sorted(top.items(), key=lambda kv: -len(kv[1])))))
        print("ngan_sach\tnguong\tbdg_huan_luyen(n=%d)\tbdg_kiem_tra_benign\tbdg_nen_kiem_tra\tbdg_song_sinh\tbdg_nen_trong_tan_cong\tphat_hien" % len(train_scores))
        for bb in ngan_sach:
            thr = nguong_ngan_sach(train_scores, bb)
            if thr != thr:
                continue
            far_tr_in = (len(train_asc) - bisect.bisect_left(train_asc, thr)) / float(len(train_asc) or 1)
            far = ti_le(benign_all, thr)[0]
            far_nen = ti_le(nen_kt, thr)[0]
            far_tw = ti_le(twins, thr)[0]
            far_trg = ti_le(trong, thr)[0]
            atk_all = [w for w in scored if w.atk is not None]
            det = ti_le(atk_all, thr)[0]
            print("%g\t%s\t%s\t%s\t%s\t%s\t%s\t%s" % (bb, f4(thr), f4(far_tr_in), f4(far), f4(far_nen), f4(far_tw), f4(far_trg), f4(det)))
            summary_ns.append((b, bb, thr, far, far_tr_in, far_nen, far_tw, far_trg, det, len(train_scores), len(benign_all), len(nen_kt), len(atk_all)))
            vuot = dem_theo([w for w in benign_all if w.score >= thr], lambda w: dims_all[w.cmax] if w.cmax >= 0 else "-")
            print("  chieu_max cua cua so benign vuot nguong: " + "  ".join(
                "%s:%d" % (k, len(v)) for k, v in sorted(vuot.items(), key=lambda kv: -len(kv[1]))))
            bao_cao_nguong("%g" % bb, thr, ctx, sink_ns)
        # (C) duong tranh chap: nguong theo phan vi nen kiem tra, bdg theo muc
        mucs = sorted({w.muc if w.muc is not None else "0" for w in benign_all})
        if nen_kt:
            nen_desc = sorted((w.score for w in nen_kt), reverse=True)
            by_muc = dem_theo(benign_all, lambda w: w.muc if w.muc is not None else "0")
            print("duong tranh chap (bdg nen sach -> bdg theo muc): muc = %s" % ",".join(mucs))
            dtc = ["bdg_nen_dat\tnguong\tbdg_nen_thuc\t" + "\t".join("bdg_muc_%s" % m for m in mucs)]
            for q in LUOI_NEN:
                thr = nguong_ngan_sach(nen_desc, q)
                vals = [f4(ti_le(by_muc.get(m, []), thr)[0]) for m in mucs]
                dtc.append("%g\t%s\t%s\t%s" % (q, f4(thr), f4(ti_le(nen_kt, thr)[0]), "\t".join(vals)))
                print("  " + dtc[-1].replace("\t", "  "))
            if outdir:
                with open(os.path.join(outdir, "duong_tranh_chap_%s.tsv" % b), "w") as fh:
                    fh.write("\n".join(dtc) + "\n")
        theo_muc_lines, theo_dai_lines, id_lines, tre_lines = sink["theo_muc"], sink["theo_dai"], sink["id"], sink["tre"]
        if outdir:
            for name, head, lines in (("theo_muc_ns", "ngan_sach\tnguong\tmuc\tbao_dong_gia\tn_bao_dong\tn", sink_ns["theo_muc"]),
                                      ("theo_dai_ns", "ngan_sach\tnguong\tdai\tbao_dong_gia\tn_bao_dong\tn", sink_ns["theo_dai"]),
                                      ("phat_hien_id_ns", "ngan_sach\tnguong\tloai\tid\tty_le\tn_vuot\tn", sink_ns["id"]),
                                      ("do_tre_ns", "ngan_sach\tnguong\tid\tphat_hien_trong_D\tdo_tre_s", sink_ns["tre"])):
                if lines:
                    with open(os.path.join(outdir, "%s_%s.tsv" % (name, b)), "w") as fh:
                        fh.write(head + "\n" + "\n".join(lines) + "\n")
        if outdir:
            with open(os.path.join(outdir, "tradeoff_%s.tsv" % b), "w") as fh:
                fh.write("nguong\tbao_dong_gia\tty_le_phat_hien\tn_bdg\tn_bat\n")
                for thr, far, det, fa, d in tb:
                    fh.write("%s\t%s\t%s\t%d\t%d\n" % (f4(thr), f4(far), f4(det), fa, d))
            for name, head, lines in (("theo_muc", "muc_phat_hien\tnguong\tmuc\tbao_dong_gia\tn_bao_dong\tn", theo_muc_lines),
                                      ("theo_dai", "muc_phat_hien\tnguong\tdai\tbao_dong_gia\tn_bao_dong\tn", theo_dai_lines),
                                      ("phat_hien_id", "muc_phat_hien\tnguong\tloai\tid\tty_le\tn_vuot\tn", id_lines),
                                      ("do_tre", "muc_phat_hien\tnguong\tid\tphat_hien_trong_D\tdo_tre_s", tre_lines)):
                if lines:
                    with open(os.path.join(outdir, "%s_%s.tsv" % (name, b)), "w") as fh:
                        fh.write(head + "\n" + "\n".join(lines) + "\n")
    if outdir and summary:
        with open(os.path.join(outdir, "tom_tat.tsv"), "w") as fh:
            fh.write("branch\tmuc_phat_hien\tnguong\tbao_dong_gia\tbdg_nen_kiem_tra\tbdg_song_sinh\tbdg_nen_trong_tan_cong\tn_benign\tn_nen_kiem_tra\tn_song_sinh\tn_nen_trong_tan_cong\n")
            for b, lv, thr, far, fn, ft, ftr, nb_, nn, nt, ntr in summary:
                fh.write("%s\t%.2f\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\n" % (b, lv, f4(thr), f4(far), f4(fn), f4(ft), f4(ftr), nb_, nn, nt, ntr))
        if summary_ns:
            with open(os.path.join(outdir, "tom_tat_ngan_sach.tsv"), "w") as fh:
                fh.write("branch\tngan_sach\tnguong\tbao_dong_gia\tbdg_huan_luyen\tbdg_nen_kiem_tra\tbdg_song_sinh\tbdg_nen_trong_tan_cong\tphat_hien\tn_huan_luyen\tn_benign\tn_nen_kiem_tra\tn_tan_cong\n")
                for r in summary_ns:
                    fh.write("%s\t%g\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\n" % (
                        r[0], r[1], f4(r[2]), f4(r[3]), f4(r[4]), f4(r[5]), f4(r[6]), f4(r[7]), f4(r[8]), r[9], r[10], r[11], r[12]))
        with open(os.path.join(outdir, "tham_so.txt"), "w") as fh:
            fh.write("c5_score %s\n%s\ncat_huan_luyen=%d\ndai_che_do=%s\nphan_tang=%s\n" % (VERSION, " ".join(argv), cut, che_do, phan_tang))
    print("\n(Doc: tai cung muc phat hien, so bao_dong_gia giua cac nhanh; bang 'theo muc' la truc hoanh hinh C5; "
          "'bdg_nen_kiem_tra' la bao dong gia tren nen sach ngay 6-7; 'theo dai' phai can bang giua ngay/dem; "
          "bang 'ngan_sach' va 'duong tranh chap' la diem danh doi khong can nhan tan cong.)")


if __name__ == "__main__":
    main(sys.argv)

# === NHAT KY ===
# 1.0  26/10/2026  ban dau; toan hoc = detector_c5.py 1.1; cot ctx_* khong cham; them nhanh AGG_cgroup_giay (chot truoc du lieu).
# 1.1  26/10/2026  cot `nguon` + quy tac cat theo nguon (phien co nhan luon la kiem tra); AGG theo dinh nghia M6g. Toan hoc cham diem khong doi.
# 1.2  26/10/2026  --out ghi them scores_<branch>.tsv (diem tung cua so) de ap nguong chon tren lab len du lieu khac. Toan hoc khong doi.
# 1.3  07/11/2026  Sau R039 (du lieu that): (1) chuan hoa PHAN TANG theo dai tai
#      (toc do ban ghi tong, he so 2; hoac muc generator tu nhip-benign.tsv);
#      ly do: bao dong gia nen 0,88-0,97 moi nhanh vi nen da nhip ngay/dem ma
#      median/MAD hoc tinh (xem dau file). (2) quy tac cat: cua so giao nhan
#      (A/B/C/N) hoac muc != 0 luon la kiem tra, bat ke ngay/nguon; ly do:
#      B1-60s/B1-300s nam tren nen ngay 1-5 nen R039 co 0 cua so kiem tra.
#      (3) --nhan-tid: cua so tan cong = cua so cua chinh tid tan cong (1.2
#      tinh moi tid giao khoang nhan -> nguong det 0,90 bi ep ve ~0; xem dau
#      file). (4) tradeoff tinh bang bisect (cung ket qua, nhanh hon). (5) bao cao them:
#      bdg nen kiem tra, bdg song sinh, theo dai, theo id, dot trong D=300 s,
#      do tre; cot moi chi NOI THEM cuoi scores_/tom_tat. Toan cham diem,
#      dinh nghia cua so tan cong (giao bat ky), muc phat hien: KHONG doi.
#      --dai-che-do khong = hanh vi 1.2 (de hoi quy).
# 1.3.1 07/11/2026  R040 ban dung: LAB-1 khong ghi tien trinh tan cong (chay ngoai
#      cgroup loc) -> them diem danh doi theo NGAN SACH bao dong gia (nguong =
#      phan vi tap huan luyen; --ngan-sach) va duong tranh chap (bdg nen sach ->
#      bdg theo muc) de doc nua "on dinh duoi tranh chap" cua C5 ma khong can
#      nhan; khong thay the diem theo muc phat hien. Toan hoc khong doi; cac
#      file cu giu nguyen dinh dang, file moi *_ns_*.tsv, tom_tat_ngan_sach.tsv,
#      duong_tranh_chap_*.tsv.
# 1.4.1 08/11/2026  Sua loi R042: trong mien log, chieu co MAD=0 bi chia EPS=1e-9
#      -> z ~ 1e12-1e13 -> nguong ngan sach vo nghia, phat_hien=0. Sua: chieu
#      MAD=0 bi BO khoi cham (bo_mad0, mac dinh BAT khi mien log; --giu-mad0 de
#      giu nhu cu). Che do tuong thich (--mien-tuyen-tinh) GIU EPS -> hoi quy
#      1.3.2 van giong het tung byte. Toan cham diem khac khong doi.
# 1.4   08/11/2026  C5 v2 theo tien dang ky v1.1: R1 n>=30 (cot n that), R2 mien
#      log ln(x+1us) cho dai luong ns, R3 ho so theo (cgroup,k) + tid rieng
#      (>=200 cua so), R5 bo chieu PHANRA chon duoc {A,B,C,D,E} mac dinh D
#      (arr+inst+own_cv). Toan cham diem khong doi. Che do tuong thich
#      (--chieu-phanra A --ho-so tat --mien-tuyen-tinh --n-toi-thieu 0
#      --dai-che-do khong) cho ket qua GIONG HET 1.3.2 (kiem hoi quy tung byte).
#      R4 nen truot: khai bao --nen-truot-gio, chua cai, lam o M6i-c2.
# 1.3.2 07/11/2026  Chan doan sau R040 (nguong 1e5..4e7 = chieu MAD 0): cot
#      chieu_max trong scores_*, file chuan_<branch>.tsv (dai x chieu: n, median,
#      MAD, mad0), phan bo chieu_max; khong-mode van gan dai de bao cao; cot x_*
#      (ung vien cua c5_extract v2) khong cham. Diem, tradeoff, tom_tat khong doi.
