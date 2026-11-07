#!/usr/bin/env bash
# lab1c_nenphu.sh — 2.5 giờ nền chu kỳ lành (1.9b + N4=zlib theo 1.9c)
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab1c_lib.sh
source scripts/lab1c_lib.sh

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab1c-$DAY"
SESS="$VAL/nen-phu"
LOG="$VAL/nenphu.log"
mkdir -p "$SESS/data" "$VAL/gen-logs"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }
trap_err() {
	local ec=$? line=${1:-?} cmd=${2:-?}
	{
		echo "ERR exit=$ec line=$line cmd=$cmd time=$(date -Is)"
	} | tee "$VAL/nenphu-loi.txt" | tee -a "$LOG"
	exit "$ec"
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

: >"$LOG"
log "nenphu: cho hids-lab1c-driver neu dang chay"
while systemctl is-active hids-lab1c-driver >/dev/null 2>&1; do
	log "driver active — cho 60s"
	sleep 60
done
log "bat dau nen-phu $(date -Is)"

lab1c_sanitize_cpu0 | tee "$SESS/cpuset-effective.txt"
lab1c_ensure_nhan
CG_NG=$(lab1c_cgroup_nginx)
CG_PG=$(lab1c_cgroup_postgres)
N4_PAYLOAD="$VAL/n4-payload.bin"
[[ -f $N4_PAYLOAD ]] || { log "thieu n4-payload (driver chua hieu chuan?)"; exit 1; }

docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true
# generator
if ! systemctl is-active hids-lab1c-gen >/dev/null 2>&1; then
	: >"$VAL/gen-systemd.log"
	systemd-run --unit=hids-lab1c-gen --collect \
		--property=Restart=always --property=RestartSec=5 \
		--property=WorkingDirectory="$REPO" \
		--property=StandardOutput=append:"$VAL/gen-systemd.log" \
		--property=StandardError=append:"$VAL/gen-systemd.log" \
		/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$VAL/gen-logs"
fi

: >"$SESS/collect.log"
taskset -c 1-7 "$REPO/bin/hids-collect" \
	-datadir "$SESS/data" \
	-cgroup "$CG_PG" -cgroup "$CG_NG" \
	-pmu sample=20 \
	>>"$SESS/collect.log" 2>&1 &
CPID=$!
echo $CPID >"$SESS/collect.pid"
for i in $(seq 1 40); do
	grep -qx READY "$SESS/collect.log" 2>/dev/null && break
	sleep 0.5
done
grep -qx READY "$SESS/collect.log" || { log "KHONG_READY"; exit 1; }
log "collector READY"

sleep 60
T0=$(mono_ns)
TW0=$(date -Is)
PIDS=()

# 3 poller + 1 zlib (1.9c) — pid thật qua pidfile
start_bg() {
	local pf=$1
	shift
	chay_trong_cgroup_bg "$CG_NG" "$pf" "$@"
	PIDS+=("$(cat "$pf")")
}
start_bg "$SESS/p10.pid" python3 "$REPO/scripts/lab1_http_client.py" \
	--name nginx-healthcheck --period-s 10 --duration-s 8880 --jitter-pct 0 \
	--log "$SESS/p10.log" >>"$SESS/p10.stderr" 2>&1
start_bg "$SESS/p60.pid" python3 "$REPO/scripts/lab1_http_client.py" \
	--name nginx-healthcheck --period-s 60 --duration-s 8880 --jitter-pct 0 \
	--log "$SESS/p60.log" >>"$SESS/p60.stderr" 2>&1
start_bg "$SESS/p300.pid" python3 "$REPO/scripts/lab1_http_client.py" \
	--name nginx-healthcheck --period-s 300 --duration-s 8880 --jitter-pct 0 \
	--log "$SESS/p300.log" >>"$SESS/p300.stderr" 2>&1
start_bg "$SESS/n4.pid" python3 "$REPO/scripts/lab1c_n4_zlib.py" \
	--duration-s 8880 --payload "$N4_PAYLOAD" --log "$SESS/n4.log" \
	--name lab1c-n4-zlib >>"$SESS/n4.stderr" 2>&1
printf '%s\n' "${PIDS[@]}" | tee "$SESS/attack.pids"
log "pids=${PIDS[*]}"
for p in "${PIDS[@]}"; do
	echo "pid=$p $(cat /proc/$p/cgroup 2>/dev/null | head -1)" | tee -a "$SESS/cgroup-check.txt"
done

# 148 phút = 8880 s từ sau READY+60 → tổng ~150 phút từ READY
sleep 8880
T1=$(mono_ns)
TW1=$(date -Is)

for p in "${PIDS[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
sleep 2
for p in "${PIDS[@]}"; do kill -KILL "$p" 2>/dev/null || true; done

# phút 150: dừng collector (đã gần hết 8880+60)
kill -TERM "$CPID" 2>/dev/null || true
sleep 5
kill -KILL "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true

# nhãn 4 id
declare -a IDS=(N1-10s-nen N1-60s-nen N1-300s-nen N4-nen)
declare -a LOGS=(p10.log p60.log p300.log n4.log)
for i in 0 1 2 3; do
	id=${IDS[$i]}
	lg=$SESS/${LOGS[$i]}
	cyc=$(awk 'NR>1{c++} END{print c+0}' "$lg" 2>/dev/null || echo 0)
	pid=${PIDS[$i]}
	rid="${id}-c-${DAY}"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$rid" "N" "$id" "LAB1c" "local" "nen-phu" "0" "" \
		"$T0" "$T1" "$TW0" "$TW1" "cycles=$cyc;pid=$pid" "nen-phu, dung de huan luyen;1.9c" \
		>>"$REPO/lab/nhan-tan-cong-lab1c.tsv"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$rid" "$id" "N" "$pid" "$T0" "$T1" "" "$pid" "nen-phu, dung de huan luyen" \
		>>"$REPO/lab/nhan-tid-lab1c.tsv"
	# kiểm từng id
	python3 "$REPO/scripts/lab1c_kiem.py" \
		--sess "$SESS" --run-id "$rid" --t0 "$T0" --t1 "$T1" \
		--tids "$pid" --cycles "$cyc" --pids-check "$pid" \
		>"$SESS/kiem-${id}.txt" || true
	# copy ok line
	grep -E '^ok=' "$SESS/kiem-${id}.txt" | tee -a "$SESS/kiem-summary.txt" || true
done

# tổng: mọi id phải ok=1
if grep -q 'ok=0' "$SESS/kiem-"*.txt 2>/dev/null; then
	echo "nenphu FAIL" | tee "$VAL/nenphu-loi.txt"
	exit 1
fi
echo "nenphu xong $(date -Is)" | tee "$VAL/nenphu-xong.txt"
log "NENPHU XONG"
exit 0
