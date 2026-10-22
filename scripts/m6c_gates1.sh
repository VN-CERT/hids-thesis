#!/usr/bin/env bash
# M6c cong phan 1: doc lai file 56 byte cu, G7a (-pmu on/off), G7b x3, G7b-nho.
# Khong tu ket luan PASS/FAIL; chi chay va ghi so lieu nguyen van.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"

echo "=== doc lai file 56 byte cu: out/g3-S3-070928.bin ===" | tee "$OUTROOT/old56.txt"
./bin/rec-stat out/g3-S3-070928.bin >>"$OUTROOT/old56.txt" 2>&1
./bin/rec-check out/g3-S3-070928.bin >>"$OUTROOT/old56.txt" 2>&1
python3 - >>"$OUTROOT/old56.txt" <<'PY'
import struct, sys
sys.path.insert(0, 'scripts')
from bin_header import record_size_after_header
p = 'out/g3-S3-070928.bin'
with open(p, 'rb') as f:
    sz = record_size_after_header(f)
    data = f.read()
print(f"doc lap (python struct): record_size={sz} so_ban_ghi={(len(data)//sz)} byte_thua={len(data)%sz}")
PY

echo "=== G7a -pmu on ===" | tee "$OUTROOT/g7a-pmu-on.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu on" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-pmu-on.txt" 2>&1
echo "exit=$?" >>"$OUTROOT/g7a-pmu-on.txt"

echo "=== G7a -pmu off ===" | tee "$OUTROOT/g7a-pmu-off.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu off" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-pmu-off.txt" 2>&1
echo "exit=$?" >>"$OUTROOT/g7a-pmu-off.txt"

echo "=== G7b x3 (mac dinh auto = pmu on) ==="
bash scripts/m6b13_g7b.sh "$OUTROOT/g7b-x3" "-zstd-level 0" >"$OUTROOT/g7b-x3-driver.log" 2>&1
# m6b13_g7b.sh chay 5 lan; chi dung 3 lan dau cho M6c, tat ca ghi trong summary.

echo "=== G7b-nho ===" | tee "$OUTROOT/g7b-nho.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh b-nho 1000000 >>"$OUTROOT/g7b-nho.txt" 2>&1
echo "exit=$?" >>"$OUTROOT/g7b-nho.txt"

echo "gates1 xong"
