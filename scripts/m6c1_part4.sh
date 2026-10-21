#!/usr/bin/env bash
# M6c-1 phan 4 (chay dem): overhead production + duong toc do + G7-cap.
# Container dung luc chay, khoi dong lai khi xong (ke ca loi).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?outroot}"
mkdir -p "$OUTROOT"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "dung container: ${RUNNING[*]}" | tee "$OUTROOT/part4.log"
docker stop "${RUNNING[@]}" >>"$OUTROOT/part4.log" 2>&1 || true

echo "=== overhead chinh (m6c1_overhead.sh) $(date -Is) ===" | tee -a "$OUTROOT/part4.log"
bash scripts/m6c1_overhead.sh "$OUTROOT/overhead" >>"$OUTROOT/part4.log" 2>&1
echo "overhead_exit=$?" | tee -a "$OUTROOT/part4.log"

echo "=== duong CPU theo toc do (-pmu host) $(date -Is) ===" | tee -a "$OUTROOT/part4.log"
for r in 1000 10000 100000 500000; do
	for att in 1 2; do
		HIDS_COLLECT_EXTRA="-pmu host" bash scripts/m6b12_rate.sh "$r" "$OUTROOT/rate-$r" >>"$OUTROOT/part4.log" 2>&1
		if grep -qx READY "$OUTROOT/rate-$r/collect.log" 2>/dev/null; then
			break
		fi
		echo "KHONG_READY rate=$r lan_thu=$att" | tee -a "$OUTROOT/part4.log"
	done
done

echo "=== G7-cap 1/2/4 (zstd mac dinh, -pmu mac dinh host) $(date -Is) ===" | tee -a "$OUTROOT/part4.log"
for n in 1 2 4; do
	G7_CAP_OUT="$OUTROOT/g7cap" G7_CAP_NPROC="$n" bash scripts/m5f_g7cap2.sh >>"$OUTROOT/part4.log" 2>&1
	echo "g7cap nproc=$n exit=$?" | tee -a "$OUTROOT/part4.log"
done
for f in "$OUTROOT"/g7cap/*.bin; do
	[[ -f "$f" ]] || continue
	echo "$f: $(grep -a -m1 '^# pmu:' "$f" || true)"
done | tee "$OUTROOT/g7cap-pmu-headers.txt"

docker start "${RUNNING[@]}" >>"$OUTROOT/part4.log" 2>&1 || true
echo "container sau: $(docker ps --format '{{.Names}}' | tr '\n' ' ')" | tee -a "$OUTROOT/part4.log"
echo "part4 xong $(date -Is)"
