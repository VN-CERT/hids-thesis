#!/usr/bin/env bash
# m6b1_gate.sh — cong kiem M6b-1: G7a zstd0, G3 S1-S5, G8, G9, G10, host-stats 10 phut.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

OUTROOT="${M6B1_OUT:-validation/m6b1-$(date +%Y%m%d)}"
mkdir -p "$OUTROOT"
LOG="$OUTROOT/gate.log"
exec > >(tee -a "$LOG") 2>&1

die() { echo "m6b1_gate: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 600; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

wait_perf_fd() {
	local pid=$1 i
	for ((i = 0; i < 3000; i++)); do
		if ls -l "/proc/$pid/fd" 2>/dev/null | grep -q 'perf_event'; then
			return 0
		fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	return 1
}

[[ $EUID -eq 0 ]] || die "can root"
hids_require_clean_git || die "cay git khong sach"
[[ -x ./bin/hids-collect ]] || die "chay make build truoc"

if [[ ${M6B1_SKIP_G7A:-} == 1 ]]; then
	echo "=== G7a bo qua (M6B1_SKIP_G7A=1) ==="
else
	echo "=== G7a zstd-level 0 ==="
	HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh a 1000000 2>&1 | tee "$OUTROOT/g7a-z0.txt"
	g7a_mat=$(grep -E 'tong bo dem mat' "$OUTROOT/g7a-z0.txt" | tail -1 | awk '{print $NF}' || true)
	g7a_mat=${g7a_mat:-999}
	[[ "$g7a_mat" == 0 ]] && pass "G7a mat=0" || fail "G7a mat=$g7a_mat"
fi

if [[ ${M6B1_SKIP_G3:-} == 1 ]]; then
	echo "=== G3 bo qua (M6B1_SKIP_G3=1) ==="
else
	echo "=== G3 S1-S5 (subset g3.sh) ==="
	G3_OUTROOT="$OUTROOT/g3" bash scripts/g3.sh 2>&1 | tee "$OUTROOT/g3.log" || fail "g3.sh loi"
fi

echo "=== G8 proc vs perf ==="
CG8=/sys/fs/cgroup/hids-test8
rmdir "$CG8" 2>/dev/null || true
mkdir -p "$CG8"
cleanup_g8() {
	rmdir "$CG8" 2>/dev/null || true
}

g8_workload() {
	# Subshell: khong chuyen ca script gate vao cgroup.
	bash -c 'echo $$ >"$1/cgroup.procs"; for _ in $(seq 1 500); do /bin/true; done' _ "$CG8"
}

perf_count_from() {
	local ev=$1 file=$2
	awk -v ev="$ev" '$0 ~ ev { gsub(/,/, "", $1); print $1+0; exit }' "$file"
}

G8DIR="$OUTROOT/g8"
rm -rf "$G8DIR"
mkdir -p "$G8DIR/data"
COLLECT_LOG="$G8DIR/collect.log"
./bin/hids-collect -datadir "$G8DIR/data" -cgroup "$CG8" -duration 2m -zstd-level 0 \
	> "$COLLECT_LOG" 2>&1 &
CPID=$!
wait_ready "$COLLECT_LOG" || { cat "$COLLECT_LOG"; fail "G8 collector khong READY"; }

perf stat -a -e sched:sched_process_exec -G hids-test8 -- sleep 30 >"$G8DIR/perf-exec.txt" 2>&1 &
PE=$!
perf stat -a -e sched:sched_process_fork -G hids-test8 -- sleep 30 >"$G8DIR/perf-fork.txt" 2>&1 &
PF=$!
perf stat -a -e sched:sched_process_exit -G hids-test8 -- sleep 30 >"$G8DIR/perf-exit.txt" 2>&1 &
PX=$!
wait_perf_fd "$PE" || fail "G8 perf exec chua gan"
wait_perf_fd "$PF" || fail "G8 perf fork chua gan"
wait_perf_fd "$PX" || fail "G8 perf exit chua gan"

g8_workload

wait "$PE" "$PF" "$PX" || true
kill -TERM "$CPID" 2>/dev/null || true
for _ in $(seq 1 40); do
	kill -0 "$CPID" 2>/dev/null || break
	sleep 0.25
done
kill -KILL "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true

PROC_TSV=$(find "$G8DIR/data" -name 'proc-*.tsv.zst' | sort | tail -1)
[[ -n ${PROC_TSV:-} ]] || fail "G8 khong co proc TSV"
zstdcat "$PROC_TSV" | tail -n +2 | awk -F'\t' '
  $2=="exec"{e++} $2=="fork"{f++} $2=="exit"{x++}
  END{print "collector exec",e+0,"fork",f+0,"exit",x+0}
' | tee "$G8DIR/proc-counts.txt"
coll_exec=$(awk '/collector exec/{print $3}' "$G8DIR/proc-counts.txt")
coll_fork=$(awk '/collector fork/{print $5}' "$G8DIR/proc-counts.txt")
coll_exit=$(awk '/collector exit/{print $7}' "$G8DIR/proc-counts.txt")
perf_exec=$(perf_count_from sched:sched_process_exec "$G8DIR/perf-exec.txt")
perf_fork=$(perf_count_from sched:sched_process_fork "$G8DIR/perf-fork.txt")
perf_exit=$(perf_count_from sched:sched_process_exit "$G8DIR/perf-exit.txt")
{
	echo "perf exec=$perf_exec fork=$perf_fork exit=$perf_exit"
	echo "collector exec=$coll_exec fork=$coll_fork exit=$coll_exit"
} | tee "$G8DIR/perf-vs-collector.txt"

[[ "$coll_exec" == "$perf_exec" ]] && pass "G8 exec collector=$coll_exec perf=$perf_exec" \
	|| fail "G8 exec collector=$coll_exec perf=$perf_exec"
[[ "$coll_fork" == "$perf_fork" ]] && pass "G8 fork collector=$coll_fork perf=$perf_fork" \
	|| fail "G8 fork collector=$coll_fork perf=$perf_fork"
[[ "$coll_exit" == "$perf_exit" ]] && pass "G8 exit collector=$coll_exit perf=$perf_exit" \
	|| fail "G8 exit collector=$coll_exit perf=$perf_exit"

true_exec=$(zstdcat "$PROC_TSV" | tail -n +2 | awk -F'\t' '$2=="exec" && $8 ~ /\/true$/ {c++} END{print c+0}')
echo "exec filename ket thuc /true: $true_exec" | tee "$G8DIR/true-exec.txt"
[[ "$true_exec" -eq 500 ]] && pass "G8 exec /true = 500" || fail "G8 exec /true = $true_exec (can 500)"
cleanup_g8

echo "=== G9 rotate 2m + G7-cap 1 tien trinh zstd0 ==="
G9DIR="$OUTROOT/g9"
rm -rf "$G9DIR"
mkdir -p "$G9DIR"
fifo="$G9DIR/sysinj.fifo"
mkfifo "$fifo"
exec 8<>"$fifo"
./bin/sysinj -n 200000000 <"$fifo" >"$G9DIR/sysinj.log" 2>&1 &
SYS9=$!
sleep 0.5
./bin/hids-collect -datadir "$G9DIR" -pid "$SYS9" -duration 7m -rotate 2m -zstd-level 0 \
	-ringbuf-mb 64 >"$G9DIR/run.log" 2>&1 &
G9PID=$!
wait_ready "$G9DIR/run.log" || { cat "$G9DIR/run.log"; fail "G9 collector khong READY"; }
printf 'x' >&8
exec 8>&-
sleep 420
kill -TERM "$SYS9" 2>/dev/null || true
wait "$SYS9" 2>/dev/null || true
kill -TERM "$G9PID" 2>/dev/null || true
wait "$G9PID" 2>/dev/null || true
rm -f "$fifo"
mapfile -t BINS < <(find "$G9DIR" -name '*.bin' | sort)
[[ ${#BINS[@]} -ge 2 ]] || fail "G9 can >= 2 file .bin, co ${#BINS[@]}"
./bin/rec-chain "${BINS[@]}" | tee "$G9DIR/rec-chain.txt"
bmiss=$(sed -n 's/.*tong seq thieu ranh gioi: \([0-9]*\).*/\1/p' "$G9DIR/rec-chain.txt" | tail -1)
bmiss=${bmiss:-999}
bholes=$(sed -n 's/.*tong lo hong ranh gioi: \([0-9]*\).*/\1/p' "$G9DIR/rec-chain.txt" | tail -1)
bholes=${bholes:-999}
last_stats=$(ls -1 "$G9DIR"/*.stats 2>/dev/null | sort | tail -1 || true)
tot_mat=0
[[ -n ${last_stats:-} ]] && tot_mat=$(awk -F, 'NR>1{d+=$3} END{print d+0}' "$last_stats")
echo "G9 ranh_gioi lo_hong=$bholes seq_thieu=$bmiss kernel_mat_tong=$tot_mat" | tee "$G9DIR/g9-summary.txt"
if [[ "$bmiss" -le "$tot_mat" && "$bholes" -le "$tot_mat" ]]; then
	pass "G9 rec-chain seq_thieu=$bmiss lo_hong=$bholes mat=$tot_mat"
else
	fail "G9 rec-chain seq_thieu=$bmiss lo_hong=$bholes > mat=$tot_mat"
fi

echo "=== G10 disk guard ==="
G10DIR="$OUTROOT/g10"
rm -rf "$G10DIR"
mkdir -p "$G10DIR"
fifo10="$G10DIR/sysinj.fifo"
mkfifo "$fifo10"
exec 8<>"$fifo10"
./bin/sysinj -n 200000000 <"$fifo10" >"$G10DIR/sysinj.log" 2>&1 &
SYS10=$!
sleep 0.5
./bin/hids-collect -datadir "$G10DIR" -pid "$SYS10" -duration 90s -zstd-level 0 \
	-min-free-gb 50 >"$G10DIR/run.log" 2>&1 &
G10PID=$!
wait_ready "$G10DIR/run.log" || fail "G10 collector khong READY"
printf 'x' >&8
exec 8>&-
sleep 2
echo 4000 >"$G10DIR/min_free_gb"
sleep 15
grep -q PAUSE_DISK "$G10DIR/run.log" && pass "G10 PAUSE_DISK" || fail "G10 khong thay PAUSE_DISK"
echo 50 >"$G10DIR/min_free_gb"
sleep 15
grep -q RESUME_DISK "$G10DIR/run.log" && pass "G10 RESUME_DISK" || fail "G10 khong thay RESUME_DISK"
kill -TERM "$SYS10" 2>/dev/null || true
wait "$SYS10" 2>/dev/null || true
kill -TERM "$G10PID" 2>/dev/null || true
wait "$G10PID" 2>/dev/null || true
rm -f "$fifo10"
skipped=$(sed -n 's/.*disk_skipped=\([0-9]*\).*/\1/p' "$G10DIR/run.log" | tail -1)
skipped=${skipped:-0}
[[ "$skipped" -gt 0 ]] && pass "G10 bo vi dia=$skipped" || fail "G10 bo vi dia=$skipped (can >0)"
mat=$(grep -E 'LOSS |mat_tong=' "$G10DIR/run.log" | awk -F= '/mat_tong/{print $NF}' | tail -1 || true)
mat=${mat:-0}
grep -q 'LOSS ' "$G10DIR/run.log" && fail "G10 kernel LOSS khac 0" || pass "G10 kernel mat=0"

echo "=== host-stats 10 phut ==="
HDIR="$OUTROOT/host10m"
mkdir -p "$HDIR"
./bin/hids-collect -datadir "$HDIR" -pid "$$" -duration 10m -zstd-level 0 >"$HDIR/run.log" 2>&1 &
HPID=$!
wait "$HPID" || true
HOST=$(find "$HDIR" -name 'host-*.tsv.zst' | head -1)
[[ -n $HOST ]] || fail "khong co host TSV"
lines=$(zstdcat "$HOST" | tail -n +2 | wc -l)
echo "host lines: $lines"
[[ "$lines" -ge 580 && "$lines" -le 620 ]] && pass "host ~600 dong" || fail "host lines=$lines"
# cpu_user khong giam
zstdcat "$HOST" | tail -n +2 | awk -F'\t' 'NR==1{f=$3} END{if($3>=f)print "ok"; else print "bad"}' | grep -q ok \
  && pass "cpu_user khong giam" || fail "cpu_user giam"

echo "=== m6b1_gate xong ==="
