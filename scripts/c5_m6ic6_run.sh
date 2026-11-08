#!/usr/bin/env bash
set -euo pipefail
cd /root/hids
STATUS=out/jobs/m6ic6-lab.status
LOG=out/jobs/m6ic6-lab.log
mkdir -p out/jobs
start=$(date -Iseconds)
echo "start=$start progress=0/4 state=running" > "$STATUS"
: >"$LOG"

echo "[$(date -Iseconds)] AUROC" | tee -a "$LOG"
mkdir -p out/c5-lab1c/auroc-v15
/usr/bin/time -v python3 analysis/c5_score.py \
  --features out/c5-lab1c/features_ghep.tsv \
  --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
  --muc lab/muc-lab1c.tsv --n-toi-thieu 30 --auroc \
  --out out/c5-lab1c/auroc-v15 \
  >out/c5-lab1c/auroc-v15/log.txt 2>out/c5-lab1c/auroc-v15/time.txt
echo "  auroc exit=$?" | tee -a "$LOG"
echo "start=$start progress=1/4 last=$(date -Iseconds) state=running" > "$STATUS"

for CH in D E A; do
  echo "[$(date -Iseconds)] T2 $CH" | tee -a "$LOG"
  outdir="out/c5-lab1c/t2-v15-$CH"
  mkdir -p "$outdir"
  /usr/bin/time -v python3 analysis/c5_score.py \
    --features out/c5-lab1c/features_ghep.tsv \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --muc lab/muc-lab1c.tsv --n-toi-thieu 30 \
    --chieu-phanra "$CH" --t2 --out "$outdir" \
    >"$outdir/log.txt" 2>"$outdir/time.txt"
  echo "  t2-$CH exit=$?" | tee -a "$LOG"
  # progress
  case $CH in D) p=2;; E) p=3;; A) p=4;; esac
  echo "start=$start progress=$p/4 last=$(date -Iseconds) state=running" > "$STATUS"
done
echo "end=$(date -Iseconds) progress=4/4 state=done" > "$STATUS"
echo ALL_OK | tee -a "$LOG"
