#!/usr/bin/env bash
# M6h: chi pipeline production. Du lieu da co, khong rsync.
set -euo pipefail
ROOT=/root/hids
STATUS=$ROOT/out/jobs/m6h-prod.status
LOG=$ROOT/out/jobs/m6h-prod.log
mkdir -p "$ROOT/out/jobs"
exec > >(tee -a "$LOG") 2>&1
echo "start=$(date -Iseconds)" | tee "$STATUS"
echo "status=prod_pipeline" | tee -a "$STATUS"

AVAIL=$(df -B1 / | awk 'NR==2 {print $4}')
echo "dia_trong_bytes=$AVAIL"
python3 - "$AVAIL" <<'PY'
import sys
avail = int(sys.argv[1])
print("dia_trong_GB=%.1f can>=90" % (avail / 1e9))
if avail < 90 * 1000**3:
    raise SystemExit("DUNG: dia trong %.1f GB < 90 GB" % (avail / 1e9))
PY

ln -sfn /srv/hids-data/prod1-benign "$ROOT/validation/prod1/nen"
echo "bin_prod=$(find -L "$ROOT/validation/prod1/nen" -type f -name '*.bin' ! -name '*.bin.periodic' ! -name '*.bin.stats' | wc -l)"
du -sh /srv/hids-data/prod1-benign
df -h /

echo "=== pipeline PROD $(date -Iseconds) ==="
rm -rf "$ROOT/out/c5-prod"
/usr/bin/time -f "TIME_prod_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" \
  "$ROOT/validation/prod1" "$ROOT/out/c5-prod"

echo "=== ap nguong $(date -Iseconds) ==="
echo "status=ap_nguong" >> "$STATUS"
python3 "$ROOT/scripts/c5_apply_threshold.py" \
  --tom-tat "$ROOT/out/c5-lab1/score/tom_tat.tsv" \
  --prod-score "$ROOT/out/c5-prod/score" \
  | tee "$ROOT/out/c5-prod/bao_dong_gia_prod.tsv"

echo "status=done exit=0 end=$(date -Iseconds)" >> "$STATUS"
echo "=== DONE === $(date -Iseconds)"
