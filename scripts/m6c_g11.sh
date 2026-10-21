#!/usr/bin/env bash
# M6c G11: tai S1 va S3, gan them perf stat -e instructions:u,cycles:u -t <tid wl>
# khi wl dang cho FIFO, dung sau khi kich ban xong; so tong inst/cyc cua collector
# (cua so nhu g3_window.py) voi perf stat. Chi do, khong sua gi.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:?can thu muc output}"
EVENTS="${2:-instructions:u,cycles:u}"
mkdir -p "$OUTROOT"
WL=./tools/wl
COLLECT=./bin/hids-collect
G3WIN=./scripts/g3_window.py
WL_CPU=20

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "collector khong READY: $log" >&2; exit 1
}

wait_wl_on_read() {
	# Cho wl vao read() tren FIFO (wchan=pipe_read) nhu g3.sh.
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	echo "wl $pid khong cho tren read()" >&2; exit 1
}

wait_wl_burst_done() {
	# Cho wl roi pipe_read (burst bat dau) roi quay lai pipe_read (burst xong).
	local pid=$1 i w seen_out=0
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		if [[ $w != pipe_read ]]; then
			seen_out=1
		elif [[ $seen_out -eq 1 ]]; then
			return 0
		fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	echo "wl $pid khong xong burst" >&2; exit 1
}

run_one() {
	local name=$1; shift
	local ts prefix bin fifo wl_pid cpid perf_pid
	ts=$(date +%H%M%S)
	prefix="out/m6c-g11-$name-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	local out="$OUTROOT/$name.txt"
	echo "=== G11 $name: wl $* (CPU $WL_CPU), perf stat -e $EVENTS ===" | tee "$out"

	mkfifo "$fifo"
	exec 9<>"$fifo"
	taskset -c "$WL_CPU" "$WL" "$@" <"$fifo" >"$prefix-wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	echo "wl pid=$wl_pid" | tee -a "$out"

	"$COLLECT" -pid "$wl_pid" -zstd-level 0 -pmu on -out "$bin" 2>"$prefix-collect.log" &
	cpid=$!
	wait_ready "$prefix-collect.log"

	# Gan perf stat khi wl dang cho FIFO (truoc khi tha wl chay burst).
	wait_wl_on_read "$wl_pid"
	perf stat -e "$EVENTS" -t "$wl_pid" -o "$OUTROOT/$name.perfstat.txt" &
	perf_pid=$!
	sleep 1

	printf '.' >&9
	wait_wl_burst_done "$wl_pid"
	# wl da xong burst va quay lai doc FIFO: dung perf stat va collector.
	kill -INT "$perf_pid" 2>/dev/null; wait "$perf_pid" 2>/dev/null || true
	kill -INT "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true
	printf '.' >&9
	exec 9>&-
	wait "$wl_pid" 2>/dev/null || true
	rm -f "$fifo"

	echo "--- perf stat (nguyen van) ---" | tee -a "$out"
	cat "$OUTROOT/$name.perfstat.txt" | tee -a "$out"

	local win t_from t_to
	win=$(python3 "$G3WIN" "$bin" "$wl_pid")
	t_from=$(echo "$win" | head -1)
	t_to=$(echo "$win" | tail -1)
	echo "cua so: $t_from .. $t_to" | tee -a "$out"

	./bin/rec-export "$bin" >"$OUTROOT/$name.export.csv"
	python3 - "$OUTROOT/$name.export.csv" "$wl_pid" "$t_from" "$t_to" >>"$out" <<'PY'
import csv, sys
path, tid, t_from, t_to = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
n = nonfirst = pmu = 0
s_inst = s_cyc = 0
per_cpu = {}
with open(path) as f:
    for row in csv.DictReader(f):
        if int(row["tid"]) != tid:
            continue
        ts = int(row["ts_enter"])
        if not (t_from < ts <= t_to):
            continue
        n += 1
        flags = int(row["flags"])
        cpu = (flags >> 8) & 0xFF
        d = per_cpu.setdefault(cpu, [0, 0])
        if flags & 1 == 0:
            nonfirst += 1
            d[1] += 1
            if int(row["pmu_ok"]):
                pmu += 1
                d[0] += 1
                s_inst += int(row["inst"])
                s_cyc += int(row["cyc"])
print(f"collector: ban ghi trong cua so={n} khong_FIRST={nonfirst} co_PMU={pmu}")
if nonfirst:
    print(f"ti le PMU (khong-FIRST): {pmu}/{nonfirst} = {pmu*100.0/nonfirst:.4f}%")
print(f"tong inst collector = {s_inst}")
print(f"tong cyc collector = {s_cyc}")
for cpu in sorted(per_cpu):
    ok, tot = per_cpu[cpu]
    print(f"CPU {cpu}: PMU {ok}/{tot} = {ok*100.0/tot:.2f}%" if tot else f"CPU {cpu}: 0/0")
PY
	echo "du lieu: $bin" | tee -a "$out"
}

run_one S1 cpu 10000 300
run_one S3 mixed 2000 3000 500
echo "G11 xong: $OUTROOT"
