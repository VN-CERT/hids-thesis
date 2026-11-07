#!/usr/bin/env python3
"""lab1c_b4_burner.py — B4 duty cycle: bận 2.0 s / sleep 20 s (Phụ lục 1.9c).
Một tiến trình sống suốt --duration-s. Ghi chu kỳ ra --log.
"""
from __future__ import annotations

import argparse
import os
import sys
import time


def busy(seconds: float) -> None:
    end = time.perf_counter() + seconds
    x = 0.0
    while time.perf_counter() < end:
        x = (x + 1.000001) * 1.000001
        if x > 1e12:
            x = 0.0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--busy-s", type=float, default=2.0)
    ap.add_argument("--sleep-s", type=float, default=20.0)
    ap.add_argument("--log", required=True)
    ap.add_argument("--name", default="lab1c-b4-burner")
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

    t_end = time.monotonic() + args.duration_s
    n = 0
    with open(args.log, "w") as log:
        log.write("cycle\tmono_ns\tbusy_s\tsleep_s\n")
        log.flush()
        while time.monotonic() < t_end:
            t0 = time.monotonic_ns()
            busy(args.busy_s)
            n += 1
            log.write(f"{n}\t{t0}\t{args.busy_s}\t{args.sleep_s}\n")
            log.flush()
            remain = t_end - time.monotonic()
            if remain <= 0:
                break
            time.sleep(min(args.sleep_s, remain))
    print(f"lab1c_b4_burner cycles={n} pid={os.getpid()}", file=sys.stderr)
    return 0 if n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
