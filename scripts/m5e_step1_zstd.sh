#!/usr/bin/env bash
# M5e buoc 1: G7a/G7b zstd mac dinh, rec-stat dem sau nen.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
OUT="${M5E_ZSTD_OUT:-validation/m5e-$(date +%Y%m%d)/step1-zstd}"
RECSTAT=./bin/rec-stat
mkdir -p "$OUT" out
unset HIDS_COLLECT_EXTRA
exec > >(tee -a "$OUT/run.log") 2>&1
echo "=== M5e step1 zstd $(date -Iseconds) ==="

G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh a 1000000 | tee "$OUT/g7a-zstd.txt"
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh b 1000000 | tee "$OUT/g7b-zstd.txt"

parse_g7() {
	local txt=$1 label=$2
	local mat diff rec perf
	mat=$(grep -E 'tong bo dem mat:' "$txt" | tail -1 | awk '{print $NF}')
	diff=$(grep -E 'tong \(perf - ban ghi\):' "$txt" | tail -1 | awk '{print $NF}')
	rec=$(grep -E 'tong ban ghi doc duoc:' "$txt" | tail -1 | awk '{print $NF}')
	perf=$(grep -E 'tong \(perf - ban ghi\):' "$txt" | tail -1 | awk '{print $(NF-1)}' || true)
	local bin
	bin=$(grep -oE 'out/g7[^ ]+\.bin' "$txt" | tail -1)
	local rs=0
	if [[ -n ${bin:-} && -f $bin ]]; then
		rs=$("$RECSTAT" -nr "$bin" 2>/dev/null | awk '/tong so ban ghi trong file/{print $NF; exit}')
	fi
	echo "$label mat=$mat perf_diff=$diff recstat=$rs collector_rec=$rec bin=$bin"
	[[ ${mat:-x} == 0 && ${diff:-x} == 0 ]] || return 1
	[[ -n ${bin:-} && -f $bin ]] && [[ ${rs:-0} == "${rec:-0}" ]]
}

parse_g7 "$OUT/g7a-zstd.txt" G7a
parse_g7 "$OUT/g7b-zstd.txt" G7b
echo "STEP1_ZSTD_PASS $(date -Iseconds)"
