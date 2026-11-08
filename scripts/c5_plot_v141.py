#!/usr/bin/env python3
"""SVG H1 / H2' / H3' cho M6i-c2b (v1.4.1). Chi thu vien chuan."""
from __future__ import annotations

import math
import os
import sys

BRANCHES = ("AGG_cgroup_giay", "BASELINE_dt_tho", "PHANRA_5tp")
COLORS = {"AGG_cgroup_giay": "#1f77b4", "BASELINE_dt_tho": "#ff7f0e", "PHANRA_5tp": "#2ca02c"}
SHORT = {"AGG_cgroup_giay": "AGG", "BASELINE_dt_tho": "BASE", "PHANRA_5tp": "PHANRA"}
IDS = ["B1", "N1", "B4", "N4"]
MUCS = ["0", "D1-8", "D1-16", "D3-7"]
CHIEU = list("ABCDE")


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
        return float(s)
    except (TypeError, ValueError):
        return float("nan")


def svg_header(w, h, title):
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % (w, h),
        '<rect width="100%" height="100%" fill="white"/>',
        '<text x="%d" y="24" font-family="sans-serif" font-size="14" text-anchor="middle">%s</text>' % (w // 2, title),
    ]


def _bar_chart(out_path, title, labels, series, ymax=1.0):
    W, H = 1200, 480
    pad_l, pad_r, pad_t, pad_b = 60, 20, 50, 100
    plot_w, plot_h = W - pad_l - pad_r, H - pad_t - pad_b
    lines = svg_header(W, H, title)
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t, pad_l, pad_t + plot_h))
    lines.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#333"/>' % (pad_l, pad_t + plot_h, pad_l + plot_w, pad_t + plot_h))
    n_b = max(1, len(series))
    group = plot_w / max(1, len(labels))
    bar_w = group * 0.75 / n_b

    def y_of(v):
        if v != v:
            return pad_t + plot_h
        return pad_t + plot_h * (1 - min(max(v, 0), ymax) / ymax)

    for i, lab in enumerate(labels):
        x0 = pad_l + i * group
        lines.append(
            '<text x="%.1f" y="%d" font-family="sans-serif" font-size="9" text-anchor="end" '
            'transform="rotate(-40 %.1f %d)">%s</text>' % (x0 + group / 2, H - 8, x0 + group / 2, H - 8, lab)
        )
        for j, (name, color, vals) in enumerate(series):
            if i >= len(vals):
                continue
            v = vals[i]
            if v != v:
                continue
            y = y_of(v)
            x = x0 + (group - n_b * bar_w) / 2 + j * bar_w
            lines.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>' % (
                x, y, bar_w - 1, pad_t + plot_h - y, color))
    x = pad_l
    for name, color, _ in series:
        lines.append('<rect x="%d" y="36" width="12" height="12" fill="%s"/>' % (x, color))
        lines.append('<text x="%d" y="46" font-family="sans-serif" font-size="11">%s</text>' % (x + 16, name))
        x += 110
    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def h1(score_dir, out_path, ngan_sach=0.01):
    labels = ["%s-%s" % (i, m) for i in IDS for m in MUCS]
    series = []
    for b in BRANCHES:
        by = {}
        path_id = os.path.join(score_dir, "phat_hien_id_ns_%s.tsv" % b)
        if not os.path.isfile(path_id):
            series.append((SHORT[b], COLORS[b], [float("nan")] * len(labels)))
            continue
        for row in read_tsv(path_id):
            if abs(fnum(row.get("ngan_sach", "nan")) - ngan_sach) > 1e-9:
                continue
            if row.get("loai") not in (None, "", "tan_cong"):
                if row.get("loai") != "tan_cong":
                    continue
            rid = row.get("id", "")
            core = rid.split("#", 1)[0]
            if "@" in core:
                iid, muc = core.split("@", 1)
            else:
                iid, muc = core, "0"
            if iid not in IDS:
                continue
            by["%s-%s" % (iid, muc)] = fnum(row.get("ty_le", "nan"))
        series.append((SHORT[b], COLORS[b], [by.get(lab, float("nan")) for lab in labels]))
    _bar_chart(out_path, "H1 phat hien lab1c @ ngan sach 0.01 (CH*)", labels, series)


def h2p(score_dir, out_path):
    series = []
    styles = {
        ("BASELINE_dt_tho", "D1-16"): ("#ff7f0e", ""),
        ("BASELINE_dt_tho", "D3-7"): ("#ff7f0e", "4 3"),
        ("PHANRA_5tp", "D1-16"): ("#2ca02c", ""),
        ("PHANRA_5tp", "D3-7"): ("#2ca02c", "4 3"),
    }
    xs, ys = [], []
    for b in ("BASELINE_dt_tho", "PHANRA_5tp"):
        path = os.path.join(score_dir, "duong_tranh_chap_%s.tsv" % b)
        if not os.path.isfile(path):
            continue
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
        raise SystemExit("H2' khong co diem: " + score_dir)
    W, H = 900, 520
    pad_l, pad_r, pad_t, pad_b = 70, 20, 50, 60
    plot_w, plot_h = W - pad_l - pad_r, H - pad_t - pad_b
    xmin, xmax = min(xs), max(xs)
    ymax = max(1.0, max(ys) if ys else 1.0)
    lx0, lx1 = math.log10(xmin), math.log10(xmax)

    def x_of(v):
        return pad_l + plot_w * (math.log10(v) - lx0) / (lx1 - lx0 or 1)

    def y_of(v):
        return pad_t + plot_h * (1 - v / ymax)

    lines = svg_header(W, H, "H2' duong tranh chap lab1c CH* (BASE vs PHANRA)")
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
    for b, muc in (("BASELINE_dt_tho", "D1-16"), ("BASELINE_dt_tho", "D3-7"),
                   ("PHANRA_5tp", "D1-16"), ("PHANRA_5tp", "D3-7")):
        color, _ = styles[(b, muc)]
        lines.append('<text x="%d" y="42" font-family="sans-serif" font-size="11" fill="%s">%s %s</text>' % (
            x, color, SHORT[b], muc))
        x += 140
    lines.append('<text x="%d" y="%d" font-family="sans-serif" font-size="11" text-anchor="middle">bdg nen sach (log)</text>' % (
        pad_l + plot_w / 2, H - 8))
    lines.append("</svg>")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def h3p(lab1c_root, out_path, ngan_sach=0.01):
    labels = CHIEU
    series = []
    for b, color in (("BASELINE_dt_tho", COLORS["BASELINE_dt_tho"]),
                     ("PHANRA_5tp", COLORS["PHANRA_5tp"])):
        vals = []
        for ch in CHIEU:
            path = os.path.join(lab1c_root, "score-v141-%s" % ch, "tom_tat_ngan_sach.tsv")
            v = float("nan")
            if os.path.isfile(path):
                for row in read_tsv(path):
                    if row["branch"] != b:
                        continue
                    if abs(fnum(row["ngan_sach"]) - ngan_sach) > 1e-9:
                        continue
                    v = fnum(row.get("bdg_nen_kiem_tra", "nan"))
                    break
            vals.append(v)
        series.append((SHORT[b], color, vals))
    _bar_chart(out_path, "H3' bdg nen kiem tra lab1c @ 0.01 theo bo chieu A..E", labels, series)


def main():
    ch = open("/root/hids/out/c5-lab1/r043-tables/CH_star.txt").read().strip().split("=")[-1].strip()
    lab1c = "/root/hids/out/c5-lab1c"
    hinh = "/root/hids/out/c5-lab1/hinh-v141"
    os.makedirs(hinh, exist_ok=True)
    h1(os.path.join(lab1c, "score-v141-%s" % ch), os.path.join(hinh, "H1_lab1c_phat_hien.svg"))
    h2p(os.path.join(lab1c, "score-v141-%s" % ch), os.path.join(hinh, "H2p_duong_tranh_chap.svg"))
    h3p(lab1c, os.path.join(hinh, "H3p_bo_chieu_A_E.svg"))
    print("CH*", ch, "hinh", hinh)


if __name__ == "__main__":
    main()
