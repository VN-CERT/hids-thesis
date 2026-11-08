#!/usr/bin/env bash
# lab2_session.sh — mot phien LAB-2 (15 phut hoac thu 5 phut)
# Args: <lop> <level>   lop=A2|B2|C2|N   level=0|D1-8|D3-7
# Env: LAB1_DAY, LAB2_TRIAL=1, LAB2_SKIP_NHAN=1
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=scripts/lab2_lib.sh
source scripts/lab2_lib.sh

LOP=${1:?}    # A2|B2|C2|N
LEVEL=${2:?}  # 0|D1-8|D3-7

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab2-$DAY"
CG_NG=$(lab2_cgroup_nginx)
CG_PG=$(lab2_cgroup_postgres)
COLLECT="$REPO/bin/hids-collect"
IMPLANT="$VAL/implant/implant-lab2"
EGRESS_PORT_ATK="${LAB2_EGRESS_PORT_ATK:-18080}"
EGRESS_PORT_BEN="${LAB2_EGRESS_PORT_BEN:-18081}"
SSH_USER="${LAB2_SSH_USER:-lab2victim}"
WORDLIST="$VAL/wordlist-200.txt"
SSH_TARGET_FILE="$VAL/ssh-target.txt"

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
((READY == 1)) || { log "KHONG_READY"; exit 1; }
log "collector READY pid=$CPID"

# lieu
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
*) log "level sai $LEVEL"; exit 1 ;;
esac
[[ -n $LIEU_PID ]] && echo "$LIEU_PID" >"$SESS/lieu.pid" && log "lieu $LEVEL pid=$LIEU_PID"

sleep "$WIN_START"
WIN_DUR=$((WIN_END - WIN_START))
T0=$(mono_ns)
TW0=$(date -Is)
ATTACK_PIDS=()
ORACLE=0
ORACLE_REF=-1
GHI_CHU="2.1;cgroup=nginx"
CONG_CU="local"
NHIP=""

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
A2)
	[[ -x $IMPLANT || -f $IMPLANT ]] || { log "thieu implant $IMPLANT"; exit 1; }
	chmod +x "$IMPLANT" || true
	# wrapper tick 1s + implant con — moc ±1s (beacon thua ~60s khong du)
	start_bg "$SESS/main.pid" bash "$REPO/scripts/lab2_a2_wrap.sh" \
		"$IMPLANT" "$SESS/a2-tick.log"
	NHIP="sliver-beacon;seconds=60;jitter=30s"
	CONG_CU="sliver-implant"
	GHI_CHU="2.1;A2;cgroup=nginx;chi_beacon;wrap_tick_1s;khong_hau_khai_thac"
	sleep "$WIN_DUR"
	ORACLE=$(python3 -c "print(max(1, int($WIN_DUR/60)))")
	if [[ -f $SESS/beacon-count.txt ]]; then
		ORACLE=$(cat "$SESS/beacon-count.txt")
	fi
	# implant pid that (neu co)
	if [[ -f $SESS/a2-tick.log.implant_pid ]]; then
		IP=$(cat "$SESS/a2-tick.log.implant_pid")
		ATTACK_PIDS+=("$IP")
		# unique
		mapfile -t ATTACK_PIDS < <(printf '%s\n' "${ATTACK_PIDS[@]}" | awk 'NF && !s[$0]++')
	fi
	;;
B2|N)
	PAY="$VAL/egress-payload.bin"
	if [[ ! -f $PAY ]]; then
		dd if=/dev/urandom of="$PAY" bs=1M count=25 status=none
	fi
	PORT=$EGRESS_PORT_ATK
	NAME=lab2-egress-atk
	[[ $LOP == N ]] && PORT=$EGRESS_PORT_BEN && NAME=lab2-egress-backup
	TONG=25MB
	# thu: giam tong
	[[ ${LAB2_TRIAL:-0} == 1 ]] && TONG=2MB
	start_bg "$SESS/main.pid" python3 "$REPO/scripts/lab2_egress.py" \
		--dich "192.168.77.20:${PORT}" --tong "$TONG" --toc-do 50KBps \
		--payload "$PAY" --log "$SESS/client.log" --name "$NAME"
	NHIP="egress;50KBps;tong=$TONG"
	CONG_CU="lab2_egress.py"
	GHI_CHU="2.1;${LOP};cgroup=nginx;dich=192.168.77.20:${PORT}"
	# cho process xong hoac het cua so
	MAIN=$(cat "$SESS/main.pid")
	DEADLINE=$((WIN_DUR + 30))
	for ((i = 0; i < DEADLINE; i++)); do
		kill -0 "$MAIN" 2>/dev/null || break
		sleep 1
	done
	# doc bytes tu log
	ORACLE=$(awk -F'\t' '$1=="end"{print $4; exit}' "$SESS/client.log" 2>/dev/null || echo 0)
	ORACLE_REF=$ORACLE
	;;
C2)
	[[ -f $WORDLIST ]] || { log "thieu wordlist"; exit 1; }
	start_bg "$SESS/main.pid" python3 "$REPO/scripts/lab2_sshbrute.py" \
		--dich 192.168.77.20 --user "$SSH_USER" --wordlist "$WORDLIST" \
		--cach-quang 5 --log "$SESS/client.log"
	NHIP="sshbrute;cach=5s;port=22022"
	CONG_CU="lab2_sshbrute.py"
	GHI_CHU="2.1;C2;cgroup=nginx;dich=192.168.77.20:22022"
	MAIN=$(cat "$SESS/main.pid")
	DEADLINE=$((WIN_DUR + 30))
	for ((i = 0; i < DEADLINE; i++)); do
		kill -0 "$MAIN" 2>/dev/null || break
		sleep 1
	done
	ORACLE=$(awk -F'\t' 'BEGIN{n=0} $1+0>0{n=$1} END{print n+0}' "$SESS/client.log" 2>/dev/null || echo 0)
	;;
*) log "lop sai $LOP"; exit 1 ;;
esac

TW1=$(date -Is)
# T1 khi van con chay (wrap tick / egress) roi moi kill — moc last ±1s
T1=$(mono_ns)

# dung tan cong
for p in "${ATTACK_PIDS[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
sleep 2
for p in "${ATTACK_PIDS[@]}"; do kill -KILL "$p" 2>/dev/null || true; done
printf '%s\n' "${ATTACK_PIDS[@]}" >"$SESS/attack.pids"

# A2: cap nhat descendants lan cuoi tu proc neu con
if [[ $LOP == A2 && -s $SESS/main.pid ]]; then
	MAIN=$(cat "$SESS/main.pid")
	if kill -0 "$MAIN" 2>/dev/null; then
		mapfile -t ATTACK_PIDS < <(lab2_descendants "$MAIN")
		printf '%s\n' "${ATTACK_PIDS[@]}" >"$SESS/attack.pids"
	fi
fi

# phan con lai den TOTAL
ELAPSED=$((WIN_END))
# sleep them neu can (tu sau WIN_END den TOTAL - da dung het WIN_DUR sau WIN_START)
REST=$((TOTAL_S - WIN_END))
((REST > 0)) && sleep "$REST" || true

# dung lieu + collector
[[ -n $LIEU_PID ]] && kill -TERM "$LIEU_PID" 2>/dev/null || true
kill -TERM "$CPID" 2>/dev/null || true
sleep 5
kill -KILL "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true
[[ -n $LIEU_PID ]] && kill -KILL "$LIEU_PID" 2>/dev/null || true

# nhan
TIDS_CSV=$(IFS=,; echo "${ATTACK_PIDS[*]}")
ID_COL="$LOP"
SONG=""
[[ $LOP == N ]] && SONG="B2"
[[ $LOP == B2 ]] && SONG="N"

if [[ ${LAB2_SKIP_NHAN:-0} != 1 ]]; then
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$RUN_ID" "$LOP" "$ID_COL" "LAB2" "$CONG_CU" "$NHIP" "$LEVEL" "$SONG" \
		"$T0" "$T1" "$TW0" "$TW1" "oracle=$ORACLE;tids=$TIDS_CSV" "$GHI_CHU" \
		>>"$REPO/lab/nhan-tan-cong-lab2.tsv"
	for p in "${ATTACK_PIDS[@]}"; do
		COMM=""
		[[ -r /proc/$p/comm ]] && COMM=$(tr -d '\0' </proc/$p/comm || true)
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$RUN_ID" "$ID_COL" "$LOP" "$p" "$T0" "$T1" "$COMM" "$p" "$GHI_CHU" \
			>>"$REPO/lab/nhan-tid-lab2.tsv"
	done
fi

# kiem
MIN_RECS=50
RELAX=()
if [[ ${LAB2_TRIAL:-0} == 1 ]]; then
	MIN_RECS=20
	RELAX=(--relax-moc)
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
