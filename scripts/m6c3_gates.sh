#!/usr/bin/env bash
# M6c-3 phan 3: G7a x4, G3 sample=20 + on, G11 hoi quy, G11s, T1 chi phi theo K.
# Container dung (driver ben ngoai lo). Moi khoi do co freq_stamp truoc/sau.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"
COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "KHONG_READY (cho 20s)" >&2
	return 1
}
pmu_line() { grep -a "^# pmu" "$1" | head -2; }

bash scripts/freq_stamp.sh 12 >"$OUTROOT/freq-truoc.txt" 2>&1

echo "=== G7a x4 ===" | tee "$OUTROOT/g7a.txt"
for mode in host on sample=20 sample=50; do
	echo "--- G7a -pmu $mode ---" >>"$OUTROOT/g7a.txt"
	HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu $mode" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a.txt" 2>&1
done
python3 - <<'PY' | tee "$OUTROOT/g7a-pmu-headers.txt"
import glob, os, subprocess
for p in sorted(glob.glob("out/g7a-*.bin"), key=os.path.getmtime)[-4:]:
    hdr = subprocess.run(["python3", "-c", """
import sys
with open(sys.argv[1],'rb') as f:
    for line in f:
        s=line.decode('utf8','replace').rstrip()
        if 'pmu' in s: print(s)
        if s.strip()=='#END': break
""", p], capture_output=True, text=True).stdout
    print(p)
    print(hdr)
PY

echo "=== G3 -pmu sample=20 ==="
HIDS_COLLECT_EXTRA="-pmu sample=20" bash scripts/m6b12_g3.sh stop "$OUTROOT/g3-sample20" || echo "g3 exit=$?"
echo "=== G3 -pmu on (hoi quy) ==="
HIDS_COLLECT_EXTRA="-pmu on" bash scripts/m6b12_g3.sh stop "$OUTROOT/g3-on" || echo "g3 exit=$?"

echo "=== ti le co PMU (rec-stat) ===" | tee "$OUTROOT/pmu-ratio.txt"
for d in g3-sample20 g3-on; do
	for f in "$OUTROOT/$d"/g3/S*.bin; do
		[[ -f $f ]] || continue
		echo "--- $d $(basename "$f") ---" >>"$OUTROOT/pmu-ratio.txt"
		./bin/rec-stat "$f" >>"$OUTROOT/pmu-ratio.txt" 2>&1
	done
done
grep -E "^---|PMU|pmu" "$OUTROOT/pmu-ratio.txt" | head -40

echo "=== G11 (-pmu on, hoi quy) ==="
bash scripts/m6c_g11.sh "$OUTROOT/g11" >"$OUTROOT/g11.log" 2>&1 || echo "g11 exit=$?"
cat "$OUTROOT/g11"/*.txt 2>/dev/null | head -30

echo "=== G11s ==="
bash scripts/m6c3_g11s.sh "$OUTROOT/g11s" 2>&1 | tee "$OUTROOT/g11s.txt"

echo "=== T1 chi phi theo K ==="
TSV="$OUTROOT/T1.tsv"
echo "load cond run value" >"$TSV"
t1_cell() {
	local cond=$1 pmumode=$2 run=$3
	local dir="$OUTROOT/T1/$cond/run$run"
	mkdir -p "$dir"
	local fifo="$dir/in.fifo" spid t0 t1
	mkfifo "$fifo"
	exec 8<>"$fifo"
	taskset -c 12 "$SYSINJ" -n 10000000 <"$fifo" >"$dir/sysinj.log" 2>&1 &
	spid=$!
	sleep 0.3
	local cpid=""
	if [[ $cond != C0 ]]; then
		"$COLLECT" -pid "$spid" -pmu "$pmumode" -duration 60s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			echo "KHONG_READY t1-$cond-$run" | tee -a "$OUTROOT/T1.log"
			kill "$spid" "$cpid" 2>/dev/null; exec 8>&-; rm -f "$fifo"
			return 1
		fi
	fi
	t0=$(date +%s%N)
	printf '.' >&8
	wait "$spid" 2>/dev/null || true
	t1=$(date +%s%N)
	exec 8>&-
	rm -f "$fifo"
	[[ -n $cpid ]] && { kill -INT "$cpid" 2>/dev/null; wait "$cpid" 2>/dev/null || true; }
	python3 -c "print(f'{($t1 - $t0) / 10000000:.2f}')" >"$dir/value.txt"
	echo "T1 $cond run$run $(cat "$dir/value.txt")" >>"$OUTROOT/T1.log"
	echo "T1 $cond $run $(cat "$dir/value.txt")" >>"$TSV"
}
for run in 1 2 3 4 5 6 7 8 9 10; do
	t1_cell C0 "" "$run" || true
	t1_cell C1-host host "$run" || true
	t1_cell C1-sample50 sample=50 "$run" || true
	t1_cell C1-sample20 sample=20 "$run" || true
	t1_cell C1-on on "$run" || true
done
python3 analysis/m6c_stats.py "$TSV" | tee "$OUTROOT/T1.stats.txt"

bash scripts/freq_stamp.sh 12 >"$OUTROOT/freq-sau.txt" 2>&1
echo "m6c3 gates xong"
