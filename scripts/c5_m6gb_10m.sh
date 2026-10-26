#!/usr/bin/env bash
set -euo pipefail
ROOT=/root/hids
STATUS=/root/hids/out/jobs/c5-m6gb-10m.status
LOG=/root/hids/out/jobs/c5-m6gb-10m.log
mkdir -p /root/hids/out/jobs
echo "start=$(date -Iseconds)" > "$STATUS"
echo "status=running" >> "$STATUS"
exec > >(tee -a "$LOG") 2>&1
echo "=== GEN 10M === $(date -Iseconds)"
/usr/bin/time -f "TIME_gen real=%e sec maxrss_kb=%M" \
  python3 "$ROOT/scripts/c5_gen_synthetic.py" --out /root/hids/out/c5-syn-10m --records 10000000 --tids 12
echo "=== PIPE === $(date -Iseconds)"
/usr/bin/time -f "TIME_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" /root/hids/out/c5-syn-10m /root/hids/out/c5-pipe-10m
ec=$?
echo "status=done exit=$ec end=$(date -Iseconds)" >> "$STATUS"
echo "=== DONE exit=$ec === $(date -Iseconds)"
exit $ec
