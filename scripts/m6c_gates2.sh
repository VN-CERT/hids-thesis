#!/usr/bin/env bash
# M6c cong phan 2: G3 x3 (-pmu on) + G3 x1 (-pmu off), dung container, mot collector;
# sau do G11 (S1/S3, perf stat) voi container van dung. Script nay tu dung/khoi dong
# container cho G11; m6b12_g3.sh tu lo phan G3.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"

for i in 1 2 3; do
	echo "=== G3 lan $i (-pmu on) ==="
	HIDS_COLLECT_EXTRA="-pmu on" bash scripts/m6b12_g3.sh stop "$OUTROOT/g3-on$i" || echo "g3-on$i exit=$?"
done

echo "=== G3 lan 4 (-pmu off) ==="
HIDS_COLLECT_EXTRA="-pmu off" bash scripts/m6b12_g3.sh stop "$OUTROOT/g3-off1" || echo "g3-off1 exit=$?"

echo "=== G11 (container dung) ==="
mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "dung container: ${RUNNING[*]}"
docker stop "${RUNNING[@]}" || true
n=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
echo "bpftool_hids_count_truoc_G11=$n"
bash scripts/m6c_g11.sh "$OUTROOT/g11" || echo "g11 exit=$?"
docker start "${RUNNING[@]}" || echo "LOI khoi dong lai container"
echo "container dang chay sau: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"

echo "gates2 xong"
