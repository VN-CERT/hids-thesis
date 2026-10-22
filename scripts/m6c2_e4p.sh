#!/usr/bin/env bash
# M6c-2 phan 4: E4p theo DUNG co che E4 goc cua scripts/m4.sh:
#  - buoc calibrate (calibrate_wl + calibrate_mem, may ranh) viet
#    out/m4-loops.txt (burn_loops, mem_steps);
#  - e4_workers: stress-ng --stream tung worker -> sleep 2 ->
#    run_wl_mem "$loops" 500: wl chay voi -loops doc tu file hieu chuan
#    (KHONG tu kiem mem trong luot chay);
#  - collector gan nhu run_wl_mem cua m4.sh: -pid <wl_pid>, bat dau 0.5s sau
#    wl, wait_ready, hai cong '.'; chi khac la them -pmu on (nhiem vu yeu cau).
# Yeu cau moi luot co >= 450 khoang dot (nr=230, khong FIRST) co co PMU;
# thieu thi dem la mot attempt truot va chay lai (toi da 3 attempt/o).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"
WL=./bin/wl
COLLECT=./bin/hids-collect
WL_CPU=20
LOOPS_FILE=out/m4-loops.txt

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "KHONG_READY (cho 20s)" >&2
	return 1
}
wait_wl_read() {
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	echo "wl $pid khong cho read()" >&2
	return 1
}
read_burn_loops() { awk '/^burn_loops/{print $2}' "$LOOPS_FILE"; }

calibrate() {
	# calibrate_wl (m4.sh dong 160-174)
	local fifo wl_pid
	fifo=$(mktemp -u)
	mkfifo "$fifo" || return 1
	echo "m6c2: hieu chuan wl tren CPU $WL_CPU (may ranh)..." >&2
	taskset -c "$WL_CPU" "$WL" mixed 1 <"$fifo" >"$OUTROOT/cal-wl.log" 2>&1 &
	wl_pid=$!
	sleep 3
	[[ -s $LOOPS_FILE ]] || { echo "hieu chuan wl that bai" >&2; return 1; }
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	# calibrate_mem (m4.sh dong 148-158)
	echo "m6c2: hieu chuan mem tren CPU $WL_CPU..." >&2
	taskset -c "$WL_CPU" "$WL" mem 1 >"$OUTROOT/cal-mem.log" 2>&1 &
	wl_pid=$!
	sleep 20
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	local ms
	ms=$(awk '/^mem_steps/{print $2}' "$LOOPS_FILE")
	[[ -n $ms && $ms -gt 0 ]] || { echo "mem hieu chuan that bai" >&2; return 1; }
	echo "calibrate xong: burn_loops=$(read_burn_loops) mem_steps=$ms" | tee "$OUTROOT/calibrate.txt"
}

run_attempt() {
	local L=$1 run=$2 attempt=$3 dir=$4 loops=$5
	local prefix fifo wl_pid cpid bin
	prefix="out/m6c2-e4p-L$L-$run-$(date +%H%M%S)"
	fifo="$prefix.fifo"
	bin="$prefix.bin"
	echo "=== E4p-goc L=$L run=$run attempt=$attempt ===" | tee "$dir/ketqua.txt"
	local stress_pids=() w
	for ((w = 0; w < L; w++)); do
		stress-ng --stream 1 --taskset 0-19,21-23 --timeout 120 >"$dir/stress-$w.log" 2>&1 &
		stress_pids+=($!)
	done
	((L > 0)) && echo "stress-ng: stress-ng --stream 1 --taskset 0-19,21-23 --timeout 120 (x$L worker)" >>"$dir/ketqua.txt"
	sleep 2
	mkfifo "$fifo"
	exec 9<>"$fifo"
	local wl_cmd="taskset -c $WL_CPU $WL -loops $loops mem 500"
	echo "wl: $wl_cmd" >>"$dir/ketqua.txt"
	taskset -c "$WL_CPU" "$WL" -loops "$loops" mem 500 <"$fifo" >"$dir/wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	"$COLLECT" -pid "$wl_pid" -pmu on -duration 90s -out "$bin" 2>"$dir/collect.log" &
	cpid=$!
	if ! wait_ready "$dir/collect.log"; then
		kill "$wl_pid" "$cpid" 2>/dev/null; wait "$wl_pid" 2>/dev/null || true
		exec 9>&-
		for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null; done
		echo "KHONG_READY: bo attempt" >&2
		return 1
	fi
	printf '.\n' >&9
	wait_wl_read "$wl_pid" || true
	printf '.\n' >&9
	wait "$wl_pid" 2>/dev/null || true
	printf '.\n' >&9
	wait "$cpid" 2>/dev/null || true
	exec 9>&-
	rm -f "$fifo"
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null; done

	./bin/rec-export "$bin" >"$dir/export.csv"
	python3 - "$dir/export.csv" "$wl_pid" >>"$dir/ketqua.txt" <<'PY'
import csv, statistics, sys
from collections import Counter
path, tid = sys.argv[1], int(sys.argv[2])
allrows = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) == tid:
            allrows.append(r)
cnt = Counter(int(r["syscall_nr"]) for r in allrows if not int(r["flags"]) & 1)
burn_nr = 230 if cnt.get(230, 0) >= cnt.get(35, 0) else 35
print(f"so ban ghi theo syscall (khong FIRST): {dict(cnt)}; chon khoang dot nr={burn_nr}")
rows = [r for r in allrows if int(r["syscall_nr"]) == burn_nr and not int(r["flags"]) & 1]
ok = [r for r in rows if int(r["pmu_ok"]) == 1]
print(f"khoang dot (nr={burn_nr}, khong FIRST): {len(rows)}, co PMU: {len(ok)}")
if ok:
    cpu = [int(r["cpu_ns"]) for r in ok]
    inst = [int(r["inst"]) for r in ok]
    cyc = [int(r["cyc"]) for r in ok]
    cpi = [c / i for c, i in zip(cyc, inst) if i > 0]
    ghz = [c / u for c, u in zip(cyc, cpu) if u > 0]
    med = statistics.median
    print(f"trung vi cpu_ns = {med(cpu):.1f}")
    print(f"trung vi inst = {med(inst):.1f}")
    print(f"trung vi cyc = {med(cyc):.1f}")
    print(f"trung vi cyc/inst (CPI) = {med(cpi):.4f}")
    print(f"trung vi cyc/cpu_ns (GHz hieu dung) = {med(ghz):.4f}")
    print(f"so_khoang_dot = {len(ok)}")
PY
	echo "du lieu: $bin" >>"$dir/ketqua.txt"
	cat "$dir/ketqua.txt"
}

run_one() {
	local L=$1 run=$2 loops=$3 ghz=$4
	local dir="$OUTROOT/L$L/run$run"
	mkdir -p "$dir"
	local attempt
	for attempt in 1 2 3; do
		run_attempt "$L" "$run" "$attempt" "$dir" "$loops"
		if grep -q "so_khoang_dot" "$dir/ketqua.txt"; then
			local n
			n=$(awk '/^so_khoang_dot/{print $3}' "$dir/ketqua.txt")
			if [[ $n -ge 450 ]]; then
				echo "so_attempt = $attempt" >>"$dir/ketqua.txt"
				echo "GHz_wall_dau_tan_so = $ghz" >>"$dir/ketqua.txt"
				return 0
			fi
		fi
		echo "E4p-goc L=$L run=$run attempt=$attempt: <450 khoang dot co PMU, chay lai" >&2
	done
}

calibrate || exit 1
LOOPS=$(read_burn_loops)
for L in 0 12 22; do
	bash scripts/freq_stamp.sh 20 >"$OUTROOT/freq-L$L.txt" 2>&1
	GHZ=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/freq-L$L.txt")
	for run in 1 2 3; do
		run_one "$L" "$run" "$LOOPS" "$GHZ"
	done
done
echo "m6c2 E4p xong: $OUTROOT"
