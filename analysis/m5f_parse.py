#!/usr/bin/env python3
"""m5f_parse.py - do kien truc su viet. KHONG SUA NOI DUNG.

Cach dung:
  python3 m5f_parse.py pgbench [--target TPS] FILE...   # log giao dich cua pgbench -l (vd: prefix.*)
  python3 m5f_parse.py wrk2    [--target RPS] FILE      # output cua wrk2 ... --latency
  them --header de in dong tieu de.

In MOT dong TSV:
  kieu  n  toc_do_per_s  lat_tb_ms  p50_ms  p99_ms  max_ms  lag_tb_ms  lag_p99_ms  loi  dat_muc  hop_ly

Quy uoc pgbench (log giao dich, moi dong):
  client_id transaction_no time script_no time_epoch time_us [schedule_lag] ...
  -> do tre = COT 3 (time, micro-giay). COT 6 (time_us) chi la phan micro-giay cua dau thoi gian,
     KHONG phai do tre. Toc do = so giao dich hoan thanh / (moc cuoi - moc dau), moc = cot5 + cot6/1e6.
Quy uoc wrk2: lay "Requests/sec", dong "Latency" (trung binh, max) va cac dong phan vi "50.000%", "99.000%".
"""
import math
import re
import sys

NAN = float("nan")
HEADER = "kieu\tn\ttoc_do_per_s\tlat_tb_ms\tp50_ms\tp99_ms\tmax_ms\tlag_tb_ms\tlag_p99_ms\tloi\tdat_muc\thop_ly"


def pct(sorted_vals, q):
    if not sorted_vals:
        return NAN
    k = max(0, math.ceil(q * len(sorted_vals)) - 1)
    return sorted_vals[k]


def mean(vals):
    return sum(vals) / len(vals) if vals else NAN


def hop_ly(m, p50, p99, mx, extra_ok=True, limit_ms=None):
    vals = [m, p50, p99, mx]
    if any(v != v for v in vals):  # NaN
        return "NGHI_NGO"
    ok = m <= mx + 1e-9 and p50 <= p99 + 1e-9 and p99 <= mx + 1e-9 and extra_ok
    if limit_ms is not None and not m < limit_ms:
        ok = False
    return "OK" if ok else "NGHI_NGO"


def dat_muc(rate, target):
    if target is None:
        return "-"
    if rate != rate or target <= 0:
        return "LECH"
    return "OK" if abs(rate - target) / target <= 0.05 else "LECH"


def f(x):
    return "nan" if x != x else f"{x:.4f}"


def do_pgbench(paths, target):
    lat, lag = [], []
    tmin = tmax = None
    total = bad = failed = 0
    for p in paths:
        with open(p, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.split()
                if not parts:
                    continue
                total += 1
                if len(parts) < 6:
                    bad += 1
                    continue
                try:
                    t = int(parts[4]) + int(parts[5]) / 1e6
                except ValueError:
                    bad += 1
                    continue
                tmin = t if tmin is None or t < tmin else tmin
                tmax = t if tmax is None or t > tmax else tmax
                if parts[2].isdigit():
                    lat.append(int(parts[2]) / 1000.0)  # cot 3: do tre giao dich (us) -> ms
                else:
                    failed += 1  # 'failed' hoac 'skipped'
                if len(parts) >= 7 and parts[6].lstrip("-").isdigit():
                    lag.append(int(parts[6]) / 1000.0)
    lat.sort()
    lag.sort()
    span = (tmax - tmin) if tmin is not None and tmax is not None else 0
    rate = len(lat) / span if span > 0 else NAN
    m, p50, p99, mx = mean(lat), pct(lat, 0.50), pct(lat, 0.99), (lat[-1] if lat else NAN)
    extra_ok = total > 0 and bad <= 0.01 * total
    print("\t".join([
        "pgbench", str(len(lat)), f(rate), f(m), f(p50), f(p99), f(mx),
        f(mean(lag)), f(pct(lag, 0.99)), f"bo_qua={bad};that_bai={failed}",
        dat_muc(rate, target), hop_ly(m, p50, p99, mx, extra_ok, limit_ms=100.0),
    ]))


UNIT = {"us": 1e-3, "ms": 1.0, "s": 1e3, "m": 6e4}


def to_ms(v, u):
    return float(v) * UNIT[u]


def do_wrk2(path, target):
    with open(path, encoding="utf-8", errors="replace") as fh:
        txt = fh.read()
    m = re.search(r"Requests/sec:\s*([\d.]+)", txt)
    rate = float(m.group(1)) if m else NAN
    m = re.search(r"^\s*Latency\s+([\d.]+)(us|ms|s|m)\s+([\d.]+)(us|ms|s|m)\s+([\d.]+)(us|ms|s|m)", txt, re.M)
    lat_m = to_ms(m.group(1), m.group(2)) if m else NAN
    lat_max = to_ms(m.group(5), m.group(6)) if m else NAN
    pcts = {float(a): to_ms(b, c) for a, b, c in re.findall(r"^\s*(\d+\.\d+)%\s+([\d.]+)(us|ms|s|m)\b", txt, re.M)}
    p50, p99 = pcts.get(50.0, NAN), pcts.get(99.0, NAN)
    m = re.search(r"(\d+) requests in", txt)
    n = int(m.group(1)) if m else -1
    non2xx = sum(int(x) for x in re.findall(r"Non-2xx or 3xx responses:\s*(\d+)", txt))
    sock = re.search(r"Socket errors:\s*(.*)", txt)
    sock_txt = sock.group(1).strip().replace(" ", "") if sock else "0"
    extra_ok = non2xx == 0 and sock is None
    print("\t".join([
        "wrk2", str(n), f(rate), f(lat_m), f(p50), f(p99), f(lat_max), "nan", "nan",
        f"non2xx={non2xx};socket={sock_txt}", dat_muc(rate, target), hop_ly(lat_m, p50, p99, lat_max, extra_ok),
    ]))


def main(argv):
    args = argv[1:]
    if "--header" in args:
        args.remove("--header")
        print(HEADER)
    target = None
    if "--target" in args:
        i = args.index("--target")
        target = float(args[i + 1])
        del args[i:i + 2]
    if len(args) < 2 or args[0] not in ("pgbench", "wrk2"):
        sys.exit(__doc__)
    if args[0] == "pgbench":
        do_pgbench(args[1:], target)
    else:
        do_wrk2(args[1], target)


if __name__ == "__main__":
    main(sys.argv)
