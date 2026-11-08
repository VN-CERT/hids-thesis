#!/usr/bin/env python3
"""LAB-2 B2 — low-rate egress (nghiên cứu, lab cô lập).
Chỉ cho phép đích 192.168.77.20. Token-bucket giới hạn tốc độ.
"""
from __future__ import annotations

import argparse
import os
import socket
import sys
import time
import urllib.error
import urllib.request

ALLOWED_HOST = "192.168.77.20"


def parse_dich(s: str) -> tuple[str, int]:
    if ":" not in s:
        raise SystemExit(f"dich phai host:port, nhan {s!r}")
    host, port_s = s.rsplit(":", 1)
    if host != ALLOWED_HOST:
        raise SystemExit(f"dich host chi duoc {ALLOWED_HOST}, nhan {host!r}")
    port = int(port_s)
    if not (1 <= port <= 65535):
        raise SystemExit(f"port khong hop le: {port}")
    return host, port


def parse_size(s: str) -> int:
    s = s.strip().upper()
    mult = 1
    if s.endswith("KB"):
        mult = 1024
        s = s[:-2]
    elif s.endswith("MB"):
        mult = 1024 * 1024
        s = s[:-2]
    elif s.endswith("B"):
        s = s[:-1]
    return int(float(s) * mult)


def parse_rate(s: str) -> float:
    """Trả bytes/giây."""
    s = s.strip().upper().replace(" ", "")
    if s.endswith("KBPS"):
        return float(s[:-4]) * 1024
    if s.endswith("MBPS"):
        return float(s[:-4]) * 1024 * 1024
    if s.endswith("BPS"):
        return float(s[:-3])
    return float(s)


def main() -> int:
    ap = argparse.ArgumentParser(description="LAB-2 B2 egress (chi 192.168.77.20)")
    ap.add_argument("--dich", required=True, help="192.168.77.20:<cong>")
    ap.add_argument("--tong", default="25MB", help="tong byte (mac dinh 25MB de kip cua so 10 phut)")
    ap.add_argument("--toc-do", default="50KBps")
    ap.add_argument("--payload", default="", help="file nguon; neu thieu thi tao ngau nhien")
    ap.add_argument("--log", required=True)
    ap.add_argument("--name", default="lab2-egress")
    ap.add_argument("--path", default="/upload", help="HTTP path POST")
    ap.add_argument("--chunk", type=int, default=4096)
    args = ap.parse_args()

    host, port = parse_dich(args.dich)
    total = parse_size(args.tong)
    rate = parse_rate(args.toc_do)
    if rate <= 0:
        raise SystemExit("toc-do phai > 0")

    log_path = args.log
    os.makedirs(os.path.dirname(log_path) or ".", exist_ok=True)

    if args.payload and os.path.isfile(args.payload):
        with open(args.payload, "rb") as f:
            data = f.read()
        if len(data) < total:
            # lap de du tong
            reps = (total // len(data)) + 1
            data = (data * reps)[:total]
        else:
            data = data[:total]
    else:
        # khong dung secrets; pattern lap
        block = (b"LAB2EGRESS" + bytes(range(256))) * 16
        data = (block * ((total // len(block)) + 1))[:total]

    url = f"http://{host}:{port}{args.path}"
    t0 = time.monotonic_ns()
    tw0 = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    sent = 0
    tokens = 0.0
    last = time.monotonic()
    chunk = max(256, args.chunk)
    err = ""

    with open(log_path, "w") as lg:
        lg.write("event\tmono_ns\twall\tbytes_cum\tdetail\n")
        lg.write(f"start\t{t0}\t{tw0}\t0\turl={url};rate={rate};total={total}\n")
        lg.flush()
        try:
            while sent < total:
                now = time.monotonic()
                tokens = min(rate * 2, tokens + (now - last) * rate)
                last = now
                if tokens < 1:
                    time.sleep(min(0.05, (1 - tokens) / rate))
                    continue
                n = min(chunk, total - sent, int(tokens))
                if n < 1:
                    continue
                body = data[sent : sent + n]
                req = urllib.request.Request(
                    url, data=body, method="POST",
                    headers={"Content-Type": "application/octet-stream",
                             "X-Lab2-Name": args.name,
                             "X-Lab2-Offset": str(sent)},
                )
                try:
                    with urllib.request.urlopen(req, timeout=30) as resp:
                        _ = resp.read(64)
                except urllib.error.HTTPError as e:
                    # 404/501 van tinh la da gui neu server nhan
                    if e.code >= 500:
                        raise
                except Exception as e:
                    # fallback raw TCP neu HTTP khong nhan POST
                    with socket.create_connection((host, port), timeout=30) as s:
                        hdr = (
                            f"POST {args.path} HTTP/1.1\r\n"
                            f"Host: {host}:{port}\r\n"
                            f"Content-Length: {len(body)}\r\n"
                            f"Connection: close\r\n\r\n"
                        ).encode()
                        s.sendall(hdr + body)
                        try:
                            s.recv(256)
                        except Exception:
                            pass
                sent += n
                tokens -= n
                if sent == n or sent % (rate * 5) < n or sent >= total:
                    lg.write(f"progress\t{time.monotonic_ns()}\t"
                             f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')}\t{sent}\t\n")
                    lg.flush()
        except Exception as e:
            err = repr(e)
            lg.write(f"error\t{time.monotonic_ns()}\t"
                     f"{time.strftime('%Y-%m-%dT%H:%M:%S%z')}\t{sent}\t{err}\n")

        t1 = time.monotonic_ns()
        tw1 = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        lg.write(f"end\t{t1}\t{tw1}\t{sent}\terr={err}\n")
        lg.flush()

    print(f"lab2_egress sent={sent} total={total} err={err!r}", flush=True)
    return 0 if not err else 1


if __name__ == "__main__":
    sys.exit(main())
