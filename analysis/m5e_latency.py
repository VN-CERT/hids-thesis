#!/usr/bin/env python3
"""Do tre tu pgbench --log hoac hey -o csv; kiem hop ly; khong dung tom tat cong cu."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def _pct(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        raise ValueError("empty")
    i = int(p * (len(sorted_vals) - 1))
    return sorted_vals[i]


def pgbench_lats_ms(path: Path) -> list[float]:
    lats: list[float] = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "|" in line:
            parts = line.split("|")
            if len(parts) >= 4:
                try:
                    lats.append(float(parts[3]) / 1000.0)  # us -> ms
                except ValueError:
                    pass
        else:
            parts = line.split()
            if len(parts) >= 4 and parts[0].isdigit():
                try:
                    lats.append(float(parts[3]) / 1000.0)
                except ValueError:
                    pass
    return lats


def hey_lats_ms(path: Path) -> list[float]:
    lats: list[float] = []
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("HTTP") or line.startswith("response"):
            continue
        cols = line.split(",")
        if len(cols) >= 5:
            try:
                lats.append(float(cols[4]) * 1000.0)  # s -> ms
            except ValueError:
                pass
    return lats


def summarize(lats_ms: list[float], duration_s: float = 60.0) -> dict:
    if not lats_ms:
        return {
            "n": 0,
            "rate_per_s": 0.0,
            "avg_ms": "",
            "p50_ms": "",
            "p99_ms": "",
            "max_ms": "",
            "sanity_ok": False,
            "sanity_msg": "khong co mau",
        }
    s = sorted(lats_ms)
    avg = sum(s) / len(s)
    p50 = _pct(s, 0.50)
    p99 = _pct(s, 0.99)
    mx = s[-1]
    ok = avg <= mx and p50 <= p99 <= mx
    msg = "ok" if ok else f"vi pham: avg={avg} max={mx} p50={p50} p99={p99}"
    return {
        "n": len(s),
        "rate_per_s": len(s) / duration_s,
        "avg_ms": avg,
        "p50_ms": p50,
        "p99_ms": p99,
        "max_ms": mx,
        "sanity_ok": ok,
        "sanity_msg": msg,
    }


def main() -> None:
    if len(sys.argv) < 3:
        print("cach dung: m5e_latency.py <pgbench|hey> <file> [duration_s]", file=sys.stderr)
        sys.exit(2)
    kind, path = sys.argv[1], Path(sys.argv[2])
    dur = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
    if kind == "pgbench":
        lats = pgbench_lats_ms(path)
    elif kind == "hey":
        lats = hey_lats_ms(path)
    else:
        sys.exit(2)
    out = summarize(lats, dur)
    print(json.dumps(out, ensure_ascii=False))
    if not out["sanity_ok"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
