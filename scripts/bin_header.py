"""Doc header file .bin hids-collect; tra ve kich thuoc ban ghi (48 hoac 56)."""

from __future__ import annotations

import sys
from typing import BinaryIO

LEGACY = 48
CURRENT = 56


def record_size_after_header(f: BinaryIO) -> int:
    rec = LEGACY
    while True:
        line = f.readline()
        if not line:
            raise SystemExit("khong tim thay #END trong header")
        if line.strip() == b"#END":
            return rec
        if line.startswith(b"# record_size:"):
            try:
                rec = int(line.split(b":", 1)[1].strip())
            except ValueError:
                print("record_size khong hop le trong header", file=sys.stderr)
                raise SystemExit(1)
            if rec not in (LEGACY, CURRENT):
                print(f"record_size {rec}: chi ho tro {LEGACY} hoac {CURRENT}", file=sys.stderr)
                raise SystemExit(1)


def skip_header(f: BinaryIO) -> int:
    """Doc header tu vi tri hien tai; tra ve record_size."""
    return record_size_after_header(f)
