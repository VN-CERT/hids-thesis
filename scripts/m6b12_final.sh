#!/usr/bin/env bash
# m6b12_final.sh — cong cuoi M6b-1.2: G7b(24x1M, zstd0, mat=0), pre24h
# (G7a, G7b-nho, G3, G9b, host10m), gate (G8, G9a, G10, host-stats), 1 gio 24h.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/hids_data_policy.sh

OUTROOT="${M6B12_OUT:-validation/m6b12-20261020/final}"
mkdir -p "$OUTROOT" out/jobs
exec > >(tee -a "$OUTROOT/final.log") 2>&1

echo "=== m6b12_final bat dau $(date -Is) ==="
[[ $EUID -eq 0 ]] || { echo "can root"; exit 1; }
hids_require_clean_git || { echo "cay git khong sach"; exit 1; }
git rev-parse --short HEAD | tee "$OUTROOT/git-head.txt"
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py | tee "$OUTROOT/architect-sha256.txt"
n=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
echo "bpftool_hids_count=$n"
[[ "$n" == "0" ]] || { echo "DUNG: con chuong trinh hids_"; exit 1; }
if pgrep -a hids-collect; then echo "DUNG: con collector"; exit 1; fi
echo "khong co collector nao dang chay"

echo "=== G7b (24 x 1.000.000, -zstd-level 0, -rb-poll mac dinh 200ms) start=$(date -Is) ==="
HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh b 1000000 2>&1 | tee "$OUTROOT/g7b-z0.txt"
g7b_mat=$(grep -E 'tong bo dem mat' "$OUTROOT/g7b-z0.txt" | tail -1 | awk '{print $NF}' || true)
echo "G7b mat=${g7b_mat:-?} (can = 0)"
[[ "${g7b_mat:-999}" == "0" ]] && echo "PASS: G7b mat=0" || echo "FAIL: G7b mat=${g7b_mat:-?}"

echo "=== pre24h (G7a, G7b-nho, G3, G9b, host10m) start=$(date -Is) ==="
PRE24H_RC=0
M6B1_PRE24H_OUT="$OUTROOT/pre24h" bash scripts/m6b1_pre24h.sh || PRE24H_RC=$?
echo "pre24h_exit=$PRE24H_RC"

echo "=== gate (G7a, G3, G8, G9a, G10, host-stats) start=$(date -Is) ==="
GATE_RC=0
M6B1_OUT="$OUTROOT/gate" bash scripts/m6b1_gate.sh || GATE_RC=$?
echo "gate_exit=$GATE_RC"

echo "--- sau gate: bpftool prog show | grep -c hids_ ---"
bpftool prog show 2>/dev/null | grep -c hids_ || true

echo "=== chay 1 gio cau hinh 24h start=$(date -Is) ==="
bash scripts/m6b11_1h.sh "$OUTROOT/run1h" || echo "run1h_exit=$?"
echo "=== m6b12_final xong $(date -Is) pre24h_exit=$PRE24H_RC gate_exit=$GATE_RC ==="
echo "pre24h_exit=$PRE24H_RC gate_exit=$GATE_RC" > "$OUTROOT/final.status"
