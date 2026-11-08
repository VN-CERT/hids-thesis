#!/usr/bin/env bash
# lab2_songsinh_driver.sh — 9 phien song sinh N-A2/N-B2/N-C2 × {0,D1-8,D3-7}
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab2_lib.sh
source scripts/lab2_lib.sh

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
export LAB2_VAL="$REPO/validation/lab2-song-sinh-$DAY"
VAL="$LAB2_VAL"
LOG="$VAL/driver.log"
mkdir -p "$VAL"/{gen-logs,N-A2,N-B2,N-C2,thu}

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
log "LAB-2 song-sinh driver bat dau DAY=$DAY VAL=$VAL"
lab2_sanitize_cpu0 | tee "$VAL/cpuset-effective.txt"
lab2_ensure_nhan

if ! systemctl is-active hids-lab2ss-gen >/dev/null 2>&1; then
	: >"$VAL/gen-systemd.log"
	systemd-run --unit=hids-lab2ss-gen --collect \
		--property=Restart=always --property=RestartSec=5 \
		--property=WorkingDirectory="$REPO" \
		--property=StandardOutput=append:"$VAL/gen-systemd.log" \
		--property=StandardError=append:"$VAL/gen-systemd.log" \
		/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$VAL/gen-logs"
	log "bat hids-lab2ss-gen"
fi

run_one() {
	local lop=$1 level=$2
	local attempt=1 max=2
	while ((attempt <= max)); do
		log "phien $lop $level attempt=$attempt"
		if LAB1_DAY="$DAY" LAB2_VAL="$VAL" bash "$REPO/scripts/lab2_songsinh_session.sh" "$lop" "$level"; then
			log "DAT $lop $level"
			return 0
		fi
		log "FAIL $lop $level attempt=$attempt"
		rm -f "$VAL/${lop}/${lop}-${level}-c-${DAY}/kiem.txt"
		attempt=$((attempt + 1))
	done
	echo "FAIL ${lop}-${level}-c-${DAY} sau $max lan" | tee "$VAL/driver-loi.txt"
	exit 1
}

for LOP in N-A2 N-B2 N-C2; do
	for L in 0 D1-8 D3-7; do
		run_one "$LOP" "$L"
	done
done

systemctl stop hids-lab2ss-gen 2>/dev/null || true
echo "driver xong $(date -Is)" | tee "$VAL/driver-xong.txt"
log "DRIVER XONG"
exit 0
