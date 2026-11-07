#!/usr/bin/env bash
# Cham lab 3 cach roi production. Dung neu cong KIEM KHOP cua toc_do khong dat.
set -euo pipefail
cd /root/hids
ROOT=/root/hids
TRAIN=833189871480814
FEAT=$ROOT/out/c5-lab1/features_all.tsv
MUC=$ROOT/out/c5-lab1/muc-v2.tsv
NHIP=$ROOT/out/c5-lab1/nhip-benign-gop.tsv

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

cham toc_do "$ROOT/out/c5-lab1/score-v131-tocdo" \
  --features "$FEAT" --train-until "$TRAIN" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do toc_do \
  --out "$ROOT/out/c5-lab1/score-v131-tocdo"

python3 - << 'PY'
import re, sys
text=open("/root/hids/out/c5-lab1/score-v131-tocdo/log.txt", encoding="utf-8").read().splitlines()
# KIEM KHOP
khop=[ln for ln in text if ln.startswith("# KIEM KHOP")]
print("\n".join(khop))
if not khop:
    sys.exit("KHONG CO KIEM KHOP")
m=re.search(r"(\d+)/(\d+) nhip co du lieu", khop[0])
co, tong=int(m.group(1)), int(m.group(2))
print("ty_le_nhip %.4f" % (co/tong))
if co/tong < 0.90:
    sys.exit("DUNG: nhip co du lieu < 90%")
# bang median
rows=[]
grab=False
for ln in text:
    if ln.startswith("dich_vu\tmuc\t"):
        grab=True
        continue
    if grab:
        if not ln or ln.startswith("#") or ln.startswith("==="):
            break
        p=ln.split("\t")
        if len(p)<4:
            break
        rows.append((p[0], p[1], float(p[3])))
from collections import defaultdict
by=defaultdict(list)
for svc, muc, med in rows:
    by[svc].append((float(muc), med, muc))
ok=True
for svc, xs in by.items():
    xs.sort()
    print("tang", svc, " ".join("%s:%.1f" % (m, med) for _, med, m in xs))
    meds=[med for _, med, _ in xs]
    if any(meds[i] <= meds[i-1] for i in range(1, len(meds))):
        ok=False
        print("KHONG TANG", svc)
if not ok:
    sys.exit("DUNG: toc_do_trung_vi khong tang theo muc")
# theo dai sau dong ngan sach 0.01
n_ok=0
for i, ln in enumerate(text):
    if re.match(r"^0\.01\t", ln):
        for nxt in text[i+1:i+6]:
            if nxt.startswith("  theo dai"):
                parts=re.findall(r"\((\d+)\)", nxt)
                pos=sum(1 for x in parts if int(x)>0)
                print(nxt)
                print("so_dai", pos)
                if pos>=2:
                    n_ok+=1
                break
print("nhanh_du_2_dai", n_ok)
if n_ok < 1:
    sys.exit("DUNG: theo dai ngan sach 0.01 khong du 2 dai")
print("CONG_TOC_DO_OK")
PY

cham nhip "$ROOT/out/c5-lab1/score-v131-nhip" \
  --features "$FEAT" --train-until "$TRAIN" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do nhip \
  --out "$ROOT/out/c5-lab1/score-v131-nhip"

cham khong "$ROOT/out/c5-lab1/score-v131-khong" \
  --features "$FEAT" --train-until "$TRAIN" --muc "$MUC" --dai-nhip "$NHIP" \
  --ngan-sach 0.001,0.01,0.05 --dai-che-do khong \
  --out "$ROOT/out/c5-lab1/score-v131-khong"

cham prod "$ROOT/out/c5-prod/score-v131-tocdo" \
  --features "$ROOT/out/c5-prod/features_all.tsv" \
  --train-until 434858090000000 \
  --dai-che-do toc_do --ngan-sach 0.001,0.01,0.05 \
  --out "$ROOT/out/c5-prod/score-v131-tocdo"

echo "=== HET CHAM $(date -Iseconds) ==="
