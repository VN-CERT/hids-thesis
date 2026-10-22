#!/usr/bin/env bash
# M6c-3: chay thu cau hinh 24 gio trong 10 phut voi -pmu sample=20 (-datadir,
# nhu pre24h host10m: -pid cua script nay). Do CPU/RSS cua collector, kernel
# drops, proc drops, host lines (cong moi doan), ti le co PMU trong .bin.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUT="${1:?can thu muc output}"
mkdir -p "$OUT/data"
bash scripts/freq_stamp.sh 12 >"$OUT/freq-truoc.txt" 2>&1
./bin/hids-collect -datadir "$OUT/data" -pid $$ -duration 10m -pmu sample=20 >"$OUT/run.log" 2>&1 &
CPID=$!
# Cho READY (toi da 20s) theo quy tac M6c-1.
for ((i = 0; i < 2000; i++)); do grep -qx READY "$OUT/run.log" 2>/dev/null && break; sleep 0.01; done
grep -qx READY "$OUT/run.log" || echo "KHONG_READY" | tee -a "$OUT/run.log"
CLK=$(getconf CLK_TCK)
prev_j=$(awk '{print $14 + $15}' "/proc/$CPID/stat" 2>/dev/null || echo 0)
t0=$(date +%s)
cpu_max=0
while kill -0 "$CPID" 2>/dev/null; do
	sleep 10
	kill -0 "$CPID" 2>/dev/null || break
	now_j=$(awk '{print $14 + $15}' "/proc/$CPID/stat" 2>/dev/null || echo "$prev_j")
	rss=$(awk '/VmRSS/{print $2}' "/proc/$CPID/status" 2>/dev/null || echo 0)
	echo "$(date -Is) cpu_jiffies_delta=$((now_j - prev_j)) rss_kb=$rss" >>"$OUT/cpu-rss.tsv"
	prev_j=$now_j
done
wait "$CPID" 2>/dev/null || true
t1=$(date +%s)
{
	echo "thoi_gian_thuc_s=$((t1 - t0))"
	echo "tong cpu_jiffies (utime+stime, $CLK Hz):"
	awk -F'[= ]' '{s += $3} END {print s}' "$OUT/cpu-rss.tsv" 2>/dev/null || true
	echo "rss_kb cuoi:"
	tail -1 "$OUT/cpu-rss.tsv" 2>/dev/null || true
	echo "host lines (cong moi doan host-*.tsv.zst, tru header moi doan):"
	total=0
	for f in "$OUT"/data/host-*.tsv.zst; do
		[[ -e $f ]] || continue
		n=$(zstdcat "$f" | wc -l)
		total=$((total + n - 1))
	done
	echo "host_lines=$total"
	echo "hai cot PMU cua host stream (3 dong cuoi):"
	zstdcat "$OUT"/data/host-*.tsv.zst 2>/dev/null | tail -3 | awk -F'\t' '{print $(NF - 1), $NF}'
	echo "kernel drops + proc drops (dong cuoi .periodic / run.log):"
	tail -2 "$OUT"/data/*.bin.periodic 2>/dev/null | tail -2
	grep -E "kernel|proc" "$OUT/run.log" | tail -4
	echo "ti le co PMU trong .bin (rec-stat tung file):"
	for f in "$OUT"/data/*.bin; do
		[[ -e $f ]] || continue
		./bin/rec-stat "$f" 2>&1 | grep -iE "pmu|tong so ban ghi" || true
	done
} | tee "$OUT/tomtat.txt"
bash scripts/freq_stamp.sh 12 >"$OUT/freq-sau.txt" 2>&1
echo "pre24h10 xong"
