#!/usr/bin/env bash
set -euo pipefail
ROOT=/root/hids
STATUS=/root/hids/out/jobs/c5-m6g-large.status
LOG=/root/hids/out/jobs/c5-m6g-large.log
exec > >(tee -a "$LOG") 2>&1
echo "start_mono_ns=$(date +%s) start=$(date -Iseconds)" > "$STATUS"
echo "status=running" >> "$STATUS"
echo "=== GEN 50M === $(date -Iseconds)"
rm -rf /root/hids/out/c5-syn-50m /root/hids/out/c5-pipe-50m
/usr/bin/time -f "TIME_gen real=%e sec maxrss_kb=%M" \
  python3 "$ROOT/scripts/c5_gen_synthetic.py" \
    --out /root/hids/out/c5-syn-50m --records 50000000 --tids 20
echo "=== PIPE === $(date -Iseconds)"
/usr/bin/time -f "TIME_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" /root/hids/out/c5-syn-50m /root/hids/out/c5-pipe-50m
ec=$?
echo "status=done exit=$ec end=$(date -Iseconds)" >> "$STATUS"
echo "=== DONE exit=$ec === $(date -Iseconds)"
exit $ec
