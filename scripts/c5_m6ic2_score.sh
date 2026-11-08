#!/usr/bin/env bash
# M6i-c2: cham C5 v1.4 tren lab / lab1c / production. Chay tuan tu.
set -euo pipefail
ROOT=/root/hids
cd "$ROOT"
STATUS=out/jobs/m6ic2-score.status
LOG=out/jobs/m6ic2-score.log
mkdir -p out/jobs
start_ts=$(date -Iseconds)
echo "start=$start_ts progress=0/11 state=running" > "$STATUS"

upd() {
  echo "start=$start_ts progress=$1/$2 last=$(date -Iseconds) state=$3" > "$STATUS"
  echo "[$(date -Iseconds)] $4" | tee -a "$LOG"
}

run_one() {
  local outdir=$1; shift
  mkdir -p "$outdir"
  upd "$DONE" "$TOTAL" running "START $outdir"
  set +e
  /usr/bin/time -v python3 analysis/c5_score.py "$@" --out "$outdir" \
    >"$outdir/log.txt" 2>"$outdir/time.txt"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    upd "$DONE" "$TOTAL" failed "FAIL $outdir rc=$rc"
    tail -n 40 "$outdir/log.txt" >>"$LOG" || true
    tail -n 20 "$outdir/time.txt" >>"$LOG" || true
    exit $rc
  fi
  local loai
  loai=$(grep -E 'loai [0-9]+ cua so thua' "$outdir/log.txt" | head -1 || true)
  echo "  $loai" | tee -a "$LOG"
  DONE=$((DONE + 1))
  upd "$DONE" "$TOTAL" running "DONE $outdir"
}

DONE=0
TOTAL=11
: >"$LOG"

# --- 1. Lab: A..E tid_lop + D lop + D tat ---
CUT_LAB=833189871480814
FEAT_LAB=out/c5-lab1/features_all_v2.tsv
MUC_LAB=out/c5-lab1/muc-v2.tsv

for CH in A B C D E; do
  run_one "out/c5-lab1/score-v14-${CH}-tid" \
    --features "$FEAT_LAB" --train-until "$CUT_LAB" --muc "$MUC_LAB" \
    --chieu-phanra "$CH" --ho-so tid_lop
done
run_one "out/c5-lab1/score-v14-D-lop" \
  --features "$FEAT_LAB" --train-until "$CUT_LAB" --muc "$MUC_LAB" \
  --chieu-phanra D --ho-so lop
run_one "out/c5-lab1/score-v14-D-tat" \
  --features "$FEAT_LAB" --train-until "$CUT_LAB" --muc "$MUC_LAB" \
  --chieu-phanra D --ho-so tat

# --- 2. LAB-1c ghep ---
CUT_GHEP=$(cat out/c5-lab1c/features_ghep.cut)
FEAT_GHEP=out/c5-lab1c/features_ghep.tsv
for CH in D A; do
  run_one "out/c5-lab1c/score-v14-${CH}" \
    --features "$FEAT_GHEP" --train-until "$CUT_GHEP" \
    --nhan lab/nhan-tan-cong-lab1c.tsv --nhan-tid lab/nhan-tid-lab1c.tsv \
    --chieu-phanra "$CH" --ho-so lop --n-toi-thieu 30
done

# --- 3. Production D + A tid_lop ---
CUT_PROD=434858090000000
FEAT_PROD=out/c5-prod/features_all_v2.tsv
for CH in D A; do
  run_one "out/c5-prod/score-v14-${CH}-tid" \
    --features "$FEAT_PROD" --train-until "$CUT_PROD" \
    --chieu-phanra "$CH" --ho-so tid_lop
done

upd "$DONE" "$TOTAL" done "ALL_OK"
echo "end=$(date -Iseconds) progress=$DONE/$TOTAL state=done" > "$STATUS"
