#!/usr/bin/env bash
# lab2_songsinh_session.sh — mot phien song sinh N-A2/N-B2/N-C2
# Args: <lop> <level>   lop=N-A2|N-B2|N-C2   level=0|D1-8|D3-7
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab2_lib.sh
source scripts/lab2_lib.sh

LOP=${1:?}
LEVEL=${2:?}

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="${LAB2_VAL:-$REPO/validation/lab2-song-sinh-$DAY}"
CG_NG=$(lab2_cgroup_nginx)
CG_PG=$(lab2_cgroup_postgres)
COLLECT="$REPO/bin/hids-collect"
EGRESS_PORT_BEN="${LAB2_EGRESS_PORT_BEN:-18081}"
HC_URL_PORT="${LAB2_HC_PORT:-18081}"
SSH_USER="${LAB2_SSH_USER:-lab2victim}"
SSH_PASS=""
if [[ -f ${LAB2_SSH_TARGET:-$REPO/validation/lab2-20261108/ssh-target.txt} ]]; then
	SSH_PASS=$(awk -F= '/^password=/{print $2}' "${LAB2_SSH_TARGET:-$REPO/validation/lab2-20261108/ssh-target.txt}")
fi
[[ -n $SSH_PASS ]] || SSH_PASS="${LAB2_SSH_PASS:-Lab2Victim!2026}"

TOTAL_S=900
WIN_START=180
WIN_END=780
if [[ ${LAB2_TRIAL:-0} == 1 ]]; then
	TOTAL_S=300
	WIN_START=60
	WIN_END=240
fi

RUN_ID="${LOP}-${LEVEL}-c-${DAY}"
if [[ ${LAB2_TRIAL:-0} == 1 ]]; then
	RUN_ID="THU-${LOP}-${LEVEL}-c-${DAY}"
	SESS="$VAL/thu/$RUN_ID"
else
	SESS="$VAL/${LOP}/$RUN_ID"
fi

if [[ -f $SESS/kiem.txt ]] && grep -qx 'ok=1' "$SESS/kiem.txt"; then
	echo "TAI DUNG $RUN_ID"
	exit 0
fi

rm -rf "$SESS"
mkdir -p "$SESS/data" "$VAL/gen-logs"
lab2_ensure_nhan
lab2_sanitize_cpu0 | tee "$SESS/cpuset-effective.txt" >/dev/null

log() { echo "[$(date -Is)] $*" | tee -a "$SESS/session.log"; }
log "=== SESSION $RUN_ID lop=$LOP level=$LEVEL total=${TOTAL_S}s win=${WIN_START}-${WIN_END} ==="

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
((READY == 1)) || { log "KHONG_READY"; exit 1; }
log "collector READY pid=$CPID"

LIEU_PID=""
case $LEVEL in
0) ;;
D1-8)
	stress-ng --cpu 8 --taskset 0-7 --timeout "${TOTAL_S}s" >>"$SESS/lieu.log" 2>&1 &
	LIEU_PID=$!
	;;
D3-7)
	taskset -c 1-7 stress-ng --stream 7 --timeout "${TOTAL_S}s" >>"$SESS/lieu.log" 2>&1 &
	LIEU_PID=$!
	;;
*) log "level sai"; exit 1 ;;
esac
[[ -n $LIEU_PID ]] && echo "$LIEU_PID" >"$SESS/lieu.pid" && log "lieu $LEVEL pid=$LIEU_PID"

sleep "$WIN_START"
WIN_DUR=$((WIN_END - WIN_START))
T0=$(mono_ns)
TW0=$(date -Is)
ATTACK_PIDS=()
ORACLE=0
ORACLE_REF=-1
# nhãn: lop cot = N (twin); id = N-A2/...
LOP_COL=N
ID_COL="$LOP"
GHI_CHU="song sinh pha 2;2.2;cgroup=nginx"
CONG_CU="local"
NHIP=""

# tai-nen sampler
TOMTAT="$VAL/tai-nen-tomtat.tsv"
python3 "$REPO/scripts/lab2_tai_nen_sample.py" \
	--sess "$SESS" --run-id "$RUN_ID" --lop "$LOP" --muc "$LEVEL" \
	--cg-nginx "$CG_NG" --cg-postgres "$CG_PG" \
	--duration-s "$WIN_DUR" --interval-s 10 \
	--tomtat "$TOMTAT" \
	>>"$SESS/tai-nen-sample.log" 2>&1 &
TAI_NEN_PID=$!
echo "$TAI_NEN_PID" >"$SESS/tai-nen.pid"

start_bg() {
	local pf=$1
	shift
	chay_trong_cgroup_bg "$CG_NG" "$pf" "$@" >>"$SESS/client.stderr" 2>&1
	local real
	real=$(cat "$pf")
	ATTACK_PIDS+=("$real")
	sleep 0.3
	local c
	for c in $(lab2_descendants "$real"); do
		[[ $c == "$real" ]] && continue
		ATTACK_PIDS+=("$c")
	done
}

case $LOP in
N-A2)
	# GET lành tới 18081 (8080 Sliver trả 404 — quyet dinh dung backup HTTP)
	start_bg "$SESS/main.pid" python3 "$REPO/scripts/lab2_healthcheck.py" \
		--dich "192.168.77.20:${HC_URL_PORT}" --period-s 60 --jitter-s 30 \
		--duration-s "$WIN_DUR" --log "$SESS/client.log"
	NHIP="healthcheck;period=60;jitter=30;port=${HC_URL_PORT}"
	CONG_CU="lab2_healthcheck.py"
	sleep "$WIN_DUR"
	ORACLE=$(awk -F'\t' 'BEGIN{n=0} $1+0>0{n=$1} END{print n+0}' "$SESS/client.log" 2>/dev/null || echo 0)
	;;
N-B2)
	PAY="$VAL/egress-payload.bin"
	if [[ ! -f $PAY ]]; then
		# tai dung payload pha 1 neu co
		if [[ -f $REPO/validation/lab2-20261108/egress-payload.bin ]]; then
			cp -a "$REPO/validation/lab2-20261108/egress-payload.bin" "$PAY"
		else
			dd if=/dev/urandom of="$PAY" bs=1M count=25 status=none
		fi
	fi
	TONG=25MB
	[[ ${LAB2_TRIAL:-0} == 1 ]] && TONG=2MB
	start_bg "$SESS/main.pid" python3 "$REPO/scripts/lab2_egress.py" \
		--dich "192.168.77.20:${EGRESS_PORT_BEN}" --tong "$TONG" --toc-do 50KBps \
		--payload "$PAY" --log "$SESS/client.log" --name lab2-egress-backup
	NHIP="egress-backup;50KBps;tong=$TONG;port=${EGRESS_PORT_BEN}"
	CONG_CU="lab2_egress.py"
	MAIN=$(cat "$SESS/main.pid")
	for ((i = 0; i < WIN_DUR + 30; i++)); do
		kill -0 "$MAIN" 2>/dev/null || break
		sleep 1
	done
	ORACLE=$(awk -F'\t' '$1=="end"{print $4; exit}' "$SESS/client.log" 2>/dev/null || echo 0)
	ORACLE_REF=$ORACLE
	[[ ${LAB2_TRIAL:-0} != 1 ]] && ORACLE_REF=26214400
	;;
N-C2)
	start_bg "$SESS/main.pid" python3 "$REPO/scripts/lab2_sshlogin.py" \
		--dich 192.168.77.20 --user "$SSH_USER" --password "$SSH_PASS" \
		--cach-quang 5 --duration-s "$WIN_DUR" --log "$SESS/client.log"
	NHIP="sshlogin;cach=5s;port=22022"
	CONG_CU="lab2_sshlogin.py"
	MAIN=$(cat "$SESS/main.pid")
	for ((i = 0; i < WIN_DUR + 30; i++)); do
		kill -0 "$MAIN" 2>/dev/null || break
		sleep 1
	done
	ORACLE=$(awk -F'\t' 'BEGIN{n=0} $1+0>0 && $4=="1"{n++} END{print n+0}' "$SESS/client.log" 2>/dev/null || echo 0)
	# neu dem ok that bai, dung so lan thu
	if [[ ${ORACLE:-0} -lt 1 ]]; then
		ORACLE=$(awk -F'\t' 'BEGIN{n=0} $1+0>0{n=$1} END{print n+0}' "$SESS/client.log" 2>/dev/null || echo 0)
	fi
	;;
*) log "lop sai $LOP"; exit 1 ;;
esac

TW1=$(date -Is)
T1=$(mono_ns)

for p in "${ATTACK_PIDS[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
sleep 2
for p in "${ATTACK_PIDS[@]}"; do kill -KILL "$p" 2>/dev/null || true; done
printf '%s\n' "${ATTACK_PIDS[@]}" >"$SESS/attack.pids"

[[ -n ${TAI_NEN_PID:-} ]] && wait "$TAI_NEN_PID" 2>/dev/null || true

REST=$((TOTAL_S - WIN_END))
((REST > 0)) && sleep "$REST" || true

[[ -n $LIEU_PID ]] && kill -TERM "$LIEU_PID" 2>/dev/null || true
kill -TERM "$CPID" 2>/dev/null || true
sleep 5
kill -KILL "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true
[[ -n $LIEU_PID ]] && kill -KILL "$LIEU_PID" 2>/dev/null || true

TIDS_CSV=$(IFS=,; echo "${ATTACK_PIDS[*]}")

if [[ ${LAB2_SKIP_NHAN:-0} != 1 ]]; then
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$RUN_ID" "$LOP_COL" "$ID_COL" "LAB2" "$CONG_CU" "$NHIP" "$LEVEL" "" \
		"$T0" "$T1" "$TW0" "$TW1" "oracle=$ORACLE;tids=$TIDS_CSV" "$GHI_CHU" \
		>>"$REPO/lab/nhan-tan-cong-lab2.tsv"
	for p in "${ATTACK_PIDS[@]}"; do
		COMM=""
		[[ -r /proc/$p/comm ]] && COMM=$(tr -d '\0' </proc/$p/comm || true)
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$RUN_ID" "$ID_COL" "$LOP_COL" "$p" "$T0" "$T1" "$COMM" "$p" "$GHI_CHU" \
			>>"$REPO/lab/nhan-tid-lab2.tsv"
	done
fi

MIN_RECS=50
RELAX=()
if [[ ${LAB2_TRIAL:-0} == 1 ]]; then
	MIN_RECS=20
	RELAX=(--relax-moc)
fi
# N-B2 trial: oracle_ref = actual
if [[ $LOP == N-B2 && ${LAB2_TRIAL:-0} == 1 ]]; then
	ORACLE_REF=$ORACLE
fi

python3 "$REPO/scripts/lab2_kiem.py" \
	--sess "$SESS" --run-id "$RUN_ID" --lop "$LOP" \
	--t0 "$T0" --t1 "$T1" --tids "$TIDS_CSV" \
	--oracle "$ORACLE" --oracle-ref "$ORACLE_REF" \
	--min-recs "$MIN_RECS" --pids-check "$TIDS_CSV" \
	"${RELAX[@]}" | tee "$SESS/kiem-run.txt"
grep -qx 'ok=1' "$SESS/kiem.txt"
log "SESSION $RUN_ID DAT"
exit 0
