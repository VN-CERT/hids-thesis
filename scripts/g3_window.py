#!/usr/bin/env python3
"""Tim cua so (ts read lan 2, ts read lan 3] cho mot tid trong file .bin."""
import struct
import sys
from pathlib import Path

# scripts/ on sys.path when invoked as python3 scripts/g3_window.py
sys.path.insert(0, str(Path(__file__).resolve().parent))
from bin_header import skip_header  # noqa: E402

GETUID_NR = 102
READ_NR = 0


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: g3_window.py <file.bin> <tid>", file=sys.stderr)
        sys.exit(2)
    path, tid_s = sys.argv[1], sys.argv[2]
    tid = int(tid_s)

    with open(path, "rb") as f:
        rec_size = skip_header(f)
        recs: list[tuple[int, int]] = []
        while True:
            b = f.read(rec_size)
            if len(b) < rec_size:
                break
            ts = struct.unpack_from("<Q", b, 0)[0]
            t = struct.unpack_from("<I", b, 16)[0]
            nr = struct.unpack_from("<H", b, 24)[0]
            if t == tid:
                recs.append((ts, nr))

    recs.sort()
    idx = next((i for i, r in enumerate(recs) if r[1] == GETUID_NR), None)
    if idx is None:
        print("khong tim thay getuid cho tid", tid, file=sys.stderr)
        sys.exit(1)
    reads = [r for r in recs[idx + 1 :] if r[1] == READ_NR]
    if len(reads) < 2:
        print("khong du hai syscall read sau getuid:", len(reads), file=sys.stderr)
        sys.exit(1)
    print(reads[0][0])
    print(reads[-1][0])


if __name__ == "__main__":
    main()
