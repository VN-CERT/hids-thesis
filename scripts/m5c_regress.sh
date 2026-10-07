#!/usr/bin/env bash
# m5c_regress.sh — buoc 2: T1/T2 (C0–C2) + T4-C1, G7, G3.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

HOOK="${1:-fentry}"
DATE=$(date +%Y%m%d)
OUTROOT="${M5C_REGRESS_OUT:-validation/m5c-${DATE}/regress-${HOOK}}"
CONTAINERS="${M5C_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"

stop_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker stop "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}

start_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker start "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}

trap start_containers EXIT

[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

stop_containers
mkdir -p out/jobs
LOG="out/jobs/m5c-regress-${HOOK}.log"
{
	echo "=== m5c regress hook=$HOOK $(date -Iseconds) ==="
	M5C_REGRESS_HOOK="$HOOK" M5C_REGRESS_MODE=step2 M5_OUTROOT="$OUTROOT" M5_RUNS=5 \
		bash scripts/m5.sh
	echo "=== G7 ==="
	HIDS_COLLECT_EXTRA="-sys-enter-hook $HOOK" bash scripts/g7.sh a 1000000
	HIDS_COLLECT_EXTRA="-sys-enter-hook $HOOK" bash scripts/g7.sh d 1000000
	HIDS_COLLECT_EXTRA="-sys-enter-hook $HOOK" bash scripts/g7.sh b-nho 1000000
	echo "=== G3 ==="
	bash scripts/g3.sh
} | tee -a "$LOG"

echo "xong regress $OUTROOT"
