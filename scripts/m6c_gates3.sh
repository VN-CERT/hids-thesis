#!/usr/bin/env bash
# M6c cong phan 3: G8, G9a, G9b, G10 nhu R030 (dung m6b1_gate.sh + m6b1_pre24h.sh).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"

echo "=== m6b1_gate.sh (G7a, G3, G8, G9a, G10, host) ==="
M6B1_OUT="$OUTROOT/gate" bash scripts/m6b1_gate.sh >"$OUTROOT/gate-driver.log" 2>&1
echo "gate_exit=$?"

echo "=== m6b1_pre24h.sh (G7b-nho, G3, G9b, host 10 phut) ==="
M6B1_OUT="$OUTROOT/pre24h" bash scripts/m6b1_pre24h.sh >"$OUTROOT/pre24h-driver.log" 2>&1
echo "pre24h_exit=$?"

echo "gates3 xong"
