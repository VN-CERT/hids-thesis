#!/usr/bin/env bash
# Cham 4 bo v1.3.2 dung tham so M6i-b; cmp voi v131; dung neu lech.
set -euo pipefail
cd /root/hids
ROOT=/root/hids
STATUS=$ROOT/out/jobs/m6ic1-score.status
LOG=$ROOT/out/jobs/m6ic1-score.log
exec > >(tee -a "$LOG") 2>&1
echo "start=$(date -Iseconds)" > "$STATUS"
echo "status=running" >> "$STATUS"

cmp_bo() {
  local old="$1" new="$2" name="$3"
  echo "=== CMP $name ==="
  local ok=1
  for f in tom_tat_ngan_sach.tsv; do
    if ! cmp -s "$old/$f" "$new/$f"; then
      echo "LECH $f"
      diff -u "$old/$f" "$new/$f" | head -40 || true
      ok=0
    else
      echo "KHOP $f"
    fi
  done
  for f in "$old"/tradeoff_*.tsv; do
    bn=$(basename "$f")
    if ! cmp -s "$old/$bn" "$new/$bn"; then
      echo "LECH $bn"
      ok=0
    else
      echo "KHOP $bn"
    fi
  done
  for f in "$old"/duong_tranh_chap_*.tsv; do
    bn=$(basename "$f")
    if ! cmp -s "$old/$bn" "$new/$bn"; then
      echo "LECH $bn"
      ok=0
    else
      echo "KHOP $bn"
    fi
  done
  if [ "$ok" -ne 1 ]; then
    echo "status=failed_cmp_$name" >> "$STATUS"
    exit 2
  fi
  echo "CMP_OK $name"
}

cham() {
  local mode="$1" out="$2"
  shift 2
  mkdir -p "$out"
  echo "=== cham $mode -> $out $(date -Iseconds) ==="
  /usr/bin/time -v python3 -u "$ROOT/analysis/c5_score.py" "$@" \
    > "$out/log.txt" 2> "$out/time.txt"
  echo "xong $mode $(date -Iseconds)"
  grep -E 'Maximum resident|Elapsed' "$out/time.txt" || true
}

TRAIN_LAB=833189871480814
FEAT_LAB=$ROOT/out/c5-lab1/features_all.tsv
MUC=$ROOT/out/c5-lab1/muc-v2.tsv
NHIP=$ROOT/out/c5-lab1/nhip-benign-gop.tsv

cham toc_do "$ROOT/out/c5-lab1/score-v132-tocdo" \
  --features "$FEAT_LAB" --train-until "$TRAIN_LAB" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do toc_do \
  --out "$ROOT/out/c5-lab1/score-v132-tocdo"
cmp_bo "$ROOT/out/c5-lab1/score-v131-tocdo" "$ROOT/out/c5-lab1/score-v132-tocdo" lab-tocdo

cham nhip "$ROOT/out/c5-lab1/score-v132-nhip" \
  --features "$FEAT_LAB" --train-until "$TRAIN_LAB" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do nhip \
  --out "$ROOT/out/c5-lab1/score-v132-nhip"
cmp_bo "$ROOT/out/c5-lab1/score-v131-nhip" "$ROOT/out/c5-lab1/score-v132-nhip" lab-nhip

cham khong "$ROOT/out/c5-lab1/score-v132-khong" \
  --features "$FEAT_LAB" --train-until "$TRAIN_LAB" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do khong \
  --out "$ROOT/out/c5-lab1/score-v132-khong"
cmp_bo "$ROOT/out/c5-lab1/score-v131-khong" "$ROOT/out/c5-lab1/score-v132-khong" lab-khong

cham prod "$ROOT/out/c5-prod/score-v132-tocdo" \
  --features "$ROOT/out/c5-prod/features_all.tsv" \
  --train-until 434858090000000 \
  --dai-che-do toc_do --ngan-sach 0.001,0.01,0.05 \
  --out "$ROOT/out/c5-prod/score-v132-tocdo"
cmp_bo "$ROOT/out/c5-prod/score-v131-tocdo" "$ROOT/out/c5-prod/score-v132-tocdo" prod-tocdo

echo "=== HET CHAM $(date -Iseconds) ==="
echo "status=done" >> "$STATUS"
echo "end=$(date -Iseconds)" >> "$STATUS"
