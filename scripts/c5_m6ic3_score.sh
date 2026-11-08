#!/usr/bin/env bash
# M6i-c3: lab1c A,D,E với nền trượt 24h → score-v142-*
set -euo pipefail
cd /root/hids
STATUS=out/jobs/m6ic3-score.status
LOG=out/jobs/m6ic3-score.log
mkdir -p out/jobs
start_ts=$(date -Iseconds)
DONE=0; TOTAL=3
echo "start=$start_ts progress=0/$TOTAL state=running" > "$STATUS"
: >"$LOG"
CUT=1006289550843307
FEAT=out/c5-lab1c/features_ghep.tsv
for CH in A D E; do
  outdir="out/c5-lab1c/score-v142-${CH}"
  mkdir -p "$outdir"
  echo "[$(date -Iseconds)] START $outdir" | tee -a "$LOG"
  /usr/bin/time -v python3 analysis/c5_score.py \
    --features "$FEAT" --train-until "$CUT" \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --muc lab/muc-lab1c.tsv \
    --chieu-phanra "$CH" --ho-so lop --n-toi-thieu 30 \
    --nen-truot-gio 24 \
    --out "$outdir" \
    >"$outdir/log.txt" 2>"$outdir/time.txt"
  DONE=$((DONE+1))
  echo "start=$start_ts progress=$DONE/$TOTAL last=$(date -Iseconds) state=running" > "$STATUS"
  echo "[$(date -Iseconds)] DONE $outdir" | tee -a "$LOG"
  ls -la "$outdir"/nen_truot_*.tsv 2>&1 | tee -a "$LOG" || true
done
echo "end=$(date -Iseconds) progress=$DONE/$TOTAL state=done" > "$STATUS"
echo ALL_OK | tee -a "$LOG"
