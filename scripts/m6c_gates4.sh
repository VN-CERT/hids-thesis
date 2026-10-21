#!/usr/bin/env bash
# M6c cong phan 4: duong CPU collector theo toc do (-pmu on, 1k/10k/100k/500k,
# moi muc 2 phut nhu R030 qua m6b12_rate.sh) + G7-cap 1/2/4 tien trinh zstd mac dinh.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"

for rate in 1000 10000 100000 500000; do
	echo "=== rate $rate ==="
	HIDS_COLLECT_EXTRA="-pmu on" bash scripts/m6b12_rate.sh "$rate" "$OUTROOT/rate-$rate" || echo "rate $rate exit=$?"
done

for n in 1 2 4; do
	echo "=== G7-cap nproc=$n ==="
	G7_CAP_OUT="$OUTROOT/g7cap" G7_CAP_DURATION=60 G7_CAP_NPROC=$n bash scripts/m5f_g7cap2.sh || echo "g7cap $n exit=$?"
done

echo "gates4 xong"
