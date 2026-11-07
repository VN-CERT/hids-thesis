#!/usr/bin/env python3
"""Ap nguong lab len diem production (ngay 6-7).

Cu: --tom-tat FILE --prod-score DIR  (muc 0.90/0.95/1.00, cot muc_phat_hien).
Moi: <thu_muc_score_lab> <thu_muc_score_prod> [ten_file_tom_tat=tom_tat.tsv] [cot_muc=muc_phat_hien]
In ca nguong lab va nguong tu hoc trong thu muc production (cung ten file, cung cot).
"""
from __future__ import annotations

import argparse
import os
from collections import defaultdict


LEVELS_CU = (0.90, 0.95, 1.00)


def read_thresholds(path, cot, levels):
    out = {}
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        if cot not in idx or "branch" not in idx or "nguong" not in idx:
            raise SystemExit("thieu cot trong %s: %s" % (path, header))
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) <= max(idx[cot], idx["nguong"], idx["branch"]):
                continue
            b = p[idx["branch"]]
            try:
                lv = float(p[idx[cot]])
            except ValueError:
                continue
            if levels is not None and not any(abs(lv - x) < 1e-12 for x in levels):
                continue
            thr = p[idx["nguong"]]
            out[(b, lv)] = float("nan") if thr == "nan" else float(thr)
    return out


def read_scores(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            try:
                diem = float(p[idx["diem"]])
            except (ValueError, KeyError, IndexError):
                continue
            dai = p[idx["dai"]] if "dai" in idx and idx["dai"] < len(p) else ""
            rows.append((int(p[idx["start_ns"]]), p[idx["tid"]], diem, dai))
    return rows


def theo_dai(rows, alarm):
    if not rows or rows[0][3] == "" and all(d == "" for *_, d in rows):
        return ""
    n = defaultdict(int)
    h = defaultdict(int)
    for s, tid, diem, dai in rows:
        n[dai or "-"] += 1
    for s, tid, diem, dai in alarm:
        h[dai or "-"] += 1
    parts = []
    for k in sorted(n):
        parts.append("%s:%.4f(%d)" % (k, h[k] / n[k] if n[k] else float("nan"), n[k]))
    return " ".join(parts)


def in_bang(thr, rows_by_b, days, cot_ten, nguon):
    print("branch\t%s\tnguon_nguong\tnguong\tn_cua_so\tn_bao_dong\tty_le\t"
          "bao_dong_moi_host_ngay\ttid_ngay_bao\ttid_ngay_quan_sat\tty_le_tid_ngay\ttheo_dai" % cot_ten)
    branches = sorted({b for b, _ in thr})
    levels = sorted({lv for _, lv in thr})
    for b in branches:
        rows = rows_by_b.get(b)
        if rows is None:
            print("%s\tNA\tkhong co scores" % b)
            continue
        for lv in levels:
            if (b, lv) not in thr:
                continue
            t = thr[(b, lv)]
            if t != t:
                print("%s\t%g\tnan\tnan\t%d\t0\tnan\tnan\t0\t0\tnan\t" % (b, lv, len(rows)))
                continue
            alarm = [r for r in rows if r[2] >= t]
            n = len(rows) or 1
            na = len(alarm)
            obs = {(tid, s // 86_400_000_000_000) for s, tid, _, _ in rows}
            hit = {(tid, s // 86_400_000_000_000) for s, tid, _, _ in alarm}
            print("%s\t%g\t%s\t%.6g\t%d\t%d\t%.6f\t%.4f\t%d\t%d\t%.6f\t%s" % (
                b, lv, nguon, t, len(rows), na, na / n, na / days,
                len(hit), len(obs), (len(hit) / len(obs) if obs else float("nan")),
                theo_dai(rows, alarm)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lab_dir", nargs="?")
    ap.add_argument("prod_dir", nargs="?")
    ap.add_argument("tom_tat_ten", nargs="?", default="tom_tat.tsv")
    ap.add_argument("cot_muc", nargs="?", default="muc_phat_hien")
    ap.add_argument("--tom-tat", default=None)
    ap.add_argument("--prod-score", default=None)
    ap.add_argument("--days", type=int, default=2)
    a = ap.parse_args()

    if a.tom_tat and a.prod_score and not a.lab_dir:
        thr = read_thresholds(a.tom_tat, "muc_phat_hien", LEVELS_CU)
        rows_by_b = {}
        for b, _ in thr:
            path = os.path.join(a.prod_score, "scores_%s.tsv" % b)
            if os.path.isfile(path):
                rows_by_b[b] = read_scores(path)
        # in dung cot cu, them theo_dai neu co
        print("branch\tmuc_phat_hien\tnguong_lab\tn_cua_so\tn_bao_dong\tty_le\t"
              "bao_dong_moi_host_ngay\ttid_ngay_bao\ttid_ngay_quan_sat\tty_le_tid_ngay")
        branches = sorted({b for b, _ in thr})
        for b in branches:
            rows = rows_by_b.get(b, [])
            if b not in rows_by_b:
                print("%s\tNA\tkhong co scores_%s.tsv" % (b, b))
                continue
            for lv in LEVELS_CU:
                t = thr.get((b, lv), float("nan"))
                if t != t:
                    print("%s\t%.2f\tnan\t%d\t0\tnan\tnan\t0\t0\tnan" % (b, lv, len(rows)))
                    continue
                alarm = [r for r in rows if r[2] >= t]
                n = len(rows) or 1
                na = len(alarm)
                obs = {(tid, s // 86_400_000_000_000) for s, tid, _, _ in rows}
                hit = {(tid, s // 86_400_000_000_000) for s, tid, _, _ in alarm}
                print("%s\t%.2f\t%.4f\t%d\t%d\t%.6f\t%.4f\t%d\t%d\t%.6f" % (
                    b, lv, t, len(rows), na, na / n, na / a.days,
                    len(hit), len(obs), (len(hit) / len(obs) if obs else float("nan"))))
        return

    if not a.lab_dir or not a.prod_dir:
        raise SystemExit("can --tom-tat va --prod-score, hoac hai thu muc score")
    levels = None if a.cot_muc != "muc_phat_hien" else LEVELS_CU
    lab_path = os.path.join(a.lab_dir, a.tom_tat_ten)
    prod_tom = os.path.join(a.prod_dir, a.tom_tat_ten)
    thr_lab = read_thresholds(lab_path, a.cot_muc, levels)
    thr_prod = read_thresholds(prod_tom, a.cot_muc, levels) if os.path.isfile(prod_tom) else {}
    branches = sorted({b for b, _ in list(thr_lab) + list(thr_prod)})
    rows_by_b = {}
    for b in branches:
        path = os.path.join(a.prod_dir, "scores_%s.tsv" % b)
        if os.path.isfile(path):
            rows_by_b[b] = read_scores(path)
    print("=== nguong lab ===")
    in_bang(thr_lab, rows_by_b, a.days, a.cot_muc, "lab")
    print("=== nguong tu hoc production ===")
    in_bang(thr_prod, rows_by_b, a.days, a.cot_muc, "prod_tu_hoc")


if __name__ == "__main__":
    main()
