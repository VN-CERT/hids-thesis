#!/usr/bin/env python3
"""LAB-2 N-A2 — health-check HTTP chu kỳ (benign song sinh beacon).
Đích cố định 192.168.77.20. GET hợp lệ, không phải C2.
"""
from __future__ import annotations

import argparse
import random
import sys
import time
import urllib.error
import urllib.request

ALLOWED_HOST = "192.168.77.20"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dich", default=f"{ALLOWED_HOST}:18081",
                    help="host:port (mac dinh 18081 backup/benign HTTP)")
    ap.add_argument("--period-s", type=float, default=60.0)
    ap.add_argument("--jitter-s", type=float, default=30.0,
                    help="jitter 0..jitter-s giay (giong beacon ±jitter)")
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--path", default="/")
    args = ap.parse_args()

    if ":" not in args.dich:
        raise SystemExit("dich phai host:port")
    host, port_s = args.dich.rsplit(":", 1)
    if host != ALLOWED_HOST:
        raise SystemExit(f"dich chi duoc {ALLOWED_HOST}")
    port = int(port_s)
    url = f"http://{host}:{port}{args.path}"

    t_end = time.monotonic() + args.duration_s
    n = 0
    with open(args.log, "w") as lg:
        lg.write("n\tmono_ns\twall\thttp_code\telapsed_ms\n")
        while time.monotonic() < t_end:
            n += 1
            t0 = time.monotonic_ns()
            tw = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            code = 0
            t_req0 = time.monotonic()
            try:
                with urllib.request.urlopen(url, timeout=10) as resp:
                    code = resp.status
                    _ = resp.read(64)
            except urllib.error.HTTPError as e:
                code = e.code
            except Exception as e:
                code = -1
                lg.write(f"{n}\t{t0}\t{tw}\t{code}\t0\terr={type(e).__name__}\n")
                lg.flush()
                print(f"cycle={n} err={e}", flush=True)
            else:
                ms = (time.monotonic() - t_req0) * 1000
                lg.write(f"{n}\t{t0}\t{tw}\t{code}\t{ms:.3f}\n")
                lg.flush()
                print(f"cycle={n} code={code} ms={ms:.1f}", flush=True)
            # sleep period + jitter (tru thoi gian request)
            remain = t_end - time.monotonic()
            if remain <= 0:
                break
            wait = args.period_s + random.uniform(0, max(0.0, args.jitter_s))
            time.sleep(min(wait, remain))
        lg.write(f"# summary cycles={n}\n")
    print(f"lab2_healthcheck cycles={n}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
