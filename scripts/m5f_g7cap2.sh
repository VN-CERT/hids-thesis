#!/usr/bin/env bash
# G7-cap một mức: 2 tiến trình, zstd mặc định, 60 giây (M5f bước 2).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh
COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj
OUT="${G7_CAP_OUT:-validation/m5f-$(date +%Y%m%d)/step2/g7-cap}"
DURATION=${G7_CAP_DURATION:-60}
RINGMB=64
N_PER_PROC=${G7_CAP_N:-200000000}
mkdir -p "$OUT"

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "g7-cap2: collector khong READY" >&2
	exit 1
}

nproc=${G7_CAP_NPROC:-2}
mode=zstd-default
ts=$(date +%Y%m%d-%H%M%S)
prefix="$OUT/${mode}-p${nproc}-${ts}"
bin="$prefix.bin"
fifo="$prefix.fifo"
log="$prefix-collect.log"
echo "=== G7-cap2 nproc=$nproc zstd-default duration=${DURATION}s ==="
mkfifo "$fifo"
exec 9<>"$fifo"
pids=()
for ((i = 0; i < nproc; i++)); do
	"$SYSINJ" -n "$N_PER_PROC" <"$fifo" >"$prefix-sysinj-$i.log" 2>&1 &
	pids+=($!)
done
sleep 0.5
pid_args=()
for p in "${pids[@]}"; do pid_args+=(-pid "$p"); done
# shellcheck disable=SC2086
"$COLLECT" "${pid_args[@]}" -ringbuf-mb "$RINGMB" -duration 120s -out "$bin" 2>"$log" &
coll_pid=$!
wait_ready "$log"
stress-ng --cpu 24 --timeout 3600s >"$prefix-stress.log" 2>&1 &
stress_pid=$!
sleep 1
t0=$(date +%s.%N)
printf '%*s' "$nproc" '' >&9
exec 9>&-
sleep "$DURATION"
t1=$(date +%s.%N)
for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
kill -INT "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true
kill -INT "$coll_pid" 2>/dev/null
wait "$coll_pid" 2>/dev/null || true
rm -f "$fifo"
recs=$(sed -n 's/.*ban ghi doc duoc: \([0-9]*\).*/\1/p' "$log" | tail -1)
mat=$(sed -n 's/.*mat: \([0-9]*\).*/\1/p' "$log" | tail -1)
echo "recs=${recs:-0} mat=${mat:-0}"
[[ ${mat:-1} == 0 ]] || exit 1
hids_drop_out_bin "$bin" 2>/dev/null || rm -f "$bin"
