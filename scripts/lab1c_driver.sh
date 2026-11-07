#!/usr/bin/env bash
# lab1c_driver.sh — 16 phiên BN + 4 slow; B4/N4 theo 1.9c
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab1c_lib.sh
source scripts/lab1c_lib.sh

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab1c-$DAY"
LOG="$VAL/driver.log"
mkdir -p "$VAL" "$VAL/bn" "$VAL/slow" "$VAL/gen-logs" "$VAL/thu"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }
trap_err() {
	local ec=$? line=${1:-?} cmd=${2:-?}
	{
		echo "ERR exit=$ec line=$line"
		echo "cmd=$cmd"
		echo "time=$(date -Is)"
	} | tee "$VAL/driver-loi.txt" | tee -a "$LOG"
	systemctl stop hids-lab1c-gen 2>/dev/null || true
	exit "$ec"
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

{
	echo ""
	echo "=== LAB1C DRIVER START $(date -Is) DAY=$DAY ==="
} >>"$LOG"

lab1c_sanitize_cpu0 | tee "$VAL/cpuset-effective.txt"
lab1c_ensure_nhan

docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true
for i in $(seq 1 30); do
	curl -sf -o /dev/null http://127.0.0.1:18080/file4k.bin && break
	sleep 1
done

# generator một lần cho cả đêm
if ! systemctl is-active hids-lab1c-gen >/dev/null 2>&1; then
	: >"$VAL/gen-systemd.log"
	systemd-run --unit=hids-lab1c-gen --collect \
		--property=Restart=always --property=RestartSec=5 \
		--property=WorkingDirectory="$REPO" \
		--property=StandardOutput=append:"$VAL/gen-systemd.log" \
		--property=StandardError=append:"$VAL/gen-systemd.log" \
		/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$VAL/gen-logs"
	log "hids-lab1c-gen started"
fi

# --- hiệu chuẩn B4 (1.9c) ---
if [[ ! -f $VAL/b4-mode.txt ]]; then
	log "hieu chuan B4 stress-ng duty"
	rm -f /tmp/lab1c-b4-cal.log
	stress-ng --cpu 1 --cpu-load 10 --cpu-load-slice 2000 --timeout 70s >/tmp/lab1c-b4-cal.log 2>&1 &
	SP=$!
	sleep 2
	# tìm worker
	WP=$(pgrep -P "$SP" | head -1 || true)
	[[ -z ${WP:-} ]] && WP=$SP
	U0=$(awk '{print $14}' /proc/"$WP"/stat 2>/dev/null || echo 0)
	sleep 66
	U1=$(awk '{print $14}' /proc/"$WP"/stat 2>/dev/null || echo 0)
	HZ=$(getconf CLK_TCK)
	UT=$(python3 -c "print( ($U1-$U0)/float($HZ) )")
	kill -TERM "$SP" 2>/dev/null || true
	wait "$SP" 2>/dev/null || true
	echo "b4_utime_s=$UT worker=$WP" | tee "$VAL/b4-cal.txt"
	# kỳ vọng 6–7 s CPU trong 66 s
	OK=$(python3 -c "u=float('$UT'); print(1 if 5.0<=u<=8.5 else 0)")
	if [[ $OK == 1 ]]; then
		echo stress-ng >"$VAL/b4-mode.txt"
		log "B4 dung stress-ng (utime=${UT}s)"
	else
		echo burner >"$VAL/b4-mode.txt"
		log "B4 dung burner (utime=${UT}s khong dat 6-7)"
	fi
fi

# --- hiệu chuẩn N4 payload ---
if [[ ! -f $VAL/n4-payload.bin ]]; then
	log "hieu chuan N4 zlib payload ~2s"
	VAL="$VAL" python3 - <<'PY' | tee "$VAL/n4-cal.txt"
import os, time, zlib
val = os.environ["VAL"]
target = (1.8, 2.2)
best = None
prev = None
for mb in [4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80]:
    raw = os.urandom(mb * 1024 * 1024)
    t0 = time.perf_counter()
    zlib.compress(raw, 6)
    dt = time.perf_counter() - t0
    print(f"mb={mb} compress_s={dt:.3f}")
    if target[0] <= dt <= target[1]:
        best = (mb, raw, dt)
        break
    if dt < target[0]:
        prev = (mb, raw, dt)
    elif dt > target[1]:
        best = prev if prev is not None else (mb, raw, dt)
        break
if best is None:
    best = prev if prev is not None else (32, os.urandom(32*1024*1024), 0.0)
mb, raw, dt = best
path = os.path.join(val, "n4-payload.bin")
open(path, "wb").write(raw)
print(f"payload_path={path} bytes={len(raw)} compress_s={dt:.3f}")
PY
fi

run_one() {
	local kind=$1 level=$2
	local rid="${kind}-${level}-c-${DAY}"
	local sess
	case $kind in
	B1-60s|N1-60s|B1-300s|N1-300s) sess="$VAL/slow/$rid" ;;
	*) sess="$VAL/bn/$rid" ;;
	esac
	if [[ -f $sess/kiem.txt ]] && grep -qx 'ok=1' "$sess/kiem.txt"; then
		log "TAI DUNG $rid"
		return 0
	fi
	local attempt=1
	while ((attempt <= 2)); do
		log "chay $rid attempt=$attempt"
		set +e
		LAB1_DAY="$DAY" bash "$REPO/scripts/lab1c_session.sh" "$kind" "$level"
		ec=$?
		set -e
		if ((ec == 0)); then
			log "DAT $rid"
			return 0
		fi
		log "KHONG_DAT $rid attempt=$attempt"
		attempt=$((attempt + 1))
	done
	echo "FAIL $rid sau 2 lan" | tee "$VAL/driver-loi.txt"
	exit 1
}

# bước 3: L=0 rồi D1-8, D1-16, D3-7
for L in 0 D1-8 D1-16 D3-7; do
	for K in B1-10s N1-10s B4 N4; do
		run_one "$K" "$L"
	done
done

# bước 4: slow mức 0
for K in B1-60s N1-60s B1-300s N1-300s; do
	run_one "$K" 0
done

systemctl stop hids-lab1c-gen 2>/dev/null || true
echo "driver xong $(date -Is)" | tee "$VAL/driver-xong.txt"
log "DRIVER XONG"
exit 0
