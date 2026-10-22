#!/usr/bin/env bash
# M6c-3 G11s: S1 (wl cpu 10000 300, CPU 20) voi -pmu on, sample=20, sample=50.
# In trung vi/p10/p90 inst va cyc (on), so khoang co co PMU va trung vi cua
# cac khoang co co (sample), xac nhan khoang khong co co inst=cyc=0.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"
WL=./bin/wl
COLLECT=./bin/hids-collect

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "KHONG_READY" >&2; return 1
}
wait_wchan() {
	local pid=$1 want=$2 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		if [[ $want == eq && $w == pipe_read ]]; then return 0; fi
		if [[ $want == ne && $w != pipe_read ]]; then return 0; fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	return 1
}

run_mode() {
	local mode=$1 tag=$2
	local dir="$OUTROOT/$tag"
	mkdir -p "$dir"
	local fifo="$dir/wl.fifo" bin="$dir/collect.bin"
	mkfifo "$fifo"
	exec 9<>"$fifo"
	taskset -c 20 "$WL" cpu 10000 300 <"$fifo" >"$dir/wl.log" 2>&1 &
	local wl_pid=$!
	sleep 0.5
	"$COLLECT" -pid "$wl_pid" -zstd-level 0 -pmu "$mode" -out "$bin" 2>"$dir/collect.log" &
	local cpid=$!
	wait_ready "$dir/collect.log" || { kill "$wl_pid" "$cpid" 2>/dev/null; exec 9>&-; return 1; }
	printf '.' >&9
	wait_wchan "$wl_pid" eq || true
	printf '.' >&9
	wait_wchan "$wl_pid" ne || true
	wait_wchan "$wl_pid" eq || true
	kill -INT "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true
	printf '.' >&9
	exec 9>&-
	wait "$wl_pid" 2>/dev/null || true
	rm -f "$fifo"
	./bin/rec-export "$bin" >"$dir/export.csv"
	python3 - "$dir/export.csv" "$wl_pid" "$tag" <<'PY'
import csv, statistics, sys
path, tid, tag = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) == tid and not int(r["flags"]) & 1:
            rows.append(r)
flagged = [r for r in rows if int(r["pmu_ok"]) == 1]
unflagged_bad = [r for r in rows if int(r["pmu_ok"]) != 1 and (int(r["inst"]) != 0 or int(r["cyc"]) != 0)]
def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, max(0, int(q * len(v))))]
print(f"[{tag}] so khoang khong-FIRST: {len(rows)}, co co PMU: {len(flagged)}, khong co nhung inst/cyc != 0: {len(unflagged_bad)}")
if flagged:
    inst = [int(r["inst"]) for r in flagged]
    cyc = [int(r["cyc"]) for r in flagged]
    print(f"[{tag}] inst: trung_vi={statistics.median(inst):.1f} p10={pct(inst, 0.10)} p90={pct(inst, 0.90)}")
    print(f"[{tag}] cyc: trung_vi={statistics.median(cyc):.1f} p10={pct(cyc, 0.10)} p90={pct(cyc, 0.90)}")
PY
}

run_mode on on
run_mode sample=20 sample20
run_mode sample=50 sample50
echo "G11s xong"
