#!/usr/bin/env bash
# lab2_driver.sh — 9 phien LAB-2 pha 1 (A2/B2/C2 × 0/D1-8/D3-7)
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab2_lib.sh
source scripts/lab2_lib.sh

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab2-$DAY"
LOG="$VAL/driver.log"
mkdir -p "$VAL/gen-logs" "$VAL/A2" "$VAL/B2" "$VAL/C2" "$VAL/N"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }
trap_err() {
	local ec=$? line=${1:-?} cmd=${2:-?}
	{
		echo "ERR exit=$ec line=$line cmd=$cmd time=$(date -Is)"
	} | tee "$VAL/driver-loi.txt" | tee -a "$LOG"
	exit "$ec"
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

: >"$LOG"
log "LAB-2 driver bat dau DAY=$DAY"
lab2_sanitize_cpu0 | tee "$VAL/cpuset-effective.txt"
lab2_ensure_nhan

# generator mot lan
if ! systemctl is-active hids-lab2-gen >/dev/null 2>&1; then
	: >"$VAL/gen-systemd.log"
	systemd-run --unit=hids-lab2-gen --collect \
		--property=Restart=always --property=RestartSec=5 \
		--property=WorkingDirectory="$REPO" \
		--property=StandardOutput=append:"$VAL/gen-systemd.log" \
		--property=StandardError=append:"$VAL/gen-systemd.log" \
		/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$VAL/gen-logs"
	log "bat hids-lab2-gen"
fi

run_one() {
	local lop=$1 level=$2
	local attempt=1
	local max=2
	while ((attempt <= max)); do
		log "phien $lop $level attempt=$attempt"
		if LAB1_DAY="$DAY" bash "$REPO/scripts/lab2_session.sh" "$lop" "$level"; then
			log "DAT $lop $level"
			return 0
		fi
		log "FAIL $lop $level attempt=$attempt"
		# xoa kiem de cho phep chay lai
		rm -f "$VAL/${lop}/${lop}-${level}-c-${DAY}/kiem.txt"
		attempt=$((attempt + 1))
	done
	echo "FAIL ${lop}-${level}-c-${DAY} sau $max lan" | tee "$VAL/driver-loi.txt"
	exit 1
}

# thu tu: moi lop xong 3 muc, A2 roi B2 roi C2
for LOP in A2 B2 C2; do
	for L in 0 D1-8 D3-7; do
		run_one "$LOP" "$L"
	done
done

# tat generator
systemctl stop hids-lab2-gen 2>/dev/null || true
echo "driver xong $(date -Is)" | tee "$VAL/driver-xong.txt"
log "DRIVER XONG"
exit 0
