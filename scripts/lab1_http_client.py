#!/usr/bin/env python3
"""Client HTTP chu ky cho B1/N1 LAB-1 — goi noi bo nginx file4k.bin.
Cach dung:
  lab1_http_client.py --name <ten_tien_trinh> --period-s <giay> --duration-s <giay> --log <file>
Jitter 0-50% moi chu ky. Thoat 0 khi xong; in so chu ky ra stderr.
"""
from __future__ import annotations

import argparse
import os
import random
import sys
import time
import urllib.error
import urllib.request


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="ten hien thi (argv0) — dung setproctitle neu co")
    ap.add_argument("--period-s", type=float, required=True)
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--url", default="http://127.0.0.1:18080/file4k.bin")
    ap.add_argument("--log", required=True)
    args = ap.parse_args()

    # doi ten tien trinh (B1 ten la, N1 ten hop le)
    try:
        import setproctitle  # type: ignore

        setproctitle.setproctitle(args.name)
    except Exception:
        # fallback: ghi vao /proc/self/comm (toi da 15 ky tu)
        try:
            with open("/proc/self/comm", "w") as f:
                f.write(args.name[:15])
        except Exception:
            pass

    t_end = time.monotonic() + args.duration_s
    n = 0
    with open(args.log, "w") as log:
        log.write("cycle\tmono_ns\thttp_code\tsize\telapsed_ms\n")
        log.flush()
        while time.monotonic() < t_end:
            t0 = time.monotonic_ns()
            code, size, err = 0, 0, ""
            try:
                with urllib.request.urlopen(args.url, timeout=10) as r:
                    body = r.read()
                    code = getattr(r, "status", 200) or 200
                    size = len(body)
            except urllib.error.HTTPError as e:
                code = e.code
                err = str(e)
            except Exception as e:
                code = -1
                err = str(e)
            t1 = time.monotonic_ns()
            n += 1
            log.write(f"{n}\t{t0}\t{code}\t{size}\t{(t1 - t0) / 1e6:.3f}")
            if err:
                log.write(f"\t{err}")
            log.write("\n")
            log.flush()
            # jitter 0-50%
            delay = args.period_s * (1.0 + random.uniform(0.0, 0.50))
            # khong vuot duration
            remain = t_end - time.monotonic()
            if remain <= 0:
                break
            time.sleep(min(delay, remain))
    print(f"lab1_http_client name={args.name} cycles={n}", file=sys.stderr)
    return 0 if n > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
