#!/usr/bin/env python3
"""Ve SVG: bao dong gia theo muc tranh chap, cac nhanh, tai muc phat hien 90%.

Doc features + nhan + muc + train-until; dung cung toan hoc c5_score (import).
Chi thu vien chuan.
"""
from __future__ import annotations

import argparse
import math
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "analysis"))
import c5_score as sc  # noqa: E402

DET = 0.90


def far_by_muc(scored, thr):
    by = {}
    for s, is_a, m in scored:
        if is_a:
            continue
        key = str(m) if m is not None else "0"
        n, h = by.get(key, (0, 0))
        by[key] = (n + 1, h + (1 if (thr == thr and s >= thr) else 0))
    out = {}
    for k, (n, h) in by.items():
        out[k] = (h / n if n else float("nan"), n, h)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--features", required=True)
    ap.add_argument("--nhan", default=None)
    ap.add_argument("--muc", default=None)
    ap.add_argument("--train-until", type=int, required=True)
    ap.add_argument("--out", required=True, help="file .svg")
    ap.add_argument("--det", type=float, default=DET)
    a = ap.parse_args()

    rows, dims_all = sc.read_features(a.features)
    atk = sc.read_ranges(a.nhan, "t_bat_dau_mono_ns", "t_ket_thuc_mono_ns", "id", "lop", skip_n=True)
    muc = sc.read_ranges(a.muc, "start_ns", "stop_ns", "muc")
    cut = a.train_until
    branches = sorted({w["branch"] for w in rows})

    # thu thap: branch -> {muc -> far}
    data = {}
    muc_keys = set()
    for b in branches:
        rb = [w for w in rows if w["branch"] == b]
        dims = [d for d in dims_all if not d.startswith("ctx_") and d != "nguon"
                and any(w["f"].get(d, float("nan")) == w["f"].get(d, float("nan")) for w in rb)]
        # khop c5_score v1.1: huan luyen = nen & stop<=cut; kiem = nguon!=nen hoac start>=cut
        train = [w for w in rb if w.get("nguon", "nen") == "nen" and w["stop"] <= cut
                 and sc.overlaps(w, atk) is None]
        test = [w for w in rb if w.get("nguon", "nen") != "nen" or w["start"] >= cut]
        stat = sc.fit(train, dims)
        scored = []
        for w in (test if test else rb):
            s = sc.score(w, stat, dims)
            if s != s:
                continue
            scored.append((s, sc.overlaps(w, atk) is not None, sc.overlaps(w, muc)))
        tb = sc.tradeoff(scored)
        thr, far = sc.thr_at_detection(tb, a.det)
        by = far_by_muc(scored, thr) if thr == thr else {}
        data[b] = {"thr": thr, "far_all": far, "by": by}
        muc_keys.update(by.keys())

    mucs = sorted(muc_keys, key=lambda x: (float(x) if x.replace(".", "", 1).isdigit() else 999, x))
    if not mucs:
        mucs = ["0"]

    # SVG grouped bars
    W, H = 900, 480
    pad_l, pad_r, pad_t, pad_b = 70, 30, 50, 70
    plot_w = W - pad_l - pad_r
    plot_h = H - pad_t - pad_b
    n_m = len(mucs)
    n_b = max(1, len(branches))
    group_w = plot_w / n_m
    bar_w = group_w * 0.7 / n_b
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd"]

    ymax = 0.0
    for b in branches:
        for k, (far, _, _) in data[b]["by"].items():
            if far == far:
                ymax = max(ymax, far)
    if ymax <= 0:
        ymax = 1.0
    ymax = math.ceil(ymax * 10) / 10.0
    if ymax < 0.1:
        ymax = 0.1

    def y_of(v):
        return pad_t + plot_h * (1.0 - v / ymax)

    lines = []
    lines.append('<?xml version="1.0" encoding="UTF-8"?>')
    lines.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % (W, H))
    lines.append('<rect width="100%" height="100%" fill="white"/>')
    lines.append('<text x="%d" y="28" font-family="sans-serif" font-size="16" text-anchor="middle">'
                 'Bao dong gia theo muc tranh chap (det=%.0f%%)</text>' % (W // 2, a.det * 100))
    # axes
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (
        pad_l, pad_t, pad_l, pad_t + plot_h))
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (
        pad_l, pad_t + plot_h, pad_l + plot_w, pad_t + plot_h))
    for i in range(0, 6):
        v = ymax * i / 5
        y = y_of(v)
        lines.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="#ddd"/>' % (
            pad_l, y, pad_l + plot_w, y))
        lines.append('<text x="%d" y="%.1f" font-family="sans-serif" font-size="11" text-anchor="end">%.2f</text>' % (
            pad_l - 8, y + 4, v))
    lines.append('<text x="18" y="%d" font-family="sans-serif" font-size="12" transform="rotate(-90 18 %d)">'
                 'bao_dong_gia</text>' % (pad_t + plot_h // 2, pad_t + plot_h // 2))

    for mi, mk in enumerate(mucs):
        gx = pad_l + mi * group_w + group_w * 0.15
        for bi, b in enumerate(branches):
            far, n, h = data[b]["by"].get(mk, (float("nan"), 0, 0))
            if far != far:
                continue
            x = gx + bi * bar_w
            y = y_of(far)
            hgt = pad_t + plot_h - y
            col = colors[bi % len(colors)]
            lines.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (
                x, y, bar_w * 0.9, hgt, col))
        cx = pad_l + mi * group_w + group_w / 2
        lines.append('<text x="%.1f" y="%d" font-family="sans-serif" font-size="12" text-anchor="middle">'
                     'muc=%s</text>' % (cx, pad_t + plot_h + 20, mk))

    # legend
    lx, ly = pad_l + 10, H - 28
    for bi, b in enumerate(branches):
        col = colors[bi % len(colors)]
        lines.append('<rect x="%d" y="%d" width="14" height="14" fill="%s"/>' % (lx, ly - 12, col))
        lines.append('<text x="%d" y="%d" font-family="sans-serif" font-size="11">%s</text>' % (
            lx + 20, ly, b))
        lx += 18 + len(b) * 7 + 40

    lines.append('<text x="%d" y="%d" font-family="sans-serif" font-size="11" fill="#555">'
                 'truc X = muc tranh chap (muc.tsv); tai cung ty le phat hien %.0f%%</text>' % (
                     pad_l, H - 8, a.det * 100))  # noqa: percent in SVG text
    lines.append("</svg>")

    os.makedirs(os.path.dirname(os.path.abspath(a.out)) or ".", exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote %s branches=%d mucs=%s" % (a.out, len(branches), ",".join(mucs)))


if __name__ == "__main__":
    main()
