#!/usr/bin/env python3
"""SVG H1/H2/H3 cho M6i-b. Chi thu vien chuan. Doc TSV da cham, khong cham lai."""
from __future__ import annotations

import math
import os
import sys

ORDER = ["0", "2", "4", "D1-8", "D1-16", "D3-4", "D3-7",
         "B4cu-0", "B4cu-2", "B4cu-4", "N4cu-0", "N4cu-2", "N4cu-4"]
BRANCHES = ("AGG_cgroup_giay", "BASELINE_dt_tho", "PHANRA_5tp")
COLORS = {"AGG_cgroup_giay": "#1f77b4", "BASELINE_dt_tho": "#ff7f0e", "PHANRA_5tp": "#2ca02c"}
SHORT = {"AGG_cgroup_giay": "AGG", "BASELINE_dt_tho": "BASE", "PHANRA_5tp": "PHANRA"}


def read_tsv(path):
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        rows = []
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < len(header):
                continue
            rows.append(dict(zip(header, p)))
        return rows


def fnum(s):
    try:
        v = float(s)
    except (TypeError, ValueError):
        return float("nan")
    return v


def svg_header(w, h, title):
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % (w, h),
        '<rect width="100%" height="100%" fill="white"/>',
        '<text x="%d" y="24" font-family="sans-serif" font-size="14" text-anchor="middle">%s</text>' % (w // 2, title),
    ]


def h1(score_dir, out_path):
    """Bao dong gia theo muc tai ngan sach 0.01."""
    data = {}
    mucs = []
    for b in BRANCHES:
        path = os.path.join(score_dir, "theo_muc_ns_%s.tsv" % b)
        if not os.path.isfile(path):
            continue
        by = {}
        for row in read_tsv(path):
            if abs(fnum(row["ngan_sach"]) - 0.01) > 1e-9:
                continue
            n = int(row["n"])
            if n <= 0:
                continue
            by[row["muc"]] = fnum(row["bao_dong_gia"])
        data[b] = by
        for m in by:
            if m not in mucs:
                mucs.append(m)
    mucs = [m for m in ORDER if m in mucs] + [m for m in mucs if m not in ORDER]
    if not mucs:
        raise SystemExit("H1 khong co muc: " + score_dir)
    W, H = 1100, 480
    pad_l, pad_r, pad_t, pad_b = 60, 20, 50, 90
    plot_w, plot_h = W - pad_l - pad_r, H - pad_t - pad_b
    ymax = 1.0
    lines = svg_header(W, H, "Bao dong gia theo muc tranh chap, ngan sach 0.01")
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t, pad_l, pad_t + plot_h))
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t + plot_h, pad_l + plot_w, pad_t + plot_h))
    n_b = max(1, len(data))
    group = plot_w / len(mucs)
    bar_w = group * 0.75 / n_b
    def y_of(v):
        return pad_t + plot_h * (1 - (0 if v != v else v) / ymax)
    for i, m in enumerate(mucs):
        x0 = pad_l + i * group
        lines.append('<text x="%.1f" y="%d" font-family="sans-serif" font-size="10" text-anchor="end" transform="rotate(-40 %.1f %d)">%s</text>' % (
            x0 + group / 2, H - 8, x0 + group / 2, H - 8, m))
        for j, b in enumerate(BRANCHES):
            if b not in data or m not in data[b]:
                continue
            v = data[b][m]
            y = y_of(v)
            x = x0 + (group - n_b * bar_w) / 2 + j * bar_w
            h = pad_t + plot_h - y
            lines.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (x, y, bar_w - 1, h, COLORS[b]))
    x = pad_l
    for b in BRANCHES:
        if b not in data:
            continue
        lines.append('<rect x="%d" y="36" width="12" height="12" fill="%s"/>' % (x, COLORS[b]))
        lines.append('<text x="%d" y="46" font-family="sans-serif" font-size="11">%s</text>' % (x + 16, SHORT[b]))
        x += 90
    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def h2(score_dir, out_path):
    series = []  # (name, color, dash, points xy)
    styles = {
        ("AGG_cgroup_giay", "D1-16"): ("#1f77b4", ""),
        ("AGG_cgroup_giay", "D3-7"): ("#1f77b4", "4 3"),
        ("BASELINE_dt_tho", "D1-16"): ("#ff7f0e", ""),
        ("BASELINE_dt_tho", "D3-7"): ("#ff7f0e", "4 3"),
        ("PHANRA_5tp", "D1-16"): ("#2ca02c", ""),
        ("PHANRA_5tp", "D3-7"): ("#2ca02c", "4 3"),
    }
    xs, ys = [], []
    for b in BRANCHES:
        path = os.path.join(score_dir, "duong_tranh_chap_%s.tsv" % b)
        rows = read_tsv(path)
        for muc in ("D1-16", "D3-7"):
            col = "bdg_muc_%s" % muc
            pts = []
            for row in rows:
                x = fnum(row["bdg_nen_thuc"])
                y = fnum(row.get(col, "nan"))
                if x == x and x > 0 and y == y:
                    pts.append((x, y))
                    xs.append(x)
                    ys.append(y)
            series.append((b, muc, pts))
    if not xs:
        raise SystemExit("H2 khong co diem")
    W, H = 900, 520
    pad_l, pad_r, pad_t, pad_b = 70, 20, 50, 60
    plot_w, plot_h = W - pad_l - pad_r, H - pad_t - pad_b
    xmin, xmax = min(xs), max(xs)
    ymin, ymax = 0.0, max(1.0, max(ys))
    lx0, lx1 = math.log10(xmin), math.log10(xmax)

    def x_of(v):
        return pad_l + plot_w * (math.log10(v) - lx0) / (lx1 - lx0 or 1)

    def y_of(v):
        return pad_t + plot_h * (1 - v / ymax)

    lines = svg_header(W, H, "Duong tranh chap: bdg nen sach (log) -> D1-16 va D3-7")
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t, pad_l, pad_t + plot_h))
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t + plot_h, pad_l + plot_w, pad_t + plot_h))
    for b, muc, pts in series:
        if len(pts) < 2:
            continue
        color, dash = styles[(b, muc)]
        d = " ".join("%.1f,%.1f" % (x_of(x), y_of(y)) for x, y in pts)
        extra = (' stroke-dasharray="%s"' % dash) if dash else ""
        lines.append('<polyline fill="none" stroke="%s" stroke-width="2"%s points="%s"/>' % (color, extra, d))
    x = pad_l
    for b, muc in (("BASELINE_dt_tho", "D1-16"), ("BASELINE_dt_tho", "D3-7")):
        color, dash = styles[(b, muc)]
        lines.append('<text x="%d" y="42" font-family="sans-serif" font-size="11" fill="%s">%s %s%s</text>' % (
            x, color, SHORT[b], muc, " net dut" if dash else " net lien"))
        x += 160
    lines.append('<text x="%d" y="%d" font-family="sans-serif" font-size="11" text-anchor="middle">bdg nen sach (log)</text>' % (pad_l + plot_w / 2, H - 8))
    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def h3(toc_dir, khong_dir, out_path):
    bands = []
    data = {}
    for b in BRANCHES:
        path = os.path.join(toc_dir, "theo_dai_ns_%s.tsv" % b)
        by = {}
        if os.path.isfile(path):
            for row in read_tsv(path):
                if abs(fnum(row["ngan_sach"]) - 0.01) > 1e-9:
                    continue
                if int(row["n"]) <= 0:
                    continue
                by[row["dai"]] = fnum(row["bao_dong_gia"])
        data[b] = by
        for k in by:
            if k not in bands:
                bands.append(k)
    def band_key(s):
        if s.startswith("r_"):
            try:
                return (0, int(s[2:]))
            except ValueError:
                return (1, s)
        return (2, s)
    bands.sort(key=band_key)
    ref = {}
    for b in BRANCHES:
        path = os.path.join(khong_dir, "theo_muc_ns_%s.tsv" % b)
        ref[b] = float("nan")
        if not os.path.isfile(path):
            continue
        for row in read_tsv(path):
            if abs(fnum(row["ngan_sach"]) - 0.01) > 1e-9:
                continue
            if row["muc"] == "0":
                ref[b] = fnum(row["bao_dong_gia"])
    if not bands:
        raise SystemExit("H3 khong co dai")
    W, H = 1000, 480
    pad_l, pad_r, pad_t, pad_b = 60, 20, 56, 70
    plot_w, plot_h = W - pad_l - pad_r, H - pad_t - pad_b
    ymax = 1.0
    lines = svg_header(W, H, "Bdg nen kiem tra theo dai, ngan sach 0.01 (toc_do; net = khong muc 0)")
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t, pad_l, pad_t + plot_h))
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t + plot_h, pad_l + plot_w, pad_t + plot_h))
    n_b = 3
    group = plot_w / len(bands)
    bar_w = group * 0.75 / n_b
    def y_of(v):
        return pad_t + plot_h * (1 - (0 if v != v else min(v, ymax)) / ymax)
    for i, dai in enumerate(bands):
        x0 = pad_l + i * group
        lines.append('<text x="%.1f" y="%d" font-family="sans-serif" font-size="10" text-anchor="middle">%s</text>' % (x0 + group / 2, H - 16, dai))
        for j, b in enumerate(BRANCHES):
            if dai not in data[b]:
                continue
            v = data[b][dai]
            y = y_of(v)
            x = x0 + (group - n_b * bar_w) / 2 + j * bar_w
            lines.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (
                x, y, bar_w - 1, pad_t + plot_h - y, COLORS[b]))
    for b in BRANCHES:
        v = ref[b]
        if v == v:
            y = y_of(v)
            lines.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="%s" stroke-dasharray="5 3"/>' % (
                pad_l, y, pad_l + plot_w, y, COLORS[b]))
    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "/root/hids/out/c5-lab1"
    hinh = os.path.join(root, "hinh")
    os.makedirs(hinh, exist_ok=True)
    for mode in ("tocdo", "nhip", "khong"):
        h1(os.path.join(root, "score-v131-%s" % mode), os.path.join(hinh, "H1_%s.svg" % mode))
    h2(os.path.join(root, "score-v131-tocdo"), os.path.join(hinh, "H2_duong_tranh_chap.svg"))
    h3(os.path.join(root, "score-v131-tocdo"), os.path.join(root, "score-v131-khong"),
       os.path.join(hinh, "H3_dai_tocdo_vs_khong.svg"))
    print("hinh", hinh)


if __name__ == "__main__":
    main()
