#!/usr/bin/env bash
# m6b12_rate.sh <rate_per_sec> <outdir>
# Duong CPU theo toc do: sysinj bom <rate> syscall/giay trong cgroup rieng,
# collector (-rb-poll mac dinh) do 2 phut. Bao CPU % mot loi + toc do dat duoc.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

RATE="${1:?rate_per_sec}"
OUT="${2:?outdir}"
mkdir -p "$OUT"
CG=/sys/fs/cgroup/hids-rate
rmdir "$CG" 2>/dev/null || true
mkdir -p "$CG"

echo "rate_target=$RATE start=$(date -Is)" | tee "$OUT/run-meta.txt"
git rev-parse --short HEAD | tee -a "$OUT/run-meta.txt"

./bin/hids-collect -datadir "$OUT/data" -cgroup "$CG" ${HIDS_COLLECT_EXTRA:-} -duration 150s -min-free-gb 50 \
	>"$OUT/collect.log" 2>&1 &
PID=$!
echo "collector_pid=$PID" | tee -a "$OUT/run-meta.txt"
for _ in $(seq 1 600); do
	grep -qx READY "$OUT/collect.log" 2>/dev/null && break
	kill -0 "$PID" 2>/dev/null || { cat "$OUT/collect.log"; exit 1; }
	sleep 0.1
done

# Mau CPU /proc moi 10 giay
(
	echo -e "wall\tticks\tcpu_seconds"
	for _ in $(seq 1 14); do
		if kill -0 "$PID" 2>/dev/null; then
			t=$(awk '{n=split($0,a,")"); split(a[n],b," "); print b[12]+b[13]}' "/proc/$PID/stat" || echo 0)
			echo -e "$(date -Is)\t$t\t$(awk -v t="$t" 'BEGIN{printf "%.3f", t/100}')"
		fi
		sleep 10
	done
) >"$OUT/cpu-proc.tsv" &
SAMPLER=$!

# Pacer: moi giay bom dung RATE syscall (getppid) trong cgroup
(
	echo "$BASHPID" >"$CG/cgroup.procs"
	end=$((SECONDS + 120))
	while (( SECONDS < end )); do
		s=$(date +%s%N)
		printf x | ./bin/sysinj -n "$RATE" >/dev/null 2>&1
		e=$(date +%s%N)
		rem=$(awk -v s="$s" -v e="$e" 'BEGIN{r=1-(e-s)/1e9; if(r<0)r=0; printf "%.3f", r}')
		sleep "$rem"
	done
) &
PACER=$!

wait "$PACER" || true
wait "$PID" || true
kill "$SAMPLER" 2>/dev/null || true
wait "$SAMPLER" 2>/dev/null || true
rmdir "$CG" 2>/dev/null || true

{
	echo "--- cpu-proc.tsv ---"
	cat "$OUT/cpu-proc.tsv"
	echo "--- tom tat ---"
	awk -F'\t' 'NR==2{first=$3} NR>1{last=$3; n++} END{printf "cpu_delta=%.3f s tren %d mau (10s/mau) cpu_%%_mot_loi=%.2f%%\n", last-first, n, (last-first)/((n-1)*10)*100}' "$OUT/cpu-proc.tsv"
	echo "status dong cuoi:"
	tail -1 "$OUT/data/status.tsv"
	echo "tong ban ghi doc duoc (tu .bin.stats):"
	grep -h "so_ban_ghi_doc_duoc" "$OUT"/data/*.bin.stats || true
	grep -h "so_ban_ghi_doc_duoc" "$OUT"/data/*.bin.stats | awk -F: '{s+=$2} END{printf "TONG_BAN_GHI=%d toc_do_dat_duoc_uoc_tinh=%.0f ban_ghi/giay (chia 120s)\n", s, s/120}'
} | tee "$OUT/rate-summary.txt"
