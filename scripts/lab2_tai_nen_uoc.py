#!/usr/bin/env python3
"""LAB-2 Cách B — ước tải nền từ rec/s trong cửa sổ nhãn (không bịa loadavg).
Doc nhan-tan-cong-lab2.tsv + .bin (rec-export). KHONG can collector dang chay.
"""
from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys
from pathlib import Path


def muc_from_run_id(rid: str) -> str:
    # A2-0-c-DAY / A2-D1-8-c-DAY / A2-D3-7-c-DAY
    parts = rid.split("-")
    # find muc
    if "-D1-8-" in rid:
        return "D1-8"
    if "-D3-7-" in rid:
        return "D3-7"
    if "-D1-16-" in rid:
        return "D1-16"
    # level 0: LOP-0-c-DAY
    return "0"


def worker_note(muc: str) -> str:
    if muc == "D3-7":
        return "D3-7=7 worker stream"
    if muc == "D1-8":
        return "D1-8=8 cpu hog"
    if muc == "0":
        return "muc=0 khong stress-ng"
    return f"muc={muc}"


def count_recs_per_sec(datadir: str, t0: int, t1: int) -> float:
    bins = sorted(glob.glob(os.path.join(datadir, "*.bin")))
    if not bins:
        return float("nan")
    n = 0
    for b in bins:
        p = subprocess.run(
            ["./bin/rec-export", b],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if p.returncode != 0 or not p.stdout:
            continue
        lines = p.stdout.splitlines()
        if not lines:
            continue
        hdr = lines[0].split(",")
        try:
            its = hdr.index("ts_enter")
        except ValueError:
            continue
        for line in lines[1:]:
            c = line.split(",")
            if len(c) <= its:
                continue
            try:
                ts = int(c[its])
            except ValueError:
                continue
            if t0 <= ts <= t1:
                n += 1
    dur = max(1e-9, (t1 - t0) / 1e9)
    return n / dur


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--val", required=True)
    ap.add_argument("--nhan", default="lab/nhan-tan-cong-lab2.tsv")
    args = ap.parse_args()
    val = Path(args.val)
    out = val / "tai-nen-uoc-tomtat.tsv"
    nhan = Path(args.nhan)
    if not nhan.is_file():
        print(f"thieu {nhan}", file=sys.stderr)
        return 1

    rows_out = [
        "run_id\tlop\tmuc_tranh_chap\tban_ghi_tren_giay_tb\tghi_chu\n"
    ]
    for i, line in enumerate(nhan.read_text().splitlines()):
        if i == 0 or not line.strip():
            continue
        cols = line.split("\t")
        if len(cols) < 14:
            continue
        rid, lop = cols[0], cols[1]
        if rid.startswith("THU-"):
            continue
        t0, t1 = int(cols[8]), int(cols[9])
        muc = cols[6] if cols[6] else muc_from_run_id(rid)
        # sess path
        sess = val / lop / rid
        datadir = sess / "data"
        if not datadir.is_dir():
            # thu?
            continue
        rps = count_recs_per_sec(str(datadir), t0, t1)
        note = (
            "tai truc tiep khong do luc chay; uoc tu rec/s + muc; "
            + worker_note(muc)
        )
        rows_out.append(f"{rid}\t{lop}\t{muc}\t{rps:.3f}\t{note}\n")
        print(f"{rid}\t{muc}\t{rps:.3f} rec/s", flush=True)

    out.write_text("".join(rows_out))
    print(f"wrote {out}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
