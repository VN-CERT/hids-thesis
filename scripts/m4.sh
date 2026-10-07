#!/usr/bin/env bash
# m4.sh — thi nghiem M4 (E1, E3, E4; e2 chuan bi cho nguoi dung).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

WL=./bin/wl
COLLECT=./bin/hids-collect
EXPORT=./bin/rec-export
E3BIN=./bin/m4_e3
M4PY=./analysis/m4.py
# Tranh numpy 2.x trong /usr/local lam hong pandas he thong.
M4_PYTHON=(env PYTHONNOUSERSITE=1 PYTHONPATH=/usr/lib/python3/dist-packages /usr/bin/python3)
LOOPS_FILE=out/m4-loops.txt
WL_CPU=20
DATE=$(date +%Y%m%d)
OUTROOT="validation/m4-${DATE}"
M4PY_OUT="$OUTROOT"

die() {
	echo "m4: $*" >&2
	exit 1
}

require_clean_git() {
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		path="${path%/}"
		if [[ $path == out/* || $path == validation/m4* ]]; then
			continue
		fi
		die "cay git khong sach: $st $path — commit truoc khi chay e4"
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

rebuild_summary() {
	local manifest=() L n mode
	for L in 0 1 2 3; do
		manifest+=("E1:${L}:${OUTROOT}/E1/L${L}.csv")
	done
	for mode in cache stream; do
		for n in 0 4 12 22; do
			manifest+=("E4-${mode}:${n}:${OUTROOT}/E4-${mode}/L${n}.csv")
		done
	done
	"${M4_PYTHON[@]}" "$M4PY" --outdir "$OUTROOT" --summary "$OUTROOT/summary-part.csv" "${manifest[@]}"
	"${M4_PYTHON[@]}" - <<PY
import pandas as pd
from pathlib import Path
root = Path("${OUTROOT}")
s = pd.read_csv(root / "summary-part.csv")
e3_rows = []
for tag in ("idle", "stress2"):
    p = root / "E3" / f"{tag}.csv"
    if not p.exists():
        continue
    df = pd.read_csv(p)
    if df.empty:
        continue
    df2 = df[df["dt_ns"].notna()]
    if df2.empty:
        row = df.iloc[-1]
    else:
        row = df2.loc[df2["vol_ns"].idxmax()]
    e3_rows.append({
        "experiment": f"E3-{tag}",
        "level": tag,
        "kind": "connect",
        "n": 1,
        "median_us": float(row["dt_ns"]) / 1000.0,
        "p90_us": float(row["dt_ns"]) / 1000.0,
        "p99_us": float(row["dt_ns"]) / 1000.0,
        "dt_median_us": float(row["dt_ns"]) / 1000.0,
        "cpu_median_us": float(row["cpu_ns"]) / 1000.0,
        "steal_median_us": float(row["steal_ns"]) / 1000.0,
        "irq_median_us": float(row["irq_ns"]) / 1000.0,
        "rq_median_us": float(row["rq_ns"]) / 1000.0,
        "vol_median_us": float(row["vol_ns"]) / 1000.0,
        "ratio_dt": float("nan"),
        "ratio_cpu": float("nan"),
    })
if e3_rows:
    s = pd.concat([s, pd.DataFrame(e3_rows)], ignore_index=True)
s.to_csv(root / "summary.csv", index=False)
print(f"luu {root / 'summary.csv'} ({len(s)} dong)")
PY
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong READY, xem $log"
}

wait_wl_read() {
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	die "wl $pid khong cho read()"
}

read_burn_loops() {
	[[ -r $LOOPS_FILE ]] || die "khong co $LOOPS_FILE — chay m4 calibrate truoc"
	awk '/^burn_loops/{print $2}' "$LOOPS_FILE"
}

calibrate_mem() {
	echo "m4: hieu chinh mem tren CPU $WL_CPU..." >&2
	taskset -c "$WL_CPU" "$WL" mem 1 >/dev/null 2>out/m4-cal-mem.log &
	local wl_pid=$!
	sleep 20
	kill "$wl_pid" 2>/dev/null
	wait "$wl_pid" 2>/dev/null
	local ms
	ms=$(awk '/^mem_steps/{print $2}' "$LOOPS_FILE")
	[[ -n $ms && $ms -gt 0 ]] || die "mem hieu chinh that bai, xem out/m4-cal-mem.log"
}

calibrate_wl() {
	mkdir -p out
	local fifo wl_pid
	fifo=$(mktemp -u)
	mkfifo "$fifo" || die "mkfifo"
	echo "m4: hieu chinh wl tren CPU $WL_CPU (may ranh)..." >&2
	taskset -c "$WL_CPU" "$WL" mixed 1 <"$fifo" >out/m4-cal-wl.log 2>&1 &
	wl_pid=$!
	sleep 3
	[[ -s $LOOPS_FILE ]] || die "hieu chinh that bai, xem out/m4-cal-wl.log"
	kill "$wl_pid" 2>/dev/null
	wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	echo "m4: burn_loops=$(read_burn_loops)" >&2
}

run_wl_mixed() {
	local loops=$1 rounds=$2
	local prefix fifo wl_pid cpid bin
	prefix="out/m4-$(date +%H%M%S)-$$"
	fifo="$prefix.fifo"
	bin="$prefix.bin"
	mkfifo "$fifo"
	exec 9<>"$fifo"
	taskset -c "$WL_CPU" "$WL" -loops "$loops" mixed "$rounds" <"$fifo" >"$prefix-wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	"$COLLECT" -pid "$wl_pid" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
	cpid=$!
	wait_ready "$prefix-collect.log"
	printf '.\n' >&9
	wait_wl_read "$wl_pid"
	printf '.\n' >&9
	wait "$wl_pid"
	printf '.\n' >&9
	wait "$cpid"
	exec 9>&-
	rm -f "$fifo"
	echo "$bin"
}

run_wl_mem() {
	local loops=$1 rounds=$2
	local prefix fifo wl_pid cpid bin
	prefix="out/m4-mem-$(date +%H%M%S)-$$"
	fifo="$prefix.fifo"
	bin="$prefix.bin"
	mkfifo "$fifo"
	exec 9<>"$fifo"
	taskset -c "$WL_CPU" "$WL" -loops "$loops" mem "$rounds" <"$fifo" >"$prefix-wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	"$COLLECT" -pid "$wl_pid" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
	cpid=$!
	wait_ready "$prefix-collect.log"
	printf '.\n' >&9
	wait_wl_read "$wl_pid"
	printf '.\n' >&9
	wait "$wl_pid"
	printf '.\n' >&9
	wait "$cpid"
	exec 9>&-
	rm -f "$fifo"
	echo "$bin"
}

export_csv() {
	local bin=$1 csv=$2
	"$EXPORT" "$bin" >"$csv"
}

e1() {
	local loops L csv manifest=() stress_pids=()
	loops=$(read_burn_loops)
	mkdir -p "$OUTROOT/E1"
	for L in 0 1 2 3; do
		for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null; done
		stress_pids=()
		for ((i = 0; i < L; i++)); do
			stress-ng --cpu 1 --taskset "$WL_CPU" --timeout 120 >/dev/null 2>&1 &
			stress_pids+=($!)
		done
		sleep 1
		bin=$(run_wl_mixed "$loops" 500)
		csv="$OUTROOT/E1/L${L}.csv"
		export_csv "$bin" "$csv"
		cp "$bin" "$OUTROOT/E1/L${L}.bin"
		manifest+=("E1:${L}:${csv}")
	done
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null; done
	printf '%s\n' "${manifest[@]}"
}

e3_once() {
	local tag=$1 stress_n=$2
	local port listener prefix bin csv
	port=$((19000 + RANDOM % 1000))
	python3 -c "import socket;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',$port));s.listen(1);s.accept();s.close()" &
	local lip=$!
	local stress_pids=()
	for ((i = 0; i < stress_n; i++)); do
		stress-ng --cpu 1 --taskset "$WL_CPU" --timeout 400 >/dev/null 2>&1 &
		stress_pids+=($!)
	done
	sleep 1
	prefix="out/m4-e3-${tag}-$(date +%H%M%S)"
	bin="$prefix.bin"
	local fifo="$prefix.fifo"
	mkfifo "$fifo"
	exec 8<>"$fifo"
	"$E3BIN" "$port" <"$fifo" &
	local wp=$!
	"$COLLECT" -pid "$wp" -duration 400s -out "$bin" 2>"$prefix-collect.log" &
	local cpid=$!
	wait_ready "$prefix-collect.log"
	printf '.' >&8
	wait "$wp"
	exec 8>&-
	rm -f "$fifo"
	wait "$cpid"
	kill "$lip" 2>/dev/null
	wait "$lip" 2>/dev/null
	for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
	mkdir -p "$OUTROOT/E3"
	csv="$OUTROOT/E3/${tag}.csv"
	export_csv "$bin" "$csv"
	cp "$bin" "$OUTROOT/E3/${tag}.bin"
	"${M4_PYTHON[@]}" - <<PY
import pandas as pd
df=pd.read_csv("$csv")
# connect x86_64 = 42; lay ban ghi co vol lon nhat (khoang ngu 300s)
df2=df[df["dt_ns"].notna()].copy()
if df2.empty:
    row=df.tail(1)
else:
    row=df2.loc[[df2["vol_ns"].idxmax()]]
print("=== E3 $tag ban ghi connect (vol max) ===")
for _,r in row.iterrows():
    print(f"syscall_nr={r.get('syscall_nr')} dt_ns={r.get('dt_ns')} vol_ns={r.get('vol_ns')} rq_ns={r.get('rq_ns')} cpu_ns={r.get('cpu_ns')}")
PY
	echo "E3:${tag}:${csv}"
}

e3() {
	e3_once idle 0
	e3_once stress2 2
}

e4_workers() {
	local n=$1 mode=$2
	local loops csv manifest=() stress_pids=() cpus
	loops=$(read_burn_loops)
	mkdir -p "$OUTROOT/E4-${mode}"
	for ((w = 0; w < n; w++)); do
		cpus="0-19,21-23"
		stress-ng --"$mode" 1 --taskset "$cpus" --timeout 120 >/dev/null 2>&1 &
		stress_pids+=($!)
	done
	sleep 2
	bin=$(run_wl_mem "$loops" 500)
	csv="$OUTROOT/E4-${mode}/L${n}.csv"
	export_csv "$bin" "$csv"
	cp "$bin" "$OUTROOT/E4-${mode}/L${n}.bin"
	for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
	echo "E4-${mode}:${n}:${csv}"
}

e4() {
	local manifest=()
	for n in 0 4 12 22; do
		manifest+=("$(e4_workers "$n" cache)")
	done
	for n in 0 4 12 22; do
		manifest+=("$(e4_workers "$n" stream)")
	done
	printf '%s\n' "${manifest[@]}"
}

e2_prep() {
	cat <<'EOF'
=== E2 (nguoi dung chay tren vCenter) ===
wl mixed R=500 tren CPU 20.
Dong thoi: stress-ng --cpu 23 --taskset 0-19,21-23 (timeout du dai).
Bon muc Limit MHz: Unlimited, 36000, 24000, 12000.
Truoc moi muc script in:
  "Tren vCenter: Edit Settings → CPU → Limit = <X> MHz → OK. Xong bam Enter."
Sau het dat lai Unlimited.

Lenh goi y (sau khi dat limit va bam Enter):
  LOOPS=$(awk '/^burn_loops/{print $2}' out/m4-loops.txt)
  taskset -c 20 ./bin/wl -loops "$LOOPS" mixed 500
  (collector -pid wl & stress-ng ...)

EOF
}

main() {
	[[ $EUID -eq 0 ]] || die "can root"
	for f in "$WL" "$COLLECT" "$EXPORT" "$E3BIN"; do
		[[ -x $f ]] || die "khong co $f (make build?)"
	done
	[[ -f $M4PY ]] || die "khong co $M4PY"
	command -v stress-ng >/dev/null || die "stress-ng"
	mkdir -p out "$OUTROOT"

	case "${1:-all}" in
	calibrate)
		calibrate_wl
		calibrate_mem
		;;
	e1)
		calibrate_wl 2>/dev/null || true
		mapfile -t m < <(e1)
		"${M4_PYTHON[@]}" "$M4PY" --outdir "$M4PY_OUT" --summary "$OUTROOT/summary-e1.csv" "${m[@]}"
		;;
	e3)
		mapfile -t m < <(e3)
		;;
	e4)
		require_clean_git
		calibrate_wl
		calibrate_mem
		mapfile -t m < <(e4)
		rebuild_summary
		;;
	rebuild-summary)
		rebuild_summary
		;;
	e2)
		e2_prep
		;;
	all)
		calibrate_wl
		calibrate_mem
		mapfile -t m1 < <(e1)
		mapfile -t m3 < <(e3)
		mapfile -t m4 < <(e4)
		all_manifest=("${m1[@]}" "${m4[@]}")
		"${M4_PYTHON[@]}" "$M4PY" --outdir "$M4PY_OUT" --summary "$OUTROOT/summary.csv" "${all_manifest[@]}"
		;;
	*)
		die "usage: m4.sh {calibrate|e1|e3|e4|e2|all}"
		;;
	esac
}

main "$@"
