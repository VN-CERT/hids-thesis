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

[[ $EUID -eq 0 ]] || die "can root"
hids_require_clean_git || die "cay git khong sach"
[[ -x ./bin/hids-collect ]] || die "chay make build truoc"

echo "=== G7a zstd-level 0 ==="
bash scripts/g7.sh a 1000000 2>&1 | tee "$OUTROOT/g7a-z0.txt"
g7a_mat=$(grep -E 'tong bo dem mat' "$OUTROOT/g7a-z0.txt" | tail -1 | awk '{print $NF}' || true)
g7a_mat=${g7a_mat:-999}
[[ "$g7a_mat" == 0 ]] && pass "G7a mat=0" || fail "G7a mat=$g7a_mat"

echo "=== G3 S1-S5 (subset g3.sh) ==="
G3_OUTROOT="$OUTROOT/g3" bash scripts/g3.sh 2>&1 | tee "$OUTROOT/g3.log" || fail "g3.sh loi"

echo "=== G8 proc vs perf ==="
CG8=/sys/fs/cgroup/hids-test8
mkdir -p "$CG8"
echo $$ >"$CG8/cgroup.procs" 2>/dev/null || true
cleanup_g8() { rmdir "$CG8" 2>/dev/null || true; }
trap cleanup_g8 EXIT

G8DIR="$OUTROOT/g8"
mkdir -p "$G8DIR"
COLLECT_LOG="$G8DIR/collect.log"
./bin/hids-collect -datadir "$G8DIR/data" -cgroup "$CG8" -duration 120 -zstd-level 0 \
	> "$COLLECT_LOG" 2>&1 &
CPID=$!
for i in $(seq 1 300); do grep -qx READY "$COLLECT_LOG" 2>/dev/null && break; sleep 0.1; done
grep -qx READY "$COLLECT_LOG" || fail "G8 collector khong READY"

(
  echo $$ >"$CG8/cgroup.procs"
  for _ in $(seq 1 500); do /bin/true; done
) &
WORK=$!
sleep 1
T0=$(date +%s.%N)
wait "$WORK" || true
T1=$(date +%s.%N)

kill -TERM "$CPID" 2>/dev/null || true
wait "$CPID" 2>/dev/null || true

perf_exec=$(perf stat -a -e "sched:sched_process_exec" -G hids-test8 -- sleep 0.1 2>&1 | true)
perf_fork=$(perf stat -a -e "sched:sched_process_fork" -G hids-test8 -- sleep 0.1 2>&1 | true)
perf_exit=$(perf stat -a -e "sched:sched_process_exit" -G hids-test8 -- sleep 0.1 2>&1 | true)
echo "perf_exec sample: $perf_exec" | tee "$G8DIR/perf-exec.txt"
echo "perf_fork sample: $perf_fork" | tee "$G8DIR/perf-fork.txt"
echo "perf_exit sample: $perf_exit" | tee "$G8DIR/perf-exit.txt"

PROC_TSV=$(find "$G8DIR/data" -name 'proc-*.tsv.zst' | head -1)
[[ -n $PROC_TSV ]] || fail "G8 khong co proc TSV"
# Dem su kien tu TSV (bo header)
zstdcat "$PROC_TSV" 2>/dev/null | tail -n +2 | awk -F'\t' '
  $2=="exec"{e++} $2=="fork"{f++} $2=="exit"{x++}
  END{print "exec",e+0,"fork",f+0,"exit",x+0}
' | tee "$G8DIR/proc-counts.txt"
true_exec=$(grep -c '/true$' <(zstdcat "$PROC_TSV" | tail -n +2 | cut -f8) || true)
echo "exec filename /true: $true_exec" | tee "$G8DIR/true-exec.txt"
[[ "$true_exec" -eq 500 ]] && pass "G8 exec /true = 500" || fail "G8 exec /true = $true_exec (can 500)"

echo "=== G9 rotate 2m + rec-chain ==="
G9DIR="$OUTROOT/g9"
mkdir -p "$G9DIR"
# Mot pid nho de co du lieu
./bin/hids-collect -datadir "$G9DIR" -pid "$$" -duration 7m -rotate 2m -zstd-level 0 \
	-ringbuf-mb 64 >"$G9DIR/run.log" 2>&1 &
G9PID=$!
wait "$G9PID" || true
mapfile -t BINS < <(find "$G9DIR" -name '*.bin' | sort)
[[ ${#BINS[@]} -ge 2 ]] || fail "G9 can >= 2 file .bin"
./bin/rec-chain "${BINS[@]}" | tee "$G9DIR/rec-chain.txt"
bmiss=$(grep 'tong seq thieu ranh gioi' "$G9DIR/rec-chain.txt" | awk '{print $NF}')
bmiss=${bmiss:-999}
# Cho phep seq thieu ranh gioi = tong mat kernel (doc tu file cuoi)
last_stats=$(find "$G9DIR" -name '*.stats' | sort | tail -1)
tot_mat=$(awk -F, 'NR>1{d+=$3} END{print d+0}' "$last_stats" 2>/dev/null || echo 0)
if [[ "$bmiss" -le "$tot_mat" ]]; then pass "G9 boundary missing $bmiss <= kernel drops $tot_mat"; else fail "G9 boundary missing $bmiss > drops $tot_mat"; fi

echo "=== G10 disk guard ==="
G10DIR="$OUTROOT/g10"
mkdir -p "$G10DIR"
./bin/hids-collect -datadir "$G10DIR" -pid "$$" -duration 90s -zstd-level 0 \
	-min-free-gb 50 >"$G10DIR/run.log" 2>&1 &
G10PID=$!
for i in $(seq 1 150); do grep -qx READY "$G10DIR/run.log" 2>/dev/null && break; sleep 0.1; done
echo 4000 >"$G10DIR/min_free_gb"
sleep 15
grep -q PAUSE_DISK "$G10DIR/run.log" && pass "G10 PAUSE_DISK" || fail "G10 khong thay PAUSE_DISK"
echo 50 >"$G10DIR/min_free_gb"
sleep 15
grep -q RESUME_DISK "$G10DIR/run.log" && pass "G10 RESUME_DISK" || fail "G10 khong thay RESUME_DISK"
kill -TERM "$G10PID" 2>/dev/null || true
wait "$G10PID" 2>/dev/null || true

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
