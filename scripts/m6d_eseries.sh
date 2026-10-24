#!/usr/bin/env bash
# M6d phan A: E1, E3, E4-cache theo dung muc/co che cua scripts/m4.sh,
# KHONG sua m4.sh. Them: 3 lan/muc, freq_stamp truoc/sau moi muc,
# collector -pmu on (E1/E4) hoac -pmu host (E3), giu .bin, rec-export TSV.
# Muc (doc tu m4.sh): E1 L=0 1 2 3; E3 idle + stress2; E4-cache n=0 4 12 22.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:-validation/m6d-$(date +%Y%m%d)}"
mkdir -p "$OUTROOT"
WL=./bin/wl
COLLECT=./bin/hids-collect
EXPORT=./bin/rec-export
E3BIN=./bin/m4_e3
LOOPS_FILE=out/m4-loops.txt
WL_CPU=20
RUNS=3

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
	return 1
}
read_burn_loops() { awk '/^burn_loops/{print $2}' "$LOOPS_FILE"; }

calibrate() {
	local fifo wl_pid
	fifo=$(mktemp -u)
	mkfifo "$fifo" || return 1
	echo "m6d: hieu chuan wl tren CPU $WL_CPU (may ranh)..." | tee -a "$OUTROOT/calibrate.txt"
	taskset -c "$WL_CPU" "$WL" mixed 1 <"$fifo" >"$OUTROOT/cal-wl.log" 2>&1 &
	wl_pid=$!
	sleep 3
	[[ -s $LOOPS_FILE ]] || { echo "hieu chuan wl that bai" >&2; return 1; }
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	echo "m6d: hieu chuan mem tren CPU $WL_CPU..." | tee -a "$OUTROOT/calibrate.txt"
	taskset -c "$WL_CPU" "$WL" mem 1 >"$OUTROOT/cal-mem.log" 2>&1 &
	wl_pid=$!
	sleep 20
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	local ms
	ms=$(awk '/^mem_steps/{print $2}' "$LOOPS_FILE")
	[[ -n $ms && $ms -gt 0 ]] || { echo "mem hieu chuan that bai" >&2; return 1; }
	echo "calibrate xong: burn_loops=$(read_burn_loops) mem_steps=$ms" | tee -a "$OUTROOT/calibrate.txt"
}

freq_pair() {
	# freq_pair <tag> <cpu> — in truoc, chay callback qua bien FREQ_TAG, in sau.
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/freq-${tag}-truoc.txt" 2>&1
	FREQ_BEFORE=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/freq-${tag}-truoc.txt")
}

freq_after() {
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/freq-${tag}-sau.txt" 2>&1
	FREQ_AFTER=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/freq-${tag}-sau.txt")
	python3 - "$FREQ_BEFORE" "$FREQ_AFTER" "$tag" <<'PY' | tee -a "$OUTROOT/freq-lech.txt"
import sys
a, b, tag = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
lech = abs(b - a) / a * 100 if a else float("nan")
note = " LECH_>2%" if lech > 2 else ""
print(f"freq {tag}: truoc={a:.4f} sau={b:.4f} lech={lech:.2f}%{note}")
PY
}

# run_wl_mixed nhu m4.sh (dong 176-198) + -pmu <mode>, retry KHONG_READY.
run_wl_mixed_pmu() {
	local loops=$1 rounds=$2 pmu=$3 outdir=$4 attempt_max=${5:-3}
	local attempt prefix fifo wl_pid cpid bin
	for attempt in $(seq 1 "$attempt_max"); do
		prefix="$outdir/wl-$(date +%H%M%S)-$attempt"
		fifo="$prefix.fifo"
		bin="$prefix.bin"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		taskset -c "$WL_CPU" "$WL" -loops "$loops" mixed "$rounds" <"$fifo" >"$prefix-wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.5
		"$COLLECT" -pid "$wl_pid" -pmu "$pmu" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		if ! wait_ready "$prefix-collect.log"; then
			echo "KHONG_READY" >>"$prefix-collect.log"
			kill "$wl_pid" "$cpid" 2>/dev/null; wait "$wl_pid" 2>/dev/null || true
			exec 9>&-; rm -f "$fifo"
			continue
		fi
		printf '.\n' >&9
		wait_wl_read "$wl_pid" || true
		printf '.\n' >&9
		wait "$wl_pid" 2>/dev/null || true
		printf '.\n' >&9
		wait "$cpid" 2>/dev/null || true
		exec 9>&-
		rm -f "$fifo"
		echo "$bin|$wl_pid|$attempt"
		return 0
	done
	return 1
}

run_wl_mem_pmu() {
	local loops=$1 rounds=$2 pmu=$3 outdir=$4 attempt_max=${5:-3}
	local attempt prefix fifo wl_pid cpid bin
	for attempt in $(seq 1 "$attempt_max"); do
		prefix="$outdir/wl-$(date +%H%M%S)-$attempt"
		fifo="$prefix.fifo"
		bin="$prefix.bin"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		taskset -c "$WL_CPU" "$WL" -loops "$loops" mem "$rounds" <"$fifo" >"$prefix-wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.5
		"$COLLECT" -pid "$wl_pid" -pmu "$pmu" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		if ! wait_ready "$prefix-collect.log"; then
			echo "KHONG_READY" >>"$prefix-collect.log"
			kill "$wl_pid" "$cpid" 2>/dev/null; wait "$wl_pid" 2>/dev/null || true
			exec 9>&-; rm -f "$fifo"
			continue
		fi
		printf '.\n' >&9
		wait_wl_read "$wl_pid" || true
		printf '.\n' >&9
		wait "$wl_pid" 2>/dev/null || true
		printf '.\n' >&9
		wait "$cpid" 2>/dev/null || true
		exec 9>&-
		rm -f "$fifo"
		echo "$bin|$wl_pid|$attempt"
		return 0
	done
	return 1
}

analyze_burn() {
	# analyze_burn <csv> <tid> <out_txt> [mode=burn|e3]
	local csv=$1 tid=$2 out=$3 mode=${4:-burn}
	python3 - "$csv" "$tid" "$out" "$mode" <<'PY'
import csv, statistics, sys
path, tid, out, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
rows = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) != tid:
            continue
        if int(r["flags"]) & 1:
            continue
        rows.append(r)
if mode == "e3":
    # nhu m4.sh: ban ghi vol_ns lon nhat
    if not rows:
        open(out, "w").write("e3: khong co ban ghi\n"); sys.exit(0)
    r = max(rows, key=lambda x: int(x["vol_ns"]))
    lines = [
        f"e3_syscall_nr={r['syscall_nr']}",
        f"cpu_ns={r['cpu_ns']}",
        f"steal_ns={r['steal_ns']}",
        f"irq_ns={r['irq_ns']}",
        f"rq_ns={r['rq_ns']}",
        f"vol_us={int(r['vol_ns']) // 1000}",
        f"steal_off_ns={r['steal_off_ns']}",
        f"inst={r['inst']}",
        f"cyc={r['cyc']}",
        f"pmu_ok={r['pmu_ok']}",
        f"CPI=na" if int(r["pmu_ok"]) != 1 or int(r["inst"]) == 0 else f"CPI={int(r['cyc']) / int(r['inst']):.4f}",
        f"GHz=na" if int(r["pmu_ok"]) != 1 or int(r["cpu_ns"]) == 0 else f"GHz={int(r['cyc']) / int(r['cpu_ns']):.4f}",
        f"so_khoang=1",
    ]
    open(out, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    sys.exit(0)

from collections import Counter
cnt = Counter(int(r["syscall_nr"]) for r in rows)
burn_nr = 230 if cnt.get(230, 0) >= cnt.get(35, 0) else 35
burn = [r for r in rows if int(r["syscall_nr"]) == burn_nr]
ok = [r for r in burn if int(r["pmu_ok"]) == 1]
def med(xs):
    return statistics.median(xs) if xs else float("nan")
cpu = [int(r["cpu_ns"]) for r in burn]
rq = [int(r["rq_ns"]) for r in burn]
steal = [int(r["steal_ns"]) for r in burn]
irq = [int(r["irq_ns"]) for r in burn]
vol_us = [int(r["vol_ns"]) // 1000 for r in burn]
off = [int(r["steal_off_ns"]) for r in burn]
inst = [int(r["inst"]) for r in ok]
cyc = [int(r["cyc"]) for r in ok]
cpi = [c / i for c, i in zip(cyc, inst) if i > 0]
ghz = [c / u for c, u in zip(cyc, [int(r["cpu_ns"]) for r in ok]) if u > 0]
lines = [
    f"burn_nr={burn_nr} so_khoang={len(burn)} so_pmu={len(ok)}",
    f"cpu_ns={med(cpu):.1f}",
    f"rq_ns={med(rq):.1f}",
    f"steal_ns={med(steal):.1f}",
    f"irq_ns={med(irq):.1f}",
    f"vol_us={med(vol_us):.1f}",
    f"steal_off_ns={med(off):.1f}",
    f"inst={med(inst):.1f}" if ok else "inst=na",
    f"cyc={med(cyc):.1f}" if ok else "cyc=na",
    f"CPI={med(cpi):.4f}" if cpi else "CPI=na",
    f"GHz={med(ghz):.4f}" if ghz else "GHz=na",
]
open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
}

# ---------- E1 ----------
run_e1() {
	local loops L run stress_pids=() i result bin tid attempt dir
	loops=$(read_burn_loops)
	mkdir -p "$OUTROOT/E1"
	echo "=== E1 muc (m4.sh dong 235): L in 0 1 2 3; stress-ng --cpu 1 --taskset $WL_CPU; wl -loops mixed 500; -pmu on ===" | tee "$OUTROOT/E1/muc.txt"
	for L in 0 1 2 3; do
		freq_pair "E1-L$L" "$WL_CPU"
		for run in $(seq 1 "$RUNS"); do
			dir="$OUTROOT/E1/L$L/run$run"
			mkdir -p "$dir"
			if ((${#stress_pids[@]})); then
				for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
			fi
			stress_pids=()
			for ((i = 0; i < L; i++)); do
				stress-ng --cpu 1 --taskset "$WL_CPU" --timeout 120 >"$dir/stress-$i.log" 2>&1 &
				stress_pids+=($!)
			done
			sleep 1
			result=$(run_wl_mixed_pmu "$loops" 500 on "$dir") || { echo "E1 L$L run$run THAT BAI" | tee -a "$OUTROOT/E1/errors.txt"; continue; }
			bin=${result%%|*}; rest=${result#*|}; tid=${rest%%|*}; attempt=${rest##*|}
			cp "$bin" "$dir/collect.bin"
			"$EXPORT" "$bin" >"$dir/export.csv"
			analyze_burn "$dir/export.csv" "$tid" "$dir/ketqua.txt" burn | tee "$dir/ketqua.tee"
			echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$dir/ketqua.txt"
			echo "so_attempt=$attempt" >>"$dir/ketqua.txt"
			echo "wl: taskset -c $WL_CPU $WL -loops $loops mixed 500" >>"$dir/ketqua.txt"
			echo "E1 L=$L run=$run attempt=$attempt bin=$bin" | tee -a "$OUTROOT/E1/progress.txt"
		done
		if ((${#stress_pids[@]})); then
			for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
		fi
		stress_pids=()
		freq_after "E1-L$L" "$WL_CPU"
		echo "GHz_wall_sau=$FREQ_AFTER" >"$OUTROOT/E1/L$L/freq.txt"
		echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$OUTROOT/E1/L$L/freq.txt"
	done
}

# ---------- E3 ----------
run_e3_once() {
	local tag=$1 stress_n=$2 run=$3 pmu=host
	local dir port lip stress_pids=() i prefix bin fifo wp cpid attempt
	dir="$OUTROOT/E3/$tag/run$run"
	mkdir -p "$dir"
	for attempt in 1 2 3; do
		port=$((19000 + RANDOM % 1000))
		python3 -c "import socket;s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',$port));s.listen(1);s.accept();s.close()" &
		lip=$!
		stress_pids=()
		for ((i = 0; i < stress_n; i++)); do
			stress-ng --cpu 1 --taskset "$WL_CPU" --timeout 400 >"$dir/stress-$i.log" 2>&1 &
			stress_pids+=($!)
		done
		sleep 1
		prefix="$dir/e3-$attempt"
		bin="$prefix.bin"
		fifo="$prefix.fifo"
		mkfifo "$fifo"
		exec 8<>"$fifo"
		"$E3BIN" "$port" <"$fifo" >"$prefix-e3.log" 2>&1 &
		wp=$!
		"$COLLECT" -pid "$wp" -pmu "$pmu" -duration 400s -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		if ! wait_ready "$prefix-collect.log"; then
			echo "KHONG_READY" >>"$prefix-collect.log"
			kill "$wp" "$cpid" "$lip" 2>/dev/null
			wait "$wp" 2>/dev/null || true
			exec 8>&-; rm -f "$fifo"
			for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
			continue
		fi
		printf '.' >&8
		wait "$wp" 2>/dev/null || true
		exec 8>&-
		rm -f "$fifo"
		wait "$cpid" 2>/dev/null || true
		kill "$lip" 2>/dev/null; wait "$lip" 2>/dev/null || true
		for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
		cp "$bin" "$dir/collect.bin"
		"$EXPORT" "$bin" >"$dir/export.csv"
		analyze_burn "$dir/export.csv" "$wp" "$dir/ketqua.txt" e3 | tee "$dir/ketqua.tee"
		echo "so_attempt=$attempt" >>"$dir/ketqua.txt"
		echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$dir/ketqua.txt"
		echo "E3 $tag run=$run attempt=$attempt" | tee -a "$OUTROOT/E3/progress.txt"
		return 0
	done
	return 1
}

run_e3() {
	mkdir -p "$OUTROOT/E3"
	echo "=== E3 muc (m4.sh dong 303-305): idle (stress_n=0), stress2 (stress_n=2); m4_e3 + -pmu host ===" | tee "$OUTROOT/E3/muc.txt"
	local tag stress_n run
	for pair in "idle:0" "stress2:2"; do
		tag=${pair%%:*}; stress_n=${pair##*:}
		freq_pair "E3-$tag" "$WL_CPU"
		for run in $(seq 1 "$RUNS"); do
			run_e3_once "$tag" "$stress_n" "$run" || echo "E3 $tag run$run THAT BAI" | tee -a "$OUTROOT/E3/errors.txt"
		done
		freq_after "E3-$tag" "$WL_CPU"
		echo "GHz_wall_sau=$FREQ_AFTER" >"$OUTROOT/E3/$tag/freq.txt"
		echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$OUTROOT/E3/$tag/freq.txt"
	done
}

# ---------- E4-cache ----------
run_e4_cache() {
	local loops n run w stress_pids=() result bin tid attempt dir cpus="0-19,21-23"
	loops=$(read_burn_loops)
	mkdir -p "$OUTROOT/E4-cache"
	echo "=== E4-cache muc (m4.sh dong 329): n in 0 4 12 22; stress-ng --cache 1 --taskset 0-19,21-23; wl -loops mem 500; -pmu on ===" | tee "$OUTROOT/E4-cache/muc.txt"
	for n in 0 4 12 22; do
		freq_pair "E4c-L$n" "$WL_CPU"
		for run in $(seq 1 "$RUNS"); do
			dir="$OUTROOT/E4-cache/L$n/run$run"
			mkdir -p "$dir"
			stress_pids=()
			for ((w = 0; w < n; w++)); do
				stress-ng --cache 1 --taskset "$cpus" --timeout 120 >"$dir/stress-$w.log" 2>&1 &
				stress_pids+=($!)
			done
			sleep 2
			result=$(run_wl_mem_pmu "$loops" 500 on "$dir") || { echo "E4c L$n run$run THAT BAI" | tee -a "$OUTROOT/E4-cache/errors.txt"; for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done; continue; }
			bin=${result%%|*}; rest=${result#*|}; tid=${rest%%|*}; attempt=${rest##*|}
			for p in "${stress_pids[@]}"; do kill "$p" 2>/dev/null; done
			cp "$bin" "$dir/collect.bin"
			"$EXPORT" "$bin" >"$dir/export.csv"
			analyze_burn "$dir/export.csv" "$tid" "$dir/ketqua.txt" burn | tee "$dir/ketqua.tee"
			echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$dir/ketqua.txt"
			echo "so_attempt=$attempt" >>"$dir/ketqua.txt"
			echo "wl: taskset -c $WL_CPU $WL -loops $loops mem 500" >>"$dir/ketqua.txt"
			echo "E4-cache L=$n run=$run attempt=$attempt" | tee -a "$OUTROOT/E4-cache/progress.txt"
		done
		freq_after "E4c-L$n" "$WL_CPU"
		echo "GHz_wall_sau=$FREQ_AFTER" >"$OUTROOT/E4-cache/L$n/freq.txt"
		echo "GHz_wall_truoc=$FREQ_BEFORE" >>"$OUTROOT/E4-cache/L$n/freq.txt"
	done
}

echo "=== muc dung (trich tu scripts/m4.sh) ===" | tee "$OUTROOT/muc-m4.txt"
{
	echo "E1: for L in 0 1 2 3; stress-ng --cpu 1 --taskset \$WL_CPU; run_wl_mixed loops 500 (m4.sh:231-250)"
	echo "E3: e3_once idle 0; e3_once stress2 2 (m4.sh:303-305)"
	echo "E4-cache: for n in 0 4 12 22; stress-ng --cache 1 --taskset 0-19,21-23; run_wl_mem loops 500 (m4.sh:308-330)"
	echo "E4-stream: KHONG chay lai (da co R034)"
} | tee -a "$OUTROOT/muc-m4.txt"

calibrate || exit 1
run_e1
run_e3
run_e4_cache
echo "m6d E-series (A) xong: $OUTROOT"

# Tong hop bang (3 lan + trung vi) cho bao cao
python3 - "$OUTROOT" <<'PY'
import os, statistics, sys
from pathlib import Path
root = Path(sys.argv[1])

def load_kq(p):
    d = {}
    if not p.exists():
        return None
    for line in p.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip()
    return d

def fnum(s):
    try:
        return float(s)
    except Exception:
        return float("nan")

def summarize(exp, levels, key_fn):
    out = []
    out.append(f"=== {exp} ===")
    header = "muc\trun\tcpu_ns\trq_ns\tsteal_ns\tirq_ns\tvol_us\tCPI\tinst\tGHz\tGHz_wall_truoc\tGHz_wall_sau"
    out.append(header)
    for lv in levels:
        vals = {k: [] for k in ("cpu_ns","rq_ns","steal_ns","irq_ns","vol_us","CPI","inst","GHz")}
        freq = load_kq(root / exp / key_fn(lv) / "freq.txt") or {}
        for run in (1, 2, 3):
            kq = load_kq(root / exp / key_fn(lv) / f"run{run}" / "ketqua.txt")
            if not kq:
                out.append(f"{lv}\t{run}\tTHIEU")
                continue
            row = [str(lv), str(run)]
            for k in ("cpu_ns","rq_ns","steal_ns","irq_ns","vol_us","CPI","inst","GHz"):
                v = kq.get(k, "na")
                row.append(v)
                if v not in ("na",) and v.replace(".","").replace("-","").isdigit() or (v.count(".")==1 and v.replace(".","").replace("-","").isdigit()):
                    try:
                        vals[k].append(float(v))
                    except Exception:
                        pass
                else:
                    try:
                        vals[k].append(float(v))
                    except Exception:
                        pass
            row.append(freq.get("GHz_wall_truoc", kq.get("GHz_wall_truoc","na")))
            row.append(freq.get("GHz_wall_sau","na"))
            out.append("\t".join(row))
        med = [str(lv), "trung_vi"]
        for k in ("cpu_ns","rq_ns","steal_ns","irq_ns","vol_us","CPI","inst","GHz"):
            xs = [x for x in vals[k] if x == x]
            med.append(f"{statistics.median(xs):.4f}" if xs else "na")
        med.append(freq.get("GHz_wall_truoc","na"))
        med.append(freq.get("GHz_wall_sau","na"))
        out.append("\t".join(med))
        # ti le so muc 0 neu co
    return "\n".join(out)

parts = []
parts.append(summarize("E1", [0,1,2,3], lambda L: f"L{L}"))
parts.append(summarize("E3", ["idle","stress2"], lambda t: t))
parts.append(summarize("E4-cache", [0,4,12,22], lambda n: f"L{n}"))
text = "\n\n".join(parts) + "\n"
(root / "bang-tong-hop.tsv").write_text(text)
print(text)
PY
