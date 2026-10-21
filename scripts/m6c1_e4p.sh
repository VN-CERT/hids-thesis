#!/usr/bin/env bash
# M6c E4p: chay lai E4-stream (wl mem R=500, CPU 20; stress-ng --stream tren
# CPU 0-19,21-23) o L = 0, 12, 22 voi -pmu on, 3 lan moi muc.
# Khoang dot = ban ghi nanosleep (nr=35). Bao trung vi cpu_ns, inst, cyc va
# hai ti so cyc/inst (CPI), cyc/cpu_ns (tan so hieu dung, GHz).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"
WL=./bin/wl
COLLECT=./bin/hids-collect

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "collector khong READY" >&2; exit 1
}
wait_wchan() { # <pid> <want: eq|ne> — cho wchan pipe_read theo dieu kien
	local pid=$1 want=$2 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		if [[ $want == eq && $w == pipe_read ]]; then return 0; fi
		if [[ $want == ne && $w != pipe_read ]]; then return 0; fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	echo "wl $pid khong doi wchan ($want)" >&2; exit 1
}

run_one() {
	local L=$1 run=$2
	local dir="$OUTROOT/L$L/run$run"
	mkdir -p "$dir"
	# wl tu kiem mem co the truot vi nhieu tan so/steal; thu lai toi da 5 lan
	# (day la tu kiem cua workload, khong phai tieu chi do).
	local attempt
	for attempt in $(seq 1 "${M6C_E4P_ATTEMPTS:-5}"); do
		run_attempt "$L" "$run" "$attempt" "$dir"
		if grep -q "khoang dot (nr=" "$dir/ketqua.txt" && ! grep -q "khoang dot (nr=230, khong FIRST): 0" "$dir/ketqua.txt"; then
			return 0
		fi
		echo "E4p L=$L run=$run attempt=$attempt: wl tu kiem truot hoac 0 khoang, thu lai" >&2
	done
	echo "E4p L=$L run=$run: het 5 lan thu" >&2
}

run_attempt() {
	local L=$1 run=$2 attempt=$3 dir="$4"
	local ts prefix bin fifo
	ts=$(date +%H%M%S)
	prefix="out/m6c-e4p-L$L-$run-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	echo "=== E4p L=$L run=$run attempt=$attempt ===" | tee "$dir/ketqua.txt"

	# Giao thuc E4 (M6c-1 5a): wl khoi dong, hieu chuan va tu kiem mem KHI MAY
	# RANH (stress-ng chua chay); stress-ng khoi dong sau, cho on dinh 10s,
	# roi moi gui go.
	local stress_pid=""
	mkfifo "$fifo"
	exec 9<>"$fifo"
	taskset -c 20 "$WL" mem 500 <"$fifo" >"$dir/wl.log" 2>&1 &
	local wl_pid=$!
	sleep 0.5
	"$COLLECT" -pid "$wl_pid" -zstd-level 0 -pmu on -out "$bin" 2>"$dir/collect.log" &
	local cpid=$!
	wait_ready "$dir/collect.log"
	wait_wchan "$wl_pid" eq
	if ((L > 0)); then
		stress-ng --stream "$L" --taskset 0-19,21-23 --timeout 300 >"$dir/stress.log" 2>&1 &
		stress_pid=$!
		sleep 10
	fi
	# wl co hai cong wait_go: '.' 1 qua marker getuid, '.' 2 chay burst.
	printf '.' >&9
	wait_wchan "$wl_pid" eq
	printf '.' >&9
	wait_wchan "$wl_pid" ne
	wait_wchan "$wl_pid" eq
	kill -INT "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true
	printf '.' >&9
	exec 9>&-
	wait "$wl_pid" 2>/dev/null || true
	rm -f "$fifo"
	if [[ -n $stress_pid ]]; then
		kill "$stress_pid" 2>/dev/null; wait "$stress_pid" 2>/dev/null || true
	fi

	./bin/rec-export "$bin" >"$dir/export.csv"
	python3 - "$dir/export.csv" "$wl_pid" >>"$dir/ketqua.txt" <<'PY'
import csv, statistics, sys
path, tid = sys.argv[1], int(sys.argv[2])
# Khoang dot ket thuc bang syscall ngu cua wl: glibc hien tai dung
# clock_nanosleep (230) thay vi nanosleep (35). Chon nr co 500 ban ghi.
from collections import Counter
allrows = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) == tid:
            allrows.append(r)
cnt = Counter(int(r["syscall_nr"]) for r in allrows if not int(r["flags"]) & 1)
burn_nr = 230 if cnt.get(230, 0) >= cnt.get(35, 0) else 35
print(f"so ban ghi theo syscall (khong FIRST): {dict(cnt)}; chon khoang dot nr={burn_nr}")
rows = []
for r in allrows:
    if int(r["syscall_nr"]) != burn_nr:
        continue
    if int(r["flags"]) & 1:  # bo FIRST
        continue
    rows.append(r)
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
PY
	echo "du lieu: $bin" >>"$dir/ketqua.txt"
	cat "$dir/ketqua.txt"
}

if [[ -n "${M6C_E4P_CELLS:-}" ]]; then
	for cell in $M6C_E4P_CELLS; do
		run_one "${cell%%:*}" "${cell##*:}"
	done
else
	for L in 0 12 22; do
		for run in 1 2 3; do
			run_one "$L" "$run"
		done
	done
fi
echo "E4p xong: $OUTROOT"
