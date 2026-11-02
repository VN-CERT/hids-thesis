#!/usr/bin/env bash
# Tiep M6h: khong rsync 201. Trich LAB tu dau, roi cho key 90 de lam muc 3-5.
set -euo pipefail
ROOT=/root/hids
STATUS=$ROOT/out/jobs/m6h.status
LOG=$ROOT/out/jobs/m6h-lab.log
mkdir -p "$ROOT/out/jobs"
exec > >(tee -a "$LOG") 2>&1
echo "start=$(date -Iseconds)" | tee "$STATUS"
echo "status=lab_pipeline" | tee -a "$STATUS"

AVAIL=$(df -B1 / | awk 'NR==2 {print $4}')
echo "dia_trong_bytes=$AVAIL"
python3 - "$AVAIL" <<'PY'
import sys
avail = int(sys.argv[1])
print("dia_trong_GB=%.1f can>=90" % (avail / 1e9))
if avail < 90 * 1000**3:
    raise SystemExit("DUNG: dia trong %.1f GB < 90 GB" % (avail / 1e9))
PY

ln -sfn /srv/hids-data/lab1-benign "$ROOT/validation/lab1-20261024/nen"
ln -sfn "$ROOT/lab" "$ROOT/validation/lab1-20261024/lab"
rm -rf "$ROOT/out/c5-lab1"
echo "=== pipeline LAB $(date -Iseconds) ==="
/usr/bin/time -f "TIME_lab_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" \
  "$ROOT/validation/lab1-20261024" "$ROOT/out/c5-lab1"

echo "=== cho ssh key 90 $(date -Iseconds) ==="
echo "status=cho_key_90" >> "$STATUS"
until ssh -o BatchMode=yes -o ConnectTimeout=8 -p 22022 qtht_@10.70.63.90 'echo OK90'; do
  echo "CHO_KEY qtht_@10.70.63.90 port 22022 $(date -Iseconds)"
  sleep 60
done

echo "=== rsync 90 $(date -Iseconds) ==="
R90='ssh -p 22022 -o BatchMode=yes'
mkdir -p /srv/hids-data/prod1-benign "$ROOT/validation/prod1"
rsync -a -e "$R90" \
  qtht_@10.70.63.90:/home/qtht_/hids-prod/benign-khoi-dong.txt \
  qtht_@10.70.63.90:/home/qtht_/hids-prod/LAB-PROD-1-FINAL.txt \
  "$ROOT/validation/prod1/"
if ! rsync -a --info=stats2 -e "$R90" \
    qtht_@10.70.63.90:/srv/hids-data/prod1/benign/ \
    /srv/hids-data/prod1-benign/; then
  ssh -p 22022 qtht_@10.70.63.90 'sudo tar -C /srv/hids-data/prod1/benign -cf - .' \
    | tar -C /srv/hids-data/prod1-benign -xf -
fi
if ! rsync -a -e "$R90" \
    qtht_@10.70.63.90:/srv/hids-data/prod1/suc-khoe.tsv \
    "$ROOT/validation/prod1/suc-khoe.tsv"; then
  ssh -p 22022 qtht_@10.70.63.90 'sudo cat /srv/hids-data/prod1/suc-khoe.tsv' \
    > "$ROOT/validation/prod1/suc-khoe.tsv"
fi
ln -sfn /srv/hids-data/prod1-benign "$ROOT/validation/prod1/nen"
echo "bin_prod=$(find /srv/hids-data/prod1-benign -type f -name '*.bin' | wc -l)"
du -sh /srv/hids-data/prod1-benign
df -h /

echo "=== pipeline PROD $(date -Iseconds) ==="
echo "status=prod_pipeline" >> "$STATUS"
rm -rf "$ROOT/out/c5-prod"
/usr/bin/time -f "TIME_prod_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" \
  "$ROOT/validation/prod1" "$ROOT/out/c5-prod"

echo "=== ap nguong $(date -Iseconds) ==="
python3 "$ROOT/scripts/c5_apply_threshold.py" \
  --tom-tat "$ROOT/out/c5-lab1/score/tom_tat.tsv" \
  --prod-score "$ROOT/out/c5-prod/score" \
  | tee "$ROOT/out/c5-prod/bao_dong_gia_prod.tsv"

echo "status=done exit=0 end=$(date -Iseconds)" >> "$STATUS"
echo "=== DONE === $(date -Iseconds)"
