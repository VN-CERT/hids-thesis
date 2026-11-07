#!/usr/bin/env bash
# lab1c_session.sh — một phiên B/N LAB-1c (15 phút hoặc rút gọn thử)
# Env: LAB1_DAY, LAB1C_TRIAL=1 (5 phút: cửa sổ 1→4), LAB1C_SKIP_NHAN=1
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab1c_lib.sh
source scripts/lab1c_lib.sh

KIND=${1:?}   # B1-10s|N1-10s|B4|N4|B1-60s|N1-60s|B1-300s|N1-300s
LEVEL=${2:?}  # 0|D1-8|D1-16|D3-7

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab1c-$DAY"
CG_NG=$(lab1c_cgroup_nginx)
CG_PG=$(lab1c_cgroup_postgres)
COLLECT="$REPO/bin/hids-collect"
B4_MODE_FILE="$VAL/b4-mode.txt"
N4_PAYLOAD="$VAL/n4-payload.bin"

# thời lượng
TOTAL_S=900
WIN_START=180
WIN_END=780
if [[ ${LAB1C_TRIAL:-0} == 1 ]]; then
	TOTAL_S=300
	WIN_START=60
	WIN_END=240
fi
# slow overrides
case $KIND in
B1-60s|N1-60s) TOTAL_S=1800; WIN_START=120; WIN_END=1680 ;;
B1-300s|N1-300s) TOTAL_S=7200; WIN_START=120; WIN_END=7080 ;;
esac

RUN_ID="${KIND}-${LEVEL}-c-${DAY}"
if [[ ${LAB1C_TRIAL:-0} == 1 ]]; then
	RUN_ID="THU-${KIND}-${LEVEL}-c-${DAY}"
	SESS="$VAL/thu/$RUN_ID"
else
	case $KIND in
	B1-60s|N1-60s|B1-300s|N1-300s) SESS="$VAL/slow/$RUN_ID" ;;
	*) SESS="$VAL/bn/$RUN_ID" ;;
	esac
fi

# tái dùng nếu đã đạt
if [[ -f $SESS/kiem.txt ]] && grep -qx 'ok=1' "$SESS/kiem.txt"; then
	echo "TAI DUNG $RUN_ID"
	exit 0
fi

rm -rf "$SESS"
mkdir -p "$SESS/data" "$VAL/gen-logs"
lab1c_ensure_nhan
lab1c_sanitize_cpu0 >/dev/null

log() { echo "[$(date -Is)] $*" | tee -a "$SESS/session.log"; }

log "=== SESSION $RUN_ID kind=$KIND level=$LEVEL total=${TOTAL_S}s win=${WIN_START}-${WIN_END} cg_ng=$CG_NG ==="
echo "memory.max=$(cat "$CG_NG/memory.max") cpu.max=$(cat "$CG_NG/cpu.max")" | tee "$SESS/cgroup-limits.txt"

# collector
: >"$SESS/collect.log"
taskset -c 1-7 "$COLLECT" \
	-datadir "$SESS/data" \
	-cgroup "$CG_PG" -cgroup "$CG_NG" \
	-pmu sample=20 \
	>>"$SESS/collect.log" 2>&1 &
CPID=$!
echo $CPID >"$SESS/collect.pid"
READY=0
for i in $(seq 1 40); do
	if grep -qx READY "$SESS/collect.log" 2>/dev/null; then READY=1; break; fi
	if ! kill -0 "$CPID" 2>/dev/null; then break; fi
	sleep 0.5
done
if ((READY != 1)); then
	log "KHONG_READY lan1"
	kill -TERM "$CPID" 2>/dev/null || true
	wait "$CPID" 2>/dev/null || true
	sleep 1
	: >"$SESS/collect.log"
	taskset -c 1-7 "$COLLECT" \
		-datadir "$SESS/data" \
		-cgroup "$CG_PG" -cgroup "$CG_NG" \
		-pmu sample=20 \
		>>"$SESS/collect.log" 2>&1 &
	CPID=$!
	echo $CPID >"$SESS/collect.pid"
	for i in $(seq 1 40); do
		if grep -qx READY "$SESS/collect.log" 2>/dev/null; then READY=1; break; fi
		sleep 0.5
	done
fi
((READY == 1)) || { log "KHONG_READY x2"; exit 1; }
log "collector READY pid=$CPID"

# liều
LIEU_PID=""
start_lieu() {
	case $LEVEL in
	0) return 0 ;;
	D1-8)
		stress-ng --cpu 8 --taskset 0-7 --timeout "${TOTAL_S}s" >>"$SESS/lieu.log" 2>&1 &
		LIEU_PID=$!
		;;
	D1-16)
		stress-ng --cpu 16 --taskset 0-7 --timeout "${TOTAL_S}s" >>"$SESS/lieu.log" 2>&1 &
		LIEU_PID=$!
		;;
	D3-7)
		taskset -c 1-7 stress-ng --stream 7 --timeout "${TOTAL_S}s" >>"$SESS/lieu.log" 2>&1 &
		LIEU_PID=$!
		;;
	*) log "level sai $LEVEL"; exit 1 ;;
	esac
	echo "$LIEU_PID" >"$SESS/lieu.pid"
	log "lieu $LEVEL pid=$LIEU_PID"
}
start_lieu

# chờ đến cửa sổ
sleep "$WIN_START"

WIN_DUR=$((WIN_END - WIN_START))
T0=$(mono_ns)
TW0=$(date -Is)
ATTACK_PIDS=()
CYCLES=0
GHI_CHU="1.9;cgroup=nginx"
B4_MODE="stress-ng"
[[ -f $B4_MODE_FILE ]] && B4_MODE=$(cat "$B4_MODE_FILE")

start_attack() {
	case $KIND in
	B1-10s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name xcfgd-beacon --period-s 10 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	N1-10s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name nginx-healthcheck --period-s 10 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	B1-60s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name xcfgd-beacon --period-s 60 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	N1-60s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name nginx-healthcheck --period-s 60 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	B1-300s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name xcfgd-beacon --period-s 300 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	N1-300s)
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1_http_client.py" \
			--name nginx-healthcheck --period-s 300 --duration-s "$WIN_DUR" --jitter-pct 50 \
			--log "$SESS/client.log" >>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	B4)
		GHI_CHU="1.9c:${B4_MODE}"
		if [[ $B4_MODE == stress-ng ]]; then
			chay_trong_cgroup "$CG_NG" stress-ng --cpu 1 --cpu-load 10 --cpu-load-slice 2000 \
				--timeout "${WIN_DUR}s" >>"$SESS/client.stderr" 2>&1 &
			ATTACK_PIDS+=($!)
			# chu kỳ xấp xỉ: mỗi 22s
			CYCLES=$((WIN_DUR / 22))
		else
			chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1c_b4_burner.py" \
				--duration-s "$WIN_DUR" --log "$SESS/client.log" --name lab1c-b4-burner \
				>>"$SESS/client.stderr" 2>&1 &
			ATTACK_PIDS+=($!)
		fi
		;;
	N4)
		GHI_CHU="1.9c:zlib"
		[[ -f $N4_PAYLOAD ]] || { log "thieu n4 payload"; exit 1; }
		chay_trong_cgroup "$CG_NG" python3 "$REPO/scripts/lab1c_n4_zlib.py" \
			--duration-s "$WIN_DUR" --payload "$N4_PAYLOAD" --log "$SESS/client.log" \
			>>"$SESS/client.stderr" 2>&1 &
		ATTACK_PIDS+=($!)
		;;
	*) log "kind sai"; exit 1 ;;
	esac
	printf '%s\n' "${ATTACK_PIDS[@]}" | tee "$SESS/attack.pids"
	# xác nhận cgroup
	sleep 0.3
	for p in "${ATTACK_PIDS[@]}"; do
		if [[ -f /proc/$p/cgroup ]]; then
			cg=$(cat /proc/$p/cgroup)
			echo "pid=$p cgroup=$cg" | tee -a "$SESS/cgroup-check.txt"
			echo "$cg" | grep -q "$CG_NG\|docker-" || log "CANH BAO: pid $p khong trong nginx cgroup"
		fi
	done
}
start_attack
log "attack pids=${ATTACK_PIDS[*]} win_dur=$WIN_DUR"

# chờ hết cửa sổ
REMAIN=$((WIN_END - WIN_START))
sleep "$REMAIN"
T1=$(mono_ns)
TW1=$(date -Is)

# dừng attack
for p in "${ATTACK_PIDS[@]}"; do
	kill -TERM "$p" 2>/dev/null || true
done
sleep 1
for p in "${ATTACK_PIDS[@]}"; do
	kill -KILL "$p" 2>/dev/null || true
done
wait 2>/dev/null || true

# chu kỳ từ log client nếu có
if [[ -f $SESS/client.log ]]; then
	CYCLES=$(awk 'NR>1{c++} END{print c+0}' "$SESS/client.log")
fi
# B4 stress-ng: ước từ wall
if [[ $KIND == B4 && $B4_MODE == stress-ng ]]; then
	CYCLES=$((WIN_DUR / 22))
	((CYCLES < 1)) && CYCLES=1
fi

# chờ hết phiên
AFTER=$((TOTAL_S - WIN_END))
((AFTER > 0)) && sleep "$AFTER"

# tắt liều + collector
[[ -n ${LIEU_PID:-} ]] && kill -TERM "$LIEU_PID" 2>/dev/null || true
kill -TERM "$CPID" 2>/dev/null || true
for i in $(seq 1 30); do
	kill -0 "$CPID" 2>/dev/null || break
	sleep 0.5
done
kill -KILL "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true
[[ -n ${LIEU_PID:-} ]] && kill -KILL "$LIEU_PID" 2>/dev/null || true

# thu thập tid (pid chính + con từ /proc lúc chạy — dùng attack.pids + pstree snapshot nếu có)
TIDS=("${ATTACK_PIDS[@]}")
# thêm tid từ client log không có; thử children file
if [[ -f $SESS/children.pids ]]; then
	mapfile -t EXTRA <"$SESS/children.pids"
	TIDS+=("${EXTRA[@]}")
fi
# unique
TIDS_CSV=$(printf '%s\n' "${TIDS[@]}" | awk 'NF' | sort -nu | paste -sd,)

log "t0=$T0 t1=$T1 cycles=$CYCLES tids=$TIDS_CSV"

# nhãn
if [[ ${LAB1C_SKIP_NHAN:-0} != 1 ]]; then
	ID=${KIND%%-*}
	case $KIND in
	B1-*|B4) LOP=B; SONG="" ;;
	N1-*|N4) LOP=N; SONG=B1; [[ $KIND == N4 ]] && SONG=B4 ;;
	esac
	case $KIND in
	B1-10s|N1-10s) ID=${KIND:0:2} ;;
	B1-60s|N1-60s|B1-300s|N1-300s) ID=$KIND ;;
	B4) ID=B4 ;;
	N4) ID=N4 ;;
	esac
	NHIP="period=?"
	case $KIND in
	B1-10s|N1-10s) NHIP="period=10" ;;
	B1-60s|N1-60s) NHIP="period=60" ;;
	B1-300s|N1-300s) NHIP="period=300" ;;
	B4|N4) NHIP="period=22;duty=2/20" ;;
	esac
	ORACLE="cycles=${CYCLES};tids=${TIDS_CSV}"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$RUN_ID" "$LOP" "$ID" "LAB1c" "local" "$NHIP" "$LEVEL" "$SONG" \
		"$T0" "$T1" "$TW0" "$TW1" "$ORACLE" "$GHI_CHU" \
		>>"$REPO/lab/nhan-tan-cong-lab1c.tsv"
	for tid in ${TIDS_CSV//,/ }; do
		COMM=""
		[[ -f /proc/$tid/comm ]] && COMM=$(cat /proc/$tid/comm 2>/dev/null || true)
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$RUN_ID" "$ID" "$LOP" "$tid" "$T0" "$T1" "$COMM" "$tid" "$GHI_CHU" \
			>>"$REPO/lab/nhan-tid-lab1c.tsv"
	done
fi

# kiểm
set +e
python3 "$REPO/scripts/lab1c_kiem.py" \
	--sess "$SESS" --run-id "$RUN_ID" --t0 "$T0" --t1 "$T1" \
	--tids "$TIDS_CSV" --cycles "$CYCLES" \
	--pids-check "$TIDS_CSV" \
	--cgroup-substr "docker-"
KEC=$?
set -e
log "kiem exit=$KEC"
exit "$KEC"
