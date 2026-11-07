#!/usr/bin/env python3
"""lab1c_n4_zlib.py — N4 một tiến trình: cứ 22 s đọc payload + zlib.compress ≈ 2 s (1.9c).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import zlib


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--payload", required=True, help="file payload cố định")
    ap.add_argument("--period-s", type=float, default=22.0)
    ap.add_argument("--out", default="/tmp/lab1c-n4.out")
    ap.add_argument("--log", required=True)
    ap.add_argument("--name", default="lab1c-n4-zlib")
    ap.add_argument("--level", type=int, default=6)
    args = ap.parse_args()

    try:
        import setproctitle  # type: ignore

        setproctitle.setproctitle(args.name)
    except Exception:
        try:
            with open("/proc/self/comm", "w") as f:
                f.write(args.name[:15])
        except Exception:
            pass

    raw = open(args.payload, "rb").read()
    t_end = time.monotonic() + args.duration_s
    n = 0
    with open(args.log, "w") as log:
        log.write("cycle\tmono_ns\tcompress_s\tsize_in\tsize_out\n")
        log.flush()
        while time.monotonic() < t_end:
            t0m = time.monotonic()
            t0 = time.monotonic_ns()
            out = zlib.compress(raw, args.level)
            with open(args.out, "wb") as fo:
                fo.write(out)
            dt = time.monotonic() - t0m
            n += 1
            log.write(f"{n}\t{t0}\t{dt:.4f}\t{len(raw)}\t{len(out)}\n")
            log.flush()
            sleep = args.period_s - dt
            remain = t_end - time.monotonic()
            if remain <= 0:
                break
            if sleep > 0:
                time.sleep(min(sleep, remain))
    print(f"lab1c_n4_zlib cycles={n} pid={os.getpid()} payload_bytes={len(raw)}", file=sys.stderr)
    return 0 if n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
