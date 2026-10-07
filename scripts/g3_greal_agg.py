#!/usr/bin/env python3
"""Tong hop G-real: collector theo tid + cua so mono, top 10 thread."""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bin_header import skip_header


def sum_records(path: Path, tids: set[int], t0: int, t1: int) -> dict[int, dict]:
    out = {t: {"cpu": 0, "steal": 0, "irq": 0, "rq": 0, "vol": 0, "n": 0} for t in tids}
    with path.open("rb") as f:
        rec_size = skip_header(f)
        while True:
            b = f.read(rec_size)
            if len(b) < rec_size:
                break
            ts = struct.unpack_from("<Q", b, 0)[0]
            if ts <= t0 or ts > t1:
                continue
            tid = struct.unpack_from("<I", b, 16)[0]
            if tid not in tids:
                continue
            s = out[tid]
            s["cpu"] += struct.unpack_from("<I", b, 28)[0]
            s["steal"] += struct.unpack_from("<I", b, 32)[0]
            s["irq"] += struct.unpack_from("<I", b, 36)[0]
            s["rq"] += struct.unpack_from("<I", b, 40)[0]
            s["vol"] += struct.unpack_from("<I", b, 44)[0] * 1000
            s["n"] += 1
    return out


def main() -> None:
    if len(sys.argv) != 5:
        print("usage: g3_greal_agg.py <bin> <tids.csv> <t0> <t1>", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    tids = {int(x) for x in sys.argv[2].split(",") if x}
    t0, t1 = int(sys.argv[3]), int(sys.argv[4])
    sums = sum_records(path, tids, t0, t1)
    tot = {"cpu": 0, "steal": 0, "irq": 0, "rq": 0, "vol": 0, "n": 0}
    for s in sums.values():
        for k in tot:
            tot[k] += s[k]
    csi = tot["cpu"] + tot["steal"] + tot["irq"]
    all5 = csi + tot["rq"] + tot["vol"]
    print(f"collector_cpu_steal_irq_ns {csi}")
    print(f"collector_rq_ns {tot['rq']}")
    print(f"collector_vol_ns {tot['vol']}")
    print(f"collector_tong_5_ns {all5}")
    print(f"collector_ban_ghi {tot['n']}")
    ranked = sorted(
        sums.items(),
        key=lambda kv: kv[1]["cpu"] + kv[1]["steal"] + kv[1]["irq"],
        reverse=True,
    )
    print("top10_tid cpu_steal_irq_ns rq_ns vol_ns ban_ghi")
    for tid, s in ranked[:10]:
        c = s["cpu"] + s["steal"] + s["irq"]
        print(f"{tid} {c} {s['rq']} {s['vol']} {s['n']}")


if __name__ == "__main__":
    main()
