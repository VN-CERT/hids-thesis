#!/usr/bin/env python3
"""Tim cua so (ts read lan 2, ts read lan 3] cho mot tid trong file .bin."""
import struct
import sys

GETUID_NR = 102
READ_NR = 0


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: g3_window.py <file.bin> <tid>", file=sys.stderr)
        sys.exit(2)
    path, tid_s = sys.argv[1], sys.argv[2]
    tid = int(tid_s)

    with open(path, "rb") as f:
        while True:
            line = f.readline()
            if not line:
                sys.exit("khong tim thay #END trong header")
            if line.strip() == b"#END":
                break
        recs: list[tuple[int, int]] = []
        while True:
            b = f.read(48)
            if len(b) < 48:
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
    print(reads[1][0])


if __name__ == "__main__":
    main()
