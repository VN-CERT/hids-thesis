#!/usr/bin/env bash
# m6b11_diag.sh <variant> <outdir> [extra collector args...]
# Chay collector 5 phut dung cau hinh 24h (2 cgroup), ghi top/perf/CPU.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

VARIANT="${1:?variant}"
OUT="${2:?outdir}"
shift 2
mkdir -p "$OUT" out/jobs

CG_REDIS=/sys/fs/cgroup/system.slice/docker-7421d7ae79685498cdaf7b24ea4426cccb9531070b12a3265fdf9d1738fdb592.scope
CG_QDRANT=/sys/fs/cgroup/system.slice/docker-319c38ff33aa4827288f68ca1236600174cf278175fd7d5d68657d48e2a6366f.scope

HZ=$(getconf CLK_TCK)
cpu_ticks() {
	# utime(14)+stime(15) trong /proc/<pid>/stat (sau dau ')' cuoi)
	awk '{n=split($0,a,")"); split(a[n],b," "); print b[12]+b[13]}' "/proc/$1/stat"
}

echo "variant=$VARIANT start=$(date -Is)" | tee "$OUT/run-meta.txt"
echo "extra_args: $*" | tee -a "$OUT/run-meta.txt"
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py | tee "$OUT/architect-sha256.txt"
git rev-parse --short HEAD | tee "$OUT/git-head.txt"

./bin/hids-collect -datadir "$OUT/data" -cgroup "$CG_REDIS" -cgroup "$CG_QDRANT" \
	-duration 5m -min-free-gb 50 "$@" >"$OUT/collect.log" 2>&1 &
CPID=$!
echo "collector_pid=$CPID" | tee -a "$OUT/run-meta.txt"

for _ in $(seq 1 600); do
	grep -qx READY "$OUT/collect.log" 2>/dev/null && break
	kill -0 "$CPID" 2>/dev/null || { cat "$OUT/collect.log"; echo "collector chet som" >&2; exit 1; }
	sleep 0.1
done
grep -qx READY "$OUT/collect.log" || { cat "$OUT/collect.log"; echo "khong READY" >&2; exit 1; }

# Mau CPU /proc moi 10 giay
(
	echo -e "wall\tcpu_ticks\tcpu_seconds"
	prev=""
	for _ in $(seq 1 29); do
		if kill -0 "$CPID" 2>/dev/null; then
			t=$(cpu_ticks "$CPID" || echo 0)
			echo -e "$(date -Is)\t$t\t$(awk -v t="$t" -v hz="$HZ" 'BEGIN{printf "%.3f", t/hz}')"
		fi
		sleep 10
	done
) >"$OUT/cpu-proc.tsv" &
SAMPLER=$!

sleep 5
top -b -n1 -H -p "$CPID" | head -20 >"$OUT/top-H.txt" || true
cat "$OUT/top-H.txt"

if [[ ${DIAG_PERF:-1} == 1 ]]; then
	perf record -F 99 -g -p "$CPID" -o "$OUT/perf.data" -- sleep 60 >"$OUT/perf-record.log" 2>&1 || true
	perf report -i "$OUT/perf.data" --stdio --no-children 2>/dev/null | head -60 >"$OUT/perf-report.txt" || true
fi

wait "$CPID" || true
kill "$SAMPLER" 2>/dev/null || true
wait "$SAMPLER" 2>/dev/null || true

echo "end=$(date -Is)" >>"$OUT/run-meta.txt"
# Tom tat CPU tu status.tsv cua collector
if [[ -f "$OUT/data/status.tsv" ]]; then
	{
		echo "--- status.tsv (nguyen van) ---"
		cat "$OUT/data/status.tsv"
		echo "--- delta cpu_seconds giua cac dong status (moi ~60s) ---"
		awk -F'\t' 'NR==2{prev=$8; pw=$1; next} NR>2{d=$8-prev; printf "%s -> %s delta_cpu=%.3f s ti_le_loi=%.2f%%\n", pw, $1, d, d/60*100; prev=$8; pw=$1}' "$OUT/data/status.tsv"
	} | tee "$OUT/cpu-status-summary.txt"
fi
# Tom tat CPU tu /proc sampler: delta moi mau 10s gom thanh phut dau
awk -F'\t' 'NR>1{print}' "$OUT/cpu-proc.tsv" | head -40 | tee "$OUT/cpu-proc-head.txt" >/dev/null || true
echo "diag xong variant=$VARIANT"
