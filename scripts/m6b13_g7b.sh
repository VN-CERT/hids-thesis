#!/usr/bin/env bash
# m6b13_g7b.sh <outdir> <extra-args-string>
# Chay G7b (24 x 1.000.000, -zstd-level 0) 5 lan; moi lan bao mat + toc do thuc te.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

OUT="${1:?outdir}"
EXTRA="${2:-"-zstd-level 0"}"
mkdir -p "$OUT"
echo "extra=$EXTRA start=$(date -Is)" | tee "$OUT/run-meta.txt"
git rev-parse --short HEAD | tee -a "$OUT/run-meta.txt"

: >"$OUT/summary.txt"
for i in 1 2 3 4 5; do
	f="$OUT/run$i.txt"
	HIDS_COLLECT_EXTRA="$EXTRA" bash scripts/g7.sh b 1000000 >"$f" 2>&1
	mat=$(grep -E 'tong bo dem mat \(ring buffer day\)' "$f" | tail -1 | awk -F: '{gsub(/[ \t]/,"",$2); print $2}')
	rec=$(grep -E '^tong ban ghi doc duoc' "$f" | tail -1 | awk -F: '{gsub(/[ \t]/,"",$2); print $2}')
	t=$(grep -E 'thoi gian chay' "$f" | tail -1 | sed -n 's/.*thoi gian chay: \([0-9.]*\) s.*/\1/p')
	rate=$(awk -v r="${rec:-0}" -v t="${t:-0}" 'BEGIN{if(t>0)printf "%.0f", r/t; else print "?"}')
	echo "run$i mat=${mat:-?} ban_ghi=${rec:-?} thoi_gian=${t:-?}s toc_do=${rate} ban_ghi/giay" | tee -a "$OUT/summary.txt"
done
echo "xong $(date -Is)" | tee -a "$OUT/summary.txt"
