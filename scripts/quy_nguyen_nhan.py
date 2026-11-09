#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Quy nguyen nhan bao dong (buoc1 / R052).

Chi DOC + TINH tren features/nhan da co. Khong sua c5_score / detector.

Detector bao dong: Hotelling T2 bo chieu D, ngan sach 1% (khop t2fair-v15-D).
Quy tac gan MOI_TRUONG | HANH_VI: thong ke CO DINH (khong hoc) — xem hang so
va ham classify() ben duoi; tieu chi dat/truot nam trong R052 muc dau.
"""
from __future__ import print_function

import argparse
import csv
import math
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis"))

import c5_score as cs  # noqa: E402

# --- hang so CO DINH (khong hoc) ---
NGAN_SACH = 0.01
TRAIN_UNTIL = 1006289550843307
BRANCH = "PHANRA_5tp"
CHIEU = "D"
Z_VUOT = 3.0          # |z| >= nay: vuot nguong dong-pha
CPI_PHANG = 2.0       # |z_cpi| < nay: cpi phang
MIN_NEN_TID = 8       # toi thieu cua so nen de dung nen rieng tid
MIN_NEN_LOP = 20
EPS_MAD = 1e-12

# thanh phan phan du (ten logic -> cot features THO, khong log)
COMP_COLS = {
    "rq": "ctx_rq_med",
    "steal": "ctx_steal_med",
    "irq": "ctx_irq_med",
    "cpu": "cpu_med",
    "vol": "x_vol_med",
    "x_arr": "x_arr_med",
    "x_inst": "x_inst_med",
    "cpi": "cpi_med",
}
ENV_COMPS = frozenset(("rq", "steal", "irq", "cpi"))
BEH_COMPS = frozenset(("vol", "x_arr", "x_inst"))


def median(xs):
    s = sorted(x for x in xs if x == x)
    n = len(s)
    if n == 0:
        return float("nan")
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def mad(xs, m):
    if m != m:
        return float("nan")
    return median([abs(x - m) for x in xs if x == x])


def z_score(v, med, mad_v):
    if v != v or med != med:
        return float("nan")
    scale = mad_v if mad_v == mad_v and mad_v > EPS_MAD else EPS_MAD
    return (v - med) / scale


def parse_id_from_tag(tag):
    """Tag dang B4@D3-7#... hoac B4@D3-7 -> B4."""
    if not tag:
        return None
    return tag.split("@", 1)[0]


def load_raw_index(path):
    """Chi so gia tri THO theo (tid, start_ns) cho PHANRA; kem cg, k, n, nguon."""
    idx = {}  # (tid_str, start) -> dict
    by_tid = defaultdict(list)
    with open(path, encoding="utf-8", errors="replace") as fh:
        r = csv.DictReader(fh, delimiter="\t")
        for row in r:
            if row.get("branch") != BRANCH:
                continue
            try:
                n = int(float(row["n"]))
            except (ValueError, KeyError):
                continue
            if n < 30:
                continue
            tid = row["tid"]
            start = int(row["start_ns"])
            stop = int(row["stop_ns"])
            vals = {}
            ok = True
            for logical, col in COMP_COLS.items():
                try:
                    vals[logical] = float(row[col])
                except (ValueError, KeyError):
                    vals[logical] = float("nan")
                    ok = False
            try:
                k = int(math.floor(math.log(n / 300.0) / math.log(2))) if n > 0 else None
            except ValueError:
                k = None
            rec = {
                "tid": tid,
                "start": start,
                "stop": stop,
                "cg": row.get("cgroup_id", ""),
                "k": k,
                "n": n,
                "nguon": row.get("nguon", ""),
                "vals": vals,
                "ok": ok,
            }
            idx[(tid, start)] = rec
            by_tid[tid].append(rec)
    for tid in by_tid:
        by_tid[tid].sort(key=lambda x: x["start"])
    return idx, by_tid


def build_baselines(raw_by_tid, muc_intervals):
    """Nen rieng tid va nen lop (cg,k) tu cua so nguon=nen giao muc 0."""
    # muc 0 intervals
    muc0 = [(lo, hi) for lo, hi, m in muc_intervals if m == "0"]

    def in_muc0(start, stop):
        if not muc0:
            # neu khong co muc file: moi cua so nen deu la nen
            return True
        for lo, hi in muc0:
            if max(start, lo) < min(stop, hi):
                return True
        # cua so nen khong giao khoang D* van coi la muc 0 neu khong giao D1/D3
        for lo, hi, m in muc_intervals:
            if m != "0" and max(start, lo) < min(stop, hi):
                return False
        return True

    tid_base = {}  # tid -> {comp: (med, mad, n)}
    lop_vals = defaultdict(lambda: defaultdict(list))  # (cg,k) -> comp -> [v]

    for tid, recs in raw_by_tid.items():
        bucket = defaultdict(list)
        for rec in recs:
            if rec["nguon"] != "nen":
                continue
            if not in_muc0(rec["start"], rec["stop"]):
                continue
            for c, v in rec["vals"].items():
                if v == v:
                    bucket[c].append(v)
                    if rec["cg"] is not None and rec["k"] is not None:
                        lop_vals[(rec["cg"], rec["k"])][c].append(v)
        if bucket and min(len(bucket[c]) for c in COMP_COLS) >= 1:
            stats = {}
            for c in COMP_COLS:
                xs = bucket.get(c, [])
                m = median(xs)
                stats[c] = (m, mad(xs, m), len(xs))
            tid_base[tid] = stats

    lop_base = {}
    for key, comps in lop_vals.items():
        stats = {}
        for c in COMP_COLS:
            xs = comps.get(c, [])
            m = median(xs)
            stats[c] = (m, mad(xs, m), len(xs))
        lop_base[key] = stats
    return tid_base, lop_base


def residual_vector(rec, tid_base, lop_base):
    """Tra ve (z_dict, nguon_nen, uu_the) hoac None."""
    tid = rec["tid"]
    stats = None
    src = None
    tb = tid_base.get(tid)
    if tb and min(tb[c][2] for c in COMP_COLS) >= MIN_NEN_TID:
        stats, src = tb, "tid"
    else:
        key = (rec["cg"], rec["k"])
        lb = lop_base.get(key)
        if lb and min(lb[c][2] for c in COMP_COLS) >= MIN_NEN_LOP:
            stats, src = lb, "lop(%s,k=%s)" % (rec["cg"], rec["k"])
        elif tb:
            stats, src = tb, "tid_it_mau"
        elif lb:
            stats, src = lb, "lop_it_mau"
        else:
            return None
    z = {}
    for c in COMP_COLS:
        med, md, _n = stats[c]
        z[c] = z_score(rec["vals"][c], med, md)
    # uu the: |z| max, bo qua nan
    best, best_abs = None, -1.0
    for c, zv in z.items():
        if zv != zv:
            continue
        a = abs(zv)
        if a > best_abs:
            best_abs, best = a, c
    return z, src, best, best_abs


def step2_candidate(uu_the, z):
    """Ung vien tu thanh phan uu the (truoc dong-pha)."""
    zcpi = z.get("cpi", float("nan"))
    if uu_the in ENV_COMPS:
        return "MOI_TRUONG", "uu_the=%s" % uu_the
    if uu_the == "cpu":
        if zcpi == zcpi and zcpi > 0:
            return "MOI_TRUONG", "uu_the=cpu & z_cpi>0"
        return "HANH_VI", "uu_the=cpu & z_cpi<=0"
    if uu_the in BEH_COMPS:
        if zcpi != zcpi or abs(zcpi) < CPI_PHANG:
            return "HANH_VI", "uu_the=%s & cpi_phang" % uu_the
        return "MOI_TRUONG", "uu_the=%s & cpi_khong_phang(|z_cpi|=%.2f)" % (uu_the, abs(zcpi))
    return "MOI_TRUONG", "uu_the=%s (mac_dinh)" % uu_the


def active_peers(rec, raw_idx, by_start_overlap, scope="cgroup"):
    """Cac tid KHAC co cua so giao [start,stop], cung cgroup (hoac toan VM)."""
    peers = []
    # quet theo chi so thoi gian tho: dung danh sach da index theo start buckets
    for other in by_start_overlap.query(rec["start"], rec["stop"]):
        if other["tid"] == rec["tid"]:
            continue
        if scope == "cgroup" and other["cg"] != rec["cg"]:
            continue
        peers.append(other)
    return peers


class OverlapIndex(object):
    """Chi so cua so theo start (chia bucket 30s) de tim giao nhanh."""

    def __init__(self, recs):
        self.bucket = defaultdict(list)
        self.step = 30 * 10 ** 9
        for rec in recs:
            b = rec["start"] // self.step
            self.bucket[b].append(rec)

    def query(self, start, stop):
        out = []
        b0 = start // self.step - 12  # 300s window / 30s + margin
        b1 = stop // self.step + 1
        seen = set()
        for b in range(b0, b1 + 1):
            for rec in self.bucket.get(b, ()):
                key = (rec["tid"], rec["start"])
                if key in seen:
                    continue
                if max(start, rec["start"]) < min(stop, rec["stop"]):
                    seen.add(key)
                    out.append(rec)
        return out


def dong_pha(rec, z, uu_the, tid_base, lop_base, overlap_idx):
    """Kiem dong pha quan the. Tra ve (nhan_ghi_de_hoac_None, info_dict)."""
    if uu_the is None or z.get(uu_the) != z.get(uu_the):
        return None, {"n_active": 0, "n_dong_pha": 0, "scope": "cgroup",
                      "note": "khong_uu_the", "can_du_lieu": True}

    z_u = z[uu_the]
    sign = 1.0 if z_u >= 0 else -1.0

    peers = active_peers(rec, None, overlap_idx, scope="cgroup")
    scope = "cgroup"
    # neu cgroup chi co W: thu VM
    if len(peers) == 0:
        peers = active_peers(rec, None, overlap_idx, scope="vm")
        scope = "vm"

    n_active = len(peers) + 1  # gom chinh W
    n_dong = 0
    for p in peers:
        rz = residual_vector(p, tid_base, lop_base)
        if rz is None:
            continue
        pz = rz[0].get(uu_the, float("nan"))
        if pz != pz:
            continue
        if abs(pz) >= Z_VUOT and (1.0 if pz >= 0 else -1.0) == sign:
            n_dong += 1

    info = {
        "n_active": n_active,
        "n_peers": len(peers),
        "n_dong_pha": n_dong,
        "scope": scope,
        "can_du_lieu": len(peers) == 0,
        "note": "",
    }
    if len(peers) == 0:
        info["note"] = "khong_peer_giao_cua_so; coi 1 tid dich chuyen"
        # chi mot tid -> HANH_VI theo dinh nghia buoc 3
        return "HANH_VI", info

    # >= nua so tid hoat dong cung dich chuyen (tinh ca W: n_dong+1)
    if (n_dong + 1) >= math.ceil(n_active / 2.0):
        return "MOI_TRUONG", info
    # chi W (va < nua) -> HANH_VI
    return "HANH_VI", info


def classify(rec, tid_base, lop_base, overlap_idx):
    rv = residual_vector(rec, tid_base, lop_base)
    if rv is None:
        return {
            "nhan": "KHONG_GAN",
            "ly_do": "thieu_nen",
            "uu_the": "",
            "z_uu": float("nan"),
            "nen_src": "",
            "cand": "",
            "n_active": 0,
            "n_dong_pha": 0,
            "scope": "",
            "can_du_lieu": True,
            "z": {},
        }
    z, src, uu, zabs = rv
    cand, cand_why = step2_candidate(uu, z)
    override, info = dong_pha(rec, z, uu, tid_base, lop_base, overlap_idx)

    # Buoc 3: neu dong-pha noi MOI_TRUONG thi ghi de HANH_VI; neu noi HANH_VI
    # va cand la HANH_VI giu nguyen; neu cand MOI_TRUONG va dong-pha HANH_VI
    # (chi 1 tid) — van MOI_TRUONG neu thanh phan moi truong? Nhiem vu:
    # "ghi de buoc 2 neu buoc 2 noi hanh vi" khi dong pha moi truong.
    # "Chi MOT tid dich chuyen -> HANH_VI" — ghi de ca khi buoc 2 noi moi truong
    # (B4 cpu/contention-looking nhung chi 1 tid).
    if override == "MOI_TRUONG" and cand == "HANH_VI":
        nhan = "MOI_TRUONG"
        ly_do = "dong_pha_ghi_de(%s); %s; n_dong=%d/%d %s" % (
            cand_why, info.get("note", ""), info["n_dong_pha"], info["n_active"], info["scope"])
    elif override == "HANH_VI":
        nhan = "HANH_VI"
        ly_do = "dong_pha_1_tid_hoac_<nua(%s); %s; n_dong=%d/%d %s" % (
            cand_why, info.get("note", ""), info["n_dong_pha"], info["n_active"], info["scope"])
    else:
        nhan = cand
        ly_do = "%s; dong_pha_giu; n_dong=%d/%d %s" % (
            cand_why, info["n_dong_pha"], info["n_active"], info["scope"])

    return {
        "nhan": nhan,
        "ly_do": ly_do,
        "uu_the": uu or "",
        "z_uu": z.get(uu, float("nan")) if uu else float("nan"),
        "nen_src": src,
        "cand": cand,
        "n_active": info["n_active"],
        "n_dong_pha": info["n_dong_pha"],
        "scope": info["scope"],
        "can_du_lieu": info["can_du_lieu"],
        "z": z,
    }


def compute_t2_alarms(features, nhan, nhan_tid, muc, train_until, ngan_sach):
    """Chay logic T2 nhu c5_score --t2 (bo D), tra ve (thr, list Row bao dong PHANRA)."""
    rows, dims_all = cs.read_features(features, mien_log=True)
    keep = []
    for w in rows:
        if w.branch != cs.AGG_BRANCH and w.nrec is not None and w.nrec < 30:
            continue
        keep.append(w)
    rows = keep
    labels = cs.read_nhan(nhan)
    tid_labels = cs.read_nhan_tid(nhan_tid, labels)
    theo_tid = bool(tid_labels)
    muc_list = cs.read_muc(muc)
    for w in rows:
        if labels:
            cs.gan_nhan(w, labels, tid_labels, theo_tid)
            w.muc_nhan = cs.muc_tu_nhan(w, labels, tid_labels, theo_tid)
        if muc_list:
            cs.gan_muc(w, muc_list)

    phanra_set = cs.CHIEU_PHANRA[CHIEU]
    cut = train_until
    rb = [w for w in rows if w.branch == BRANCH]
    dims_idx = [i for i, d in enumerate(dims_all) if d in phanra_set
                and any(w.f[i] == w.f[i] for w in rb)]
    train = [w for w in rb if w.nguon == "nen" and w.stop <= cut and w.atk is None
             and w.twin is None and (w.muc_nhan in (None, "", "0"))]
    fit = cs.fit_cov(train, dims_idx)
    if not fit:
        sys.exit("T2: khong fit duoc hiep phuong sai (n_train=%d)" % len(train))
    med, Sinv = fit

    def lvl(w):
        mm = w.muc_nhan if w.muc_nhan not in (None, "") else (w.muc if w.muc is not None else "0")
        return mm if mm not in (None, "") else "0"

    for w in rb:
        w._st = cs.t2_score(w, dims_idx, med, Sinv)
    train_sc = sorted((w._st for w in train if w._st == w._st), reverse=True)
    k = max(0, min(len(train_sc) - 1, int(ngan_sach * len(train_sc))))
    thr = train_sc[k]
    alarms = [w for w in rb if w._st == w._st and w._st >= thr]
    meta = {
        "thr": thr,
        "n_train": len(train),
        "n_alarm": len(alarms),
        "dims": [dims_all[i] for i in dims_idx],
    }
    return thr, alarms, meta, muc_list


def set_of(w):
    """Gan cua so bao dong vao tap A/B/C/D (co the nhieu tap)."""
    tags = []
    muc = w.muc_nhan if w.muc_nhan not in (None, "") else (w.muc if w.muc else "0")
    ident = parse_id_from_tag(w.atk) if w.atk else None
    twin_id = parse_id_from_tag(w.twin) if w.twin else None

    # A: twin N1 duoi D3-7 hoac D1-16
    if twin_id == "N1" and muc in ("D3-7", "D1-16"):
        tags.append("A")
    # B: nen (nguon=nen) duoi D1/D3
    if w.nguon == "nen" and muc in ("D1-8", "D1-16", "D3-7"):
        tags.append("B")
    # C: B4 duoi D3-7
    if ident == "B4" and muc == "D3-7":
        tags.append("C")
    # D: B1 bat ky muc
    if ident == "B1":
        tags.append("D")
    return tags, muc, ident, twin_id


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", default=os.path.join(ROOT, "out/c5-lab1c/features_ghep.tsv"))
    ap.add_argument("--nhan", default=os.path.join(ROOT, "lab/nhan-tan-cong-lab1c.tsv"))
    ap.add_argument("--nhan-tid", default=os.path.join(ROOT, "lab/nhan-tid-lab1c.tsv"))
    ap.add_argument("--muc", default=os.path.join(ROOT, "lab/muc-lab1c.tsv"))
    ap.add_argument("--train-until", type=int, default=TRAIN_UNTIL)
    ap.add_argument("--ngan-sach", type=float, default=NGAN_SACH)
    ap.add_argument("--out", default=os.path.join(ROOT, "out/c5-lab1c/quy-nguyen-nhan"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    print("# quy_nguyen_nhan: T2 bo D ngan_sach=%g train_until=%d" % (a.ngan_sach, a.train_until))
    thr, alarms, meta, muc_list = compute_t2_alarms(
        a.features, a.nhan, a.nhan_tid, a.muc, a.train_until, a.ngan_sach)
    print("# T2 thr@%.3g = %.6g | n_train=%d n_alarm=%d dims=%s" % (
        a.ngan_sach, thr, meta["n_train"], meta["n_alarm"], "+".join(meta["dims"])))

    print("# load raw features index...")
    raw_idx, raw_by_tid = load_raw_index(a.features)
    tid_base, lop_base = build_baselines(raw_by_tid, muc_list)
    print("# nen_tid=%d nen_lop=%d raw_windows=%d" % (len(tid_base), len(lop_base), len(raw_idx)))

    overlap_idx = OverlapIndex([r for recs in raw_by_tid.values() for r in recs])

    # gan nhan
    rows_out = []
    by_set = defaultdict(list)
    n_can_du_lieu = 0
    for w in alarms:
        tags, muc, ident, twin_id = set_of(w)
        key = (str(w.tid), w.start)
        rec = raw_idx.get(key)
        if rec is None:
            # thu tid int/str
            rec = raw_idx.get((str(int(w.tid)), w.start))
        if rec is None:
            cls = {
                "nhan": "KHONG_GAN", "ly_do": "thieu_raw", "uu_the": "", "z_uu": float("nan"),
                "nen_src": "", "cand": "", "n_active": 0, "n_dong_pha": 0, "scope": "",
                "can_du_lieu": True, "z": {},
            }
        else:
            cls = classify(rec, tid_base, lop_base, overlap_idx)
        if cls["can_du_lieu"]:
            n_can_du_lieu += 1
        row = {
            "start_ns": w.start,
            "stop_ns": w.stop,
            "tid": w.tid,
            "nguon": w.nguon,
            "t2": w._st,
            "muc": muc,
            "atk": w.atk or "",
            "twin": w.twin or "",
            "ident": ident or "",
            "twin_id": twin_id or "",
            "sets": ",".join(tags) if tags else "",
            "nhan": cls["nhan"],
            "cand": cls["cand"],
            "uu_the": cls["uu_the"],
            "z_uu": cls["z_uu"],
            "nen_src": cls["nen_src"],
            "n_active": cls["n_active"],
            "n_dong_pha": cls["n_dong_pha"],
            "scope": cls["scope"],
            "can_du_lieu": int(bool(cls["can_du_lieu"])),
            "ly_do": cls["ly_do"],
        }
        for c in COMP_COLS:
            row["z_%s" % c] = cls["z"].get(c, float("nan"))
        rows_out.append(row)
        for t in tags:
            by_set[t].append(row)

    # ghi chi tiet
    detail = os.path.join(a.out, "chi_tiet.tsv")
    cols = ["sets", "nhan", "cand", "uu_the", "z_uu", "n_active", "n_dong_pha", "scope",
            "can_du_lieu", "muc", "ident", "twin_id", "tid", "start_ns", "stop_ns",
            "t2", "nguon", "nen_src", "atk", "twin", "ly_do"] + ["z_%s" % c for c in COMP_COLS]
    with open(detail, "w") as fh:
        fh.write("\t".join(cols) + "\n")
        for row in sorted(rows_out, key=lambda r: (r["sets"], r["start_ns"], str(r["tid"]))):
            fh.write("\t".join("nan" if (isinstance(row.get(c), float) and row.get(c) != row.get(c))
                               else str(row.get(c, "")) for c in cols) + "\n")

    # bang tong hop
    summary = os.path.join(a.out, "tong_hop.tsv")
    with open(summary, "w") as fh:
        fh.write("tap\tn_bao_dong\tn_MOI_TRUONG\tn_HANH_VI\tn_KHONG_GAN\tpct_MOI_TRUONG\tpct_HANH_VI\tuu_the_top\tn_can_du_lieu_dong_pha\n")
        lines_print = []
        for tap in ("A", "B", "C", "D"):
            ws = by_set.get(tap, [])
            n = len(ws)
            n_m = sum(1 for r in ws if r["nhan"] == "MOI_TRUONG")
            n_h = sum(1 for r in ws if r["nhan"] == "HANH_VI")
            n_k = sum(1 for r in ws if r["nhan"] == "KHONG_GAN")
            n_cd = sum(1 for r in ws if r["can_du_lieu"])
            pct_m = (100.0 * n_m / n) if n else float("nan")
            pct_h = (100.0 * n_h / n) if n else float("nan")
            top = Counter(r["uu_the"] for r in ws if r["uu_the"]).most_common(5)
            top_s = ",".join("%s:%d" % (k, v) for k, v in top)
            fh.write("%s\t%d\t%d\t%d\t%d\t%.2f\t%.2f\t%s\t%d\n" % (
                tap, n, n_m, n_h, n_k, pct_m, pct_h, top_s, n_cd))
            lines_print.append((tap, n, n_m, n_h, n_k, pct_m, pct_h, top_s, n_cd))

    # tieu chi (a)+(b)
    # (a) twin/nen = A hop B
    env_pool = by_set.get("A", []) + by_set.get("B", [])
    # tranh dem 2 lan neu cua so vua A vua B (hiếm)
    seen = set()
    env_uniq = []
    for r in env_pool:
        k = (r["tid"], r["start_ns"])
        if k in seen:
            continue
        seen.add(k)
        env_uniq.append(r)
    n_env = len(env_uniq)
    n_env_m = sum(1 for r in env_uniq if r["nhan"] == "MOI_TRUONG")
    pct_a = (100.0 * n_env_m / n_env) if n_env else float("nan")

    b4 = by_set.get("C", [])
    n_b4 = len(b4)
    n_b4_h = sum(1 for r in b4 if r["nhan"] == "HANH_VI")
    pct_b = (100.0 * n_b4_h / n_b4) if n_b4 else float("nan")

    dat_a = (n_env > 0 and pct_a >= 80.0)
    dat_b = (n_b4 > 0 and pct_b >= 80.0)
    ket = "DAT" if (dat_a and dat_b) else "TRUOT"

    with open(os.path.join(a.out, "ket_luan.tsv"), "w") as fh:
        fh.write("metric\tvalue\n")
        fh.write("t2_thr\t%.10g\n" % thr)
        fh.write("n_alarm_all\t%d\n" % len(alarms))
        fh.write("n_env_AB\t%d\n" % n_env)
        fh.write("n_env_MOI_TRUONG\t%d\n" % n_env_m)
        fh.write("pct_env_MOI_TRUONG\t%.4f\n" % pct_a)
        fh.write("dat_a_ge80\t%d\n" % int(dat_a))
        fh.write("n_B4\t%d\n" % n_b4)
        fh.write("n_B4_HANH_VI\t%d\n" % n_b4_h)
        fh.write("pct_B4_HANH_VI\t%.4f\n" % pct_b)
        fh.write("dat_b_ge80\t%d\n" % int(dat_b))
        fh.write("ket_luan\t%s\n" % ket)
        fh.write("n_alarm_can_du_lieu_dong_pha\t%d\n" % n_can_du_lieu)

    print("# tong hop:")
    for t in lines_print:
        print("  %s n=%d MOI=%d HANH=%d KHONG=%d pct_MOI=%.2f pct_HANH=%.2f uu=[%s] can_dl=%d" % t)
    print("# (a) twin+nen: %d/%d = %.2f%% MOI_TRUONG -> %s" % (
        n_env_m, n_env, pct_a, "OK" if dat_a else "FAIL"))
    print("# (b) B4: %d/%d = %.2f%% HANH_VI -> %s" % (
        n_b4_h, n_b4, pct_b, "OK" if dat_b else "FAIL"))
    print("# KET_LUAN %s" % ket)
    print("# out %s" % a.out)


if __name__ == "__main__":
    main()
