#!/usr/bin/env python3
"""Nhan egress LAB-2 tren 202 — ghi moc + so byte vao log.
Chay tren 202: python3 lab2_egress_recv.py --port 18080 --log /root/lab/egress-recv.log
"""
from __future__ import annotations

import argparse
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=18080)
    ap.add_argument("--log", default="/root/lab/egress-recv.log")
    ap.add_argument("--bind", default="192.168.77.20")
    args = ap.parse_args()

    logf = open(args.log, "a", buffering=1)
    logf.write(f"# start {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
               f"bind={args.bind}:{args.port}\n")

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", "0"))
            got = 0
            while got < n:
                chunk = self.rfile.read(min(65536, n - got))
                if not chunk:
                    break
                got += len(chunk)
            ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            mono = time.monotonic_ns()
            logf.write(f"{ts}\t{mono}\tPOST\t{self.path}\tbytes={got}\t"
                       f"from={self.client_address[0]}\n")
            self.send_response(204)
            self.end_headers()

        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"lab2-egress-recv ok\n")

        def log_message(self, fmt, *a):
            return

    httpd = ThreadingHTTPServer((args.bind, args.port), H)
    print(f"listening {args.bind}:{args.port} log={args.log}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
