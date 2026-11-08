#!/usr/bin/env python3
"""LAB-2 N-C2 — SSH login HỢP LỆ lặp (benign song sinh bruteforce).
Đích cố định 192.168.77.20:22022; mật khẩu đúng mỗi lần; chạy `true` rồi thoát.
"""
from __future__ import annotations

import argparse
import socket
import sys
import time

import paramiko

ALLOWED_HOST = "192.168.77.20"
ALLOWED_PORT = 22022


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dich", default=ALLOWED_HOST)
    ap.add_argument("--port", type=int, default=ALLOWED_PORT)
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--cach-quang", type=float, default=5.0)
    ap.add_argument("--duration-s", type=float, required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--timeout", type=float, default=8.0)
    args = ap.parse_args()

    if args.dich != ALLOWED_HOST:
        raise SystemExit(f"dich chi duoc {ALLOWED_HOST}")
    if args.port != ALLOWED_PORT:
        raise SystemExit(f"port chi duoc {ALLOWED_PORT}")

    t_end = time.monotonic() + args.duration_s
    n_ok = 0
    n = 0
    with open(args.log, "w") as lg:
        lg.write("n\tmono_ns\twall\tok\tdetail\n")
        while time.monotonic() < t_end:
            n += 1
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
                    password=args.password,
                    timeout=args.timeout,
                    allow_agent=False,
                    look_for_keys=False,
                    banner_timeout=args.timeout,
                    auth_timeout=args.timeout,
                )
                _stdin, stdout, stderr = client.exec_command("true", timeout=args.timeout)
                _ = stdout.channel.recv_exit_status()
                ok = 1
                n_ok += 1
                detail = "login_ok"
            except paramiko.AuthenticationException:
                detail = "auth_fail"
            except (socket.error, paramiko.SSHException, OSError) as e:
                detail = f"err:{type(e).__name__}"
            finally:
                try:
                    client.close()
                except Exception:
                    pass
            lg.write(f"{n}\t{t0}\t{tw}\t{ok}\t{detail}\n")
            lg.flush()
            print(f"login={n} ok={ok} detail={detail}", flush=True)
            remain = t_end - time.monotonic()
            if remain <= 0:
                break
            time.sleep(min(args.cach_quang, remain))
        lg.write(f"# summary tries={n} success={n_ok}\n")
    print(f"lab2_sshlogin tries={n} success={n_ok}", flush=True)
    return 0 if n_ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
