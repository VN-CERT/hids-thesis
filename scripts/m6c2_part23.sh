#!/usr/bin/env bash
# M6c-2 phan 2+3: freq_stamp CPU 12/20 (may ranh), G7a x1, G3 x1 sau khi sua
# STEALCHECK theo tong. Container dung trong luc do, khoi dong lai khi xong.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"
mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
cleanup() { docker start "${RUNNING[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true

echo "=== freq_stamp CPU 12 ===" | tee "$OUTROOT/freq-12.txt"
bash scripts/freq_stamp.sh 12 2>&1 | tee -a "$OUTROOT/freq-12.txt"
echo "=== freq_stamp CPU 20 ===" | tee "$OUTROOT/freq-20.txt"
bash scripts/freq_stamp.sh 20 2>&1 | tee -a "$OUTROOT/freq-20.txt"

echo "=== G7a x1 (binary sau sua STEALCHECK) ===" | tee "$OUTROOT/g7a.txt"
bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a.txt" 2>&1
echo "g7a exit=$?" >>"$OUTROOT/g7a.txt"

cleanup
trap - EXIT

echo "=== G3 x1 (m6b12_g3.sh stop, tu dung/khoi dong container) ==="
bash scripts/m6b12_g3.sh stop "$OUTROOT/g3" || echo "g3 exit=$?"
echo "part23 xong"
