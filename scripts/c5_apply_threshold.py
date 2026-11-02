#!/usr/bin/env python3
"""Ap nguong lab (tom_tat, det 0.90/0.95/1.00) len scores production ngay 6-7."""
from __future__ import annotations

import argparse
import os


LEVELS = (0.90, 0.95, 1.00)


def read_thresholds(path):
    out = {}
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            b = p[idx["branch"]]
            lv = float(p[idx["muc_phat_hien"]])
            if lv not in LEVELS:
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
            except ValueError:
                continue
            rows.append((int(p[idx["start_ns"]]), p[idx["tid"]], diem))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tom-tat", required=True)
    ap.add_argument("--prod-score", required=True, help="thu muc score production")
    ap.add_argument("--days", type=int, default=2)
    ap.add_argument("--day-ns", type=int, default=86_400_000_000_000)
    a = ap.parse_args()
    thr = read_thresholds(a.tom_tat)
    branches = sorted({b for b, _ in thr})
    print("branch\tmuc_phat_hien\tnguong_lab\tn_cua_so\tn_bao_dong\tty_le\tbao_dong_moi_host_ngay\ttid_ngay_bao\ttid_ngay_quan_sat\tty_le_tid_ngay")
    for b in branches:
        path = os.path.join(a.prod_score, "scores_%s.tsv" % b)
        if not os.path.isfile(path):
            print("%s\tNA\tkhong co %s" % (b, path))
            continue
        rows = read_scores(path)
        for lv in LEVELS:
            t = thr.get((b, lv), float("nan"))
            if t != t:
                print("%s\t%.2f\tnan\t%d\t0\tnan\tnan\t0\t0\tnan" % (b, lv, len(rows)))
                continue
            alarm = [(s, tid, d) for s, tid, d in rows if d >= t]
            n = len(rows) or 1
            na = len(alarm)
            # tid-ngay: ngay = start // day_ns
            obs = {(tid, s // a.day_ns) for s, tid, _ in rows}
            hit = {(tid, s // a.day_ns) for s, tid, _ in alarm}
            print("%s\t%.2f\t%.4f\t%d\t%d\t%.6f\t%.4f\t%d\t%d\t%.6f" % (
                b, lv, t, len(rows), na, na / n, na / a.days,
                len(hit), len(obs), (len(hit) / len(obs) if obs else float("nan")),
            ))


if __name__ == "__main__":
    main()
