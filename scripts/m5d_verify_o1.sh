#!/usr/bin/env bash
# m5d_verify_o1.sh — G7 + G3 sau O1; mau IWI/CAL.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
OUT=${M5D_VERIFY_OUT:-validation/m5d-verify}
mkdir -p "$OUT" out
LOG="$OUT/verify.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== m5d verify O1 $(date -Iseconds) ==="
echo "--- IRQ truoc G7a (10s) ---"
bash scripts/m5d_irq_sample.sh 10 "$OUT/irq.tsv"
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh a 1000000
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh b 24000000
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh b-nho 1000000
echo "--- IRQ sau G7b-nho (10s) ---"
bash scripts/m5d_irq_sample.sh 10 "$OUT/irq.tsv"
docker start qdrant >/dev/null 2>&1 || true
G3_SKIP_GIT_CHECK=1 G3_OUTROOT="$OUT/g3" bash scripts/g3.sh m5d
echo "=== verify xong ==="
