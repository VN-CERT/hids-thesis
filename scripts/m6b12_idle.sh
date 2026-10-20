#!/usr/bin/env bash
# m6b12_idle.sh <outdir> [extra collector args...]
# Do CPU collector khi dich idle (0 ban ghi/giay): -pid tien trinh sleep, 70s.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

OUT="${1:?outdir}"
shift
mkdir -p "$OUT"

sleep 240 &
SLP=$!
trap 'kill $SLP 2>/dev/null || true' EXIT
./bin/hids-collect -datadir "$OUT/data" -pid "$SLP" -duration 70s -min-free-gb 50 "$@" >"$OUT/collect.log" 2>&1 &
PID=$!
echo "collector_pid=$PID sleep_pid=$SLP start=$(date -Is)" | tee "$OUT/run-meta.txt"
git rev-parse --short HEAD | tee -a "$OUT/run-meta.txt"

for _ in $(seq 1 600); do
	grep -qx READY "$OUT/collect.log" 2>/dev/null && break
	kill -0 "$PID" 2>/dev/null || { cat "$OUT/collect.log"; exit 1; }
	sleep 0.1
done

{
	echo -e "wall\tticks\tcpu_seconds"
	for _ in $(seq 1 6); do
		t=$(awk '{n=split($0,a,")"); split(a[n],b," "); print b[12]+b[13]}' "/proc/$PID/stat")
		echo -e "$(date -Is)\t$t\t$(awk -v t="$t" 'BEGIN{printf "%.3f", t/100}')"
		sleep 10
	done
} | tee "$OUT/cpu-proc.tsv"

wait "$PID" || true
{
	echo "--- tom tat idle ---"
	awk -F'\t' 'NR==2{first=$3} NR>1{last=$3} END{printf "cpu_delta_60s=%.3f s cpu_%%_mot_loi=%.2f%%\n", last-first, (last-first)/60*100}' "$OUT/cpu-proc.tsv"
	tail -1 "$OUT/data/status.tsv"
} | tee "$OUT/idle-summary.txt"
