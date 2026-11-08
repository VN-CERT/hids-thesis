#!/usr/bin/env bash
# M6i-c4: ablation lab1c I/Iarr/own_only/arr_only/E/D → score-v143-*
set -euo pipefail
cd /root/hids
STATUS=out/jobs/m6ic4-score.status
LOG=out/jobs/m6ic4-score.log
mkdir -p out/jobs
start_ts=$(date -Iseconds)
DONE=0; TOTAL=6
echo "start=$start_ts progress=0/$TOTAL state=running" > "$STATUS"
: >"$LOG"
CUT=1006289550843307
FEAT=out/c5-lab1c/features_ghep.tsv
for CH in I Iarr own_only arr_only E D; do
  outdir="out/c5-lab1c/score-v143-${CH}"
  mkdir -p "$outdir"
  echo "[$(date -Iseconds)] START $outdir" | tee -a "$LOG"
  /usr/bin/time -v python3 analysis/c5_score.py \
    --features "$FEAT" --train-until "$CUT" \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --muc lab/muc-lab1c.tsv \
    --chieu-phanra "$CH" --ho-so lop --n-toi-thieu 30 \
    --out "$outdir" \
    >"$outdir/log.txt" 2>"$outdir/time.txt"
  thr=$(awk -F'\t' 'NR>1 && $1=="PHANRA_5tp" && $2=="0.01" {print $3; exit}' "$outdir/tom_tat_ngan_sach.tsv" || echo nan)
  echo "  PHANRA_nguong@0.01=$thr" | tee -a "$LOG"
  DONE=$((DONE+1))
  echo "start=$start_ts progress=$DONE/$TOTAL last=$(date -Iseconds) state=running" > "$STATUS"
  echo "[$(date -Iseconds)] DONE $outdir" | tee -a "$LOG"
done
echo "end=$(date -Iseconds) progress=$DONE/$TOTAL state=done" > "$STATUS"
echo ALL_OK | tee -a "$LOG"
