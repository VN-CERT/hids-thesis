#!/usr/bin/env bash
# G7-cap: cong suat collector (mat=0), khong thay G7b.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj
DATE=$(date +%Y%m%d)
OUT="${G7_CAP_OUT:-validation/m5d-${DATE}/g7-cap}"
DURATION=${G7_CAP_DURATION:-60}
RINGMB=64
N_PER_PROC=${G7_CAP_N:-200000000}
STRESS=1

die() { echo "g7-cap: $*" >&2; exit 1; }

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong READY: $log"
}

collect_cpu_from_log() {
	awk -F'[:,]' '/thoi gian chay:.*CPU collector/{gsub(/[^0-9.]/,"",$2); u=$2; gsub(/[^0-9.]/,"",$3); s=$3; print u+0, s+0}' "$1" | tail -1
}

run_level() {
	local mode=$1 nproc=$2 zstd_flag=$3
	local ts prefix bin fifo log coll_pid stress_pid
	ts=$(date +%Y%m%d-%H%M%S)
	prefix="$OUT/${mode}-p${nproc}-${ts}"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	log="$prefix-collect.log"

	echo "=== G7-cap mode=$mode nproc=$nproc zstd=$zstd_flag duration=${DURATION}s ring=${RINGMB}MiB ==="
	mkfifo "$fifo"
	exec 9<>"$fifo"
	local -a pids=()
	local i
	for ((i = 0; i < nproc; i++)); do
		"$SYSINJ" -n "$N_PER_PROC" <"$fifo" >"$prefix-sysinj-$i.log" 2>&1 &
		pids+=($!)
	done
	sleep 0.5
	local -a pid_args=()
	for p in "${pids[@]}"; do pid_args+=(-pid "$p"); done
	# shellcheck disable=SC2086
	"$COLLECT" "${pid_args[@]}" -ringbuf-mb "$RINGMB" -duration 120s ${zstd_flag} -out "$bin" 2>"$log" &
	coll_pid=$!
	wait_ready "$log"
	stress_pid=""
	if [[ $STRESS -eq 1 ]]; then
		stress-ng --cpu 24 --timeout 3600s >"$prefix-stress.log" 2>&1 &
		stress_pid=$!
		sleep 1
	fi
	local t0 t1
	t0=$(date +%s.%N)
	printf '%*s' "$nproc" '' >&9
	exec 9>&-
	sleep "$DURATION"
	t1=$(date +%s.%N)
	for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
	for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
	[[ -n $stress_pid ]] && kill -INT "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true
	kill -INT "$coll_pid" 2>/dev/null
	wait "$coll_pid" 2>/dev/null || true
	rm -f "$fifo"

	local recs mat elapsed rate loss_pct u_cpu s_cpu
	recs=$(sed -n 's/.*ban ghi doc duoc: \([0-9]*\).*/\1/p' "$log" | tail -1)
	mat=$(sed -n 's/.*mat: \([0-9]*\).*/\1/p' "$log" | tail -1)
	[[ -z ${recs:-} ]] && recs=0
	[[ -z ${mat:-} ]] && mat=0
	elapsed=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')
	rate=$(awk -v r="$recs" -v e="$elapsed" 'BEGIN{if(e>0) printf "%.0f", r/e; else print 0}')
	loss_pct=$(awk -v m="$mat" -v r="$recs" 'BEGIN{t=m+r; if(t>0) printf "%.4f", 100*m/t; else print 0}')
	read -r u_cpu s_cpu < <(collect_cpu_from_log "$log" || echo "0 0")

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$mode" "$nproc" "$zstd_flag" "$recs" "$mat" "$rate" "$loss_pct" "$u_cpu" "$s_cpu" "$elapsed" \
		>>"$OUT/summary.tsv"
	echo "  recs=$recs mat=$mat rate=${rate}/s loss=${loss_pct}% cpu_user=${u_cpu}s cpu_sys=${s_cpu}s elapsed=$elapsed"
	hids_drop_out_bin "$bin" 2>/dev/null || rm -f "$bin"
}

# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh
mkdir -p "$OUT"
echo -e "mode\tnproc\tzstd_flag\trecords\tlost\trate_per_s\tloss_pct\tcpu_user_s\tcpu_sys_s\telapsed_s" >"$OUT/summary.tsv"

for mode in zstd-default zstd0; do
	case $mode in
	zstd-default) zf="" ;;
	zstd0) zf="-zstd-level 0" ;;
	esac
	for nproc in 1 2 4 8 16 24; do
		run_level "$mode" "$nproc" "$zf"
	done
done

echo "=== toc do cao nhat mat=0 theo luot ==="
for mode in zstd-default zstd0; do
	awk -F'\t' -v m="$mode" '$1==m && $5==0 {print}' "$OUT/summary.tsv" | sort -t$'\t' -k6 -nr | head -1 \
		| awk -F'\t' '{printf "%s: max_rate=%s/s nproc=%s recs=%s\n", $1, $6, $2, $4}'
done
echo "luu $OUT/summary.tsv"
