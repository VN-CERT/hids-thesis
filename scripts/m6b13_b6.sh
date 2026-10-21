#!/usr/bin/env bash
# m6b13_b6.sh <outdir> — M6b-1.3 B6: nhieu giua bpftrace va collector tren cung
# tracepoint sched. Chi chay kich ban S3 (wl mixed 2000 3000 500), 3 cau hinh x 3 lan:
#   a: bpftrace TOI GIAN gan TRUOC collector
#   b: bpftrace TOI GIAN gan SAU collector (cho READY)
#   c: bpftrace MO RONG (nhanh preempt + in tung su kien W/S/P), collector truoc
# Script tu dung tat ca container dang chay va khoi dong lai khi xong (ke ca khi loi).
# Khong sua tieu chi/cog nao; chi do lech rq collector so voi bpftrace.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/hids_data_policy.sh

OUTROOT="${1:?outdir}"
COLLECT=./bin/hids-collect
RECCHK=./bin/rec-check
WL=./bin/wl
G3WIN=./scripts/g3_window.py
WL_CPU=20
mkdir -p "$OUTROOT" out
exec > >(tee -a "$OUTROOT/b6-run.log") 2>&1

die() { echo "m6b13_b6: $*" >&2; exit 1; }

hids_require_clean_git || die "cay git khong sach — commit truoc khi chay"
[[ $EUID -eq 0 ]] || die "can chay bang root"
for f in "$COLLECT" "$RECCHK" "$WL" "$G3WIN"; do [[ -e $f ]] || die "khong thay $f"; done
command -v bpftrace >/dev/null || die "khong co bpftrace"

echo "=== m6b13_b6 start=$(date -Is) outdir=$OUTROOT ==="
git rev-parse --short HEAD
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py
n=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
echo "bpftool_hids_count_truoc=$n"
[[ "$n" == "0" ]] || die "con chuong trinh hids_"
pgrep -a hids-collect && die "con collector" || echo "khong co collector"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "container dang chay truoc: ${RUNNING[*]}"
restart_containers() {
	if [[ ${#RUNNING[@]} -gt 0 ]]; then
		docker start "${RUNNING[@]}" >/dev/null 2>&1 || echo "LOI khoi dong lai container"
		echo "container dang chay sau: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
	fi
}
trap restart_containers EXIT
if [[ ${#RUNNING[@]} -gt 0 ]]; then
	docker stop "${RUNNING[@]}" || die "docker stop loi"
fi
echo "container con chay khi do: $(docker ps --format '{{.Names}}' | wc -l)"

BT_MIN='tracepoint:sched:sched_wakeup /args->pid == $1 && @w == 0/ { @w = nsecs; } tracepoint:sched:sched_switch { $now = nsecs; if (args->next_pid == $1 && @w != 0) { @rq_sau_wakeup_ns = sum($now - @w); @so_lan = count(); @w = 0; } }'
BT_EXT='tracepoint:sched:sched_wakeup /args->pid == $1/ { $now = nsecs; printf("W %lu %d %d\n", $now, cpu, args->target_cpu); if (@w == 0) { @w = $now; } } tracepoint:sched:sched_switch { $now = nsecs; if (args->prev_pid == $1 && args->prev_state == 0) { printf("P %lu %d\n", $now, cpu); @p = $now; } if (args->next_pid == $1) { printf("S %lu %d\n", $now, cpu); $d = 0; if (@w != 0) { $d = $d + ($now - @w); @rq_sau_wakeup_ns = sum($now - @w); @so_lan = count(); @w = 0; } if (@p != 0) { $d = $d + ($now - @p); @rq_sau_preempt_ns = sum($now - @p); @so_lan_preempt = count(); @p = 0; } if ($d > 0) { @rq_tong_ns = sum($d); } } }'

wait_bt_attach() {
	local log=$1 i
	for ((i = 0; i < 600; i++)); do
		grep -q Attaching "$log" 2>/dev/null && return 0
		sleep 0.05
	done
	die "bpftrace khong in Attaching, xem $log"
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong in READY, xem $log"
}

wait_wl_on_read() {
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	die "pid $pid khong cho tren read() sau 120 giay"
}

run_once() {
	local cfg=$1 rep=$2
	local ts prefix bin fifo wl_pid cpid bt_pid rundir
	ts=$(date +%H%M%S)
	prefix="out/m6b13-b6-$cfg$rep-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	rundir="$OUTROOT/$cfg$rep"
	mkdir -p "$rundir"
	echo "=== B6 cau hinh $cfg lan $rep (prefix $prefix) ==="

	mkfifo "$fifo" || die "fifo $fifo"
	exec 9<>"$fifo"
	taskset -c "$WL_CPU" "$WL" mixed 2000 3000 500 <"$fifo" >"$prefix-wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	local tid=$wl_pid
	echo "wl pid=$wl_pid tid=$tid" | tee "$rundir/ketqua.txt"

	bt_pid=0
	cpid=0
	start_collector() {
		"$COLLECT" -pid "$wl_pid" -zstd-level 0 -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		wait_ready "$prefix-collect.log"
	}
	start_bpftrace() {
		local prog=$1
		bpftrace -e "$prog" "$tid" >"$prefix-bpftrace.log" 2>&1 &
		bt_pid=$!
		wait_bt_attach "$prefix-bpftrace.log"
	}

	case "$cfg" in
	a)
		echo "thu tu: bpftrace toi gian TRUOC, collector SAU" | tee -a "$rundir/ketqua.txt"
		start_bpftrace "$BT_MIN"
		start_collector
		;;
	b)
		echo "thu tu: collector TRUOC (READY), bpftrace toi gian SAU" | tee -a "$rundir/ketqua.txt"
		start_collector
		start_bpftrace "$BT_MIN"
		;;
	c)
		echo "thu tu: collector TRUOC (READY), bpftrace mo rong + su kien SAU" | tee -a "$rundir/ketqua.txt"
		start_collector
		start_bpftrace "$BT_EXT"
		;;
	*) die "cau hinh khong hop le: $cfg" ;;
	esac

	printf '.' >&9
	wait_wl_on_read "$wl_pid"
	printf '.' >&9
	wait_wl_on_read "$wl_pid"

	kill -INT "$bt_pid" 2>/dev/null
	wait "$bt_pid" 2>/dev/null || true
	kill -INT "$cpid" 2>/dev/null
	wait "$cpid" 2>/dev/null
	printf '.' >&9
	exec 9>&-
	wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"

	local n_after
	n_after=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
	echo "bpftool_hids_count_sau=$n_after" | tee -a "$rundir/ketqua.txt"

	local bt_rq bt_lan
	bt_rq=$(grep '^@rq_sau_wakeup_ns:' "$prefix-bpftrace.log" | tail -1 | awk '{print $NF}')
	bt_lan=$(grep '^@so_lan:' "$prefix-bpftrace.log" | tail -1 | awk '{print $NF}')

	local t_from t_to
	t_from=$(python3 "$G3WIN" "$bin" "$tid" | head -1) || die "khong tim cua so (from)"
	t_to=$(python3 "$G3WIN" "$bin" "$tid" | tail -1) || die "khong tim cua so (to)"
	echo "cua so ts_enter: ($t_from, $t_to]" | tee -a "$rundir/ketqua.txt"
	"$RECCHK" -tid "$tid" -from-mono "$t_from" -to-mono "$t_to" "$bin" >"$rundir/rec-check.txt" 2>&1
	local coll_rq
	coll_rq=$(awk '/^rq /{print $2; exit}' "$rundir/rec-check.txt")

	{
		echo "collector_rq_ns=${coll_rq:-?}"
		echo "bpftrace_rq_sau_wakeup_ns=${bt_rq:-?}"
		echo "bpftrace_so_lan_wakeup=${bt_lan:-?}"
		if [[ -n ${coll_rq:-} && -n ${bt_rq:-} && -n ${bt_lan:-} && $bt_lan -gt 0 && $bt_rq -gt 0 ]]; then
			awk -v c="$coll_rq" -v b="$bt_rq" -v n="$bt_lan" 'BEGIN{
				d = c - b;
				printf "lech_ns=%d\n", d;
				printf "lech_phan_tram=%.4f\n", d / b * 100;
				printf "lech_us_moi_wakeup=%.4f\n", d / n / 1000;
			}'
		fi
	} | tee -a "$rundir/ketqua.txt"

	cp "$prefix-bpftrace.log" "$rundir/bpftrace.log"
	echo "bin: $bin" | tee -a "$rundir/ketqua.txt"
	echo "xong B6 $cfg lan $rep"
}

for cfg in a b c; do
	for rep in 1 2 3; do
		run_once "$cfg" "$rep"
	done
done

echo "=== bang tong B6 ==="
{
	printf '%-6s %-4s %-18s %-18s %-10s %-12s %s\n' "cfg" "lan" "collector_rq" "bpftrace_rq" "so_wakeup" "lech_%" "lech_us/wakeup"
	for cfg in a b c; do
		for rep in 1 2 3; do
			k="$OUTROOT/$cfg$rep/ketqua.txt"
			[[ -f $k ]] || continue
			c=$(grep '^collector_rq_ns=' "$k" | cut -d= -f2)
			b=$(grep '^bpftrace_rq_sau_wakeup_ns=' "$k" | cut -d= -f2)
			n=$(grep '^bpftrace_so_lan_wakeup=' "$k" | cut -d= -f2)
			p=$(grep '^lech_phan_tram=' "$k" | cut -d= -f2)
			u=$(grep '^lech_us_moi_wakeup=' "$k" | cut -d= -f2)
			printf '%-6s %-4s %-18s %-18s %-10s %-12s %s\n' "$cfg" "$rep" "${c:-?}" "${b:-?}" "${n:-?}" "${p:-?}" "${u:-?}"
		done
	done
} | tee "$OUTROOT/b6-summary.txt"

trap - EXIT
restart_containers
echo "=== m6b13_b6 xong $(date -Is) ==="
