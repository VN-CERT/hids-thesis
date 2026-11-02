#!/usr/bin/env bash
# M6h: rsync 201 (+ cho key 90) roi chay pipeline lab va production. Qua dem.
set -euo pipefail
ROOT=/root/hids
STATUS=$ROOT/out/jobs/m6h.status
LOG=$ROOT/out/jobs/m6h.log
mkdir -p "$ROOT/out/jobs" "$ROOT/validation/lab1-20261024" "$ROOT/validation/prod1" "$ROOT/lab" /srv/hids-data
exec > >(tee -a "$LOG") 2>&1
echo "start=$(date -Iseconds)" | tee "$STATUS"
echo "status=running" | tee -a "$STATUS"

AVAIL=$(df -B1 / | awk 'NR==2 {print $4}')
echo "dia_trong_bytes=$AVAIL"
python3 - "$AVAIL" <<'PY'
import sys
avail=int(sys.argv[1])
need=90*1000**3
print("dia_trong_GB=%.1f can>=90" % (avail/1e9))
if avail < need:
    raise SystemExit("DUNG: dia trong %.1f GB < 90 GB" % (avail/1e9))
PY

echo "=== rsync 201 $(date -Iseconds) ==="
RSH='ssh -p 22022 -o BatchMode=yes'
rsync -a --info=stats2 -e "$RSH" \
  root@10.70.55.201:/root/collector/validation/lab1-20261024/ \
  "$ROOT/validation/lab1-20261024/"
rsync -a -e "$RSH" \
  root@10.70.55.201:/root/collector/validation/lab1-FINAL.txt \
  "$ROOT/validation/lab1-20261024/lab1-FINAL.txt"
rsync -a -e "$RSH" \
  root@10.70.55.201:/root/collector/lab/ \
  "$ROOT/lab/"
rsync -a --info=stats2 -e "$RSH" \
  root@10.70.55.201:/srv/hids-data/lab1-benign/ \
  /srv/hids-data/lab1-benign/
ln -sfn /srv/hids-data/lab1-benign "$ROOT/validation/lab1-20261024/nen"
ln -sfn "$ROOT/lab" "$ROOT/validation/lab1-20261024/lab"
echo "=== dem .bin lab ==="
find /srv/hids-data/lab1-benign "$ROOT/validation/lab1-20261024/bn" \
  "$ROOT/validation/lab1-20261024/benign-lieu" "$ROOT/validation/lab1-20261024/slow" \
  -name '*.bin' 2>/dev/null | wc -l
du -sh /srv/hids-data/lab1-benign "$ROOT/validation/lab1-20261024" "$ROOT/lab"
df -h /

echo "=== pipeline LAB $(date -Iseconds) ==="
echo "status=lab_pipeline" >> "$STATUS"
/usr/bin/time -f "TIME_lab_pipe real=%e sec maxrss_kb=%M" \
  bash "$ROOT/scripts/c5_pipeline.sh" \
  "$ROOT/validation/lab1-20261024" "$ROOT/out/c5-lab1"

echo "=== cho ssh key 90 $(date -Iseconds) ==="
echo "status=cho_key_90" >> "$STATUS"
until ssh -o BatchMode=yes -o ConnectTimeout=8 -p 22022 qtht_@10.70.63.90 'echo OK90'; do
  echo "CHO_KEY qtht_@10.70.63.90 port 22022 — can ssh-copy-id $(date -Iseconds)"
  sleep 60
done

echo "=== rsync 90 $(date -Iseconds) ==="
# qtht_ doc duoc; sudo rsync neu can. Thu copy truc tiep truoc.
R90='ssh -p 22022 -o BatchMode=yes'
mkdir -p /srv/hids-data/prod1-benign "$ROOT/validation/prod1"
rsync -a --info=stats2 -e "$R90" \
  qtht_@10.70.63.90:/home/qtht_/hids-prod/benign-khoi-dong.txt \
  qtht_@10.70.63.90:/home/qtht_/hids-prod/LAB-PROD-1-FINAL.txt \
  "$ROOT/validation/prod1/" || true
# benign bins: thu duong user; neu tu choi, sudo qua ssh
if ! rsync -a --info=stats2 -e "$R90" \
    qtht_@10.70.63.90:/srv/hids-data/prod1/benign/ \
    /srv/hids-data/prod1-benign/; then
  echo "rsync benign that bai, thu sudo tar"
  ssh -p 22022 qtht_@10.70.63.90 'sudo tar -C /srv/hids-data/prod1/benign -cf - .' \
    | tar -C /srv/hids-data/prod1-benign -xf -
fi
rsync -a -e "$R90" \
  qtht_@10.70.63.90:/srv/hids-data/prod1/suc-khoe.tsv \
  "$ROOT/validation/prod1/suc-khoe.tsv" \
  || ssh -p 22022 qtht_@10.70.63.90 'sudo cat /srv/hids-data/prod1/suc-khoe.tsv' \
     > "$ROOT/validation/prod1/suc-khoe.tsv"
ln -sfn /srv/hids-data/prod1-benign "$ROOT/validation/prod1/nen"
echo "=== dem .bin prod ==="
find /srv/hids-data/prod1-benign -name '*.bin' | wc -l
du -sh /srv/hids-data/prod1-benign
df -h /

echo "=== pipeline PROD $(date -Iseconds) ==="
echo "status=prod_pipeline" >> "$STATUS"
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
