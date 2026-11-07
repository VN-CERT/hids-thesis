#!/usr/bin/env bash
# Cho labv2 xong roi: kiem cot cu, chay dap-ung, viet phu luc R041-b, commit, push.
set -euo pipefail
cd /root/hids
LOG=out/jobs/m6ic1-r041b.log
STATUS=out/jobs/m6ic1-r041b.status
echo "start=$(date -Iseconds)" > "$STATUS"
echo "status=waiting_lab" >> "$STATUS"
exec > >(tee -a "$LOG") 2>&1

echo "Cho hids-m6ic1-labv2..."
while systemctl is-active --quiet hids-m6ic1-labv2 2>/dev/null; do
  sleep 60
done
# also wait until status says done
for i in $(seq 1 120); do
  if grep -q '^status=done' out/jobs/m6ic1-labv2.status 2>/dev/null; then
    break
  fi
  if grep -q '^status=failed' out/jobs/m6ic1-labv2.status 2>/dev/null; then
    echo "LAB FAILED"; echo "status=failed" >> "$STATUS"; exit 1
  fi
  sleep 30
done
grep -q '^status=done' out/jobs/m6ic1-labv2.status
echo "LAB DONE $(date -Iseconds)"
echo "status=checking" >> "$STATUS"

python3 << 'PY'
import random
from pathlib import Path
old=Path("out/c5-lab1/features_all.tsv")
new=Path("out/c5-lab1/features_all_v2.tsv")
with open(old) as fo, open(new) as fn:
    ho=fo.readline().rstrip("\n").split("\t")
    hn=fn.readline().rstrip("\n").split("\t")
    # old cols must be prefix (same order) of new, except nguon at end
    # v1: branch tid start_ns stop_ns + dims + nguon
    # v2: same + EXTRA before nguon
    print("v1_cols", len(ho), "v2_cols", len(hn))
    print("v1_header", "\t".join(ho[:6]), "...", ho[-1])
    print("v2_header_tail", "\t".join(hn[-8:]))
    # line counts
    n_old=1; n_new=1
    # count via wc externally
print("counting...")
PY
n1=$(wc -l < out/c5-lab1/features_all.tsv)
n2=$(wc -l < out/c5-lab1/features_all_v2.tsv)
echo "lines_v1=$n1 lines_v2=$n2"
if [[ "$n1" != "$n2" ]]; then
  echo "LECH so dong"; echo "status=failed_lines" >> "$STATUS"; exit 2
fi

python3 << 'PY'
import random
from pathlib import Path
old_p=Path("out/c5-lab1/features_all.tsv")
new_p=Path("out/c5-lab1/features_all_v2.tsv")
with open(old_p) as fo:
    ho=fo.readline().rstrip("\n").split("\t")
    old_rows=fo.readlines()
with open(new_p) as fn:
    hn=fn.readline().rstrip("\n").split("\t")
    new_rows=fn.readlines()
assert len(old_rows)==len(new_rows)
ixo={c:i for i,c in enumerate(ho)}
ixn={c:i for i,c in enumerate(hn)}
# common old cols
common=[c for c in ho if c in ixn]
print("common_cols", len(common))
rng=random.Random(42)
idxs=rng.sample(range(len(old_rows)), min(1000, len(old_rows)))
bad=0
first=None
for i in idxs:
    po=old_rows[i].rstrip("\n").split("\t")
    pn=new_rows[i].rstrip("\n").split("\t")
    for c in common:
        if po[ixo[c]] != pn[ixn[c]]:
            bad+=1
            if first is None:
                first=(i,c,po[ixo[c]],pn[ixn[c]])
            break
print("mau=1000 lech_dong=%d" % bad)
if first:
    print("first", first)
if bad:
    raise SystemExit(2)
print("KIEM_COT_CU_KHOP")
PY

NHAN=""
for p in lab/nhan-lieu.tsv validation/lab1-20261024/lab/nhan-lieu.tsv; do
  [[ -f "$p" ]] && NHAN=$p && break
done
# also search
if [[ -z "$NHAN" ]]; then
  NHAN=$(find validation/lab1-20261024 lab -name 'nhan-lieu.tsv' 2>/dev/null | head -1 || true)
fi
echo "nhan_lieu=$NHAN"

python3 scripts/c5_dap_ung.py \
  --features out/c5-lab1/features_all_v2.tsv \
  --muc out/c5-lab1/muc-v2.tsv \
  --train-until 833189871480814 \
  --out out/c5-lab1/dap-ung \
  ${NHAN:+--nhan-lieu "$NHAN"}

# Write appendix R041-b via python
python3 << 'PY'
from pathlib import Path
from datetime import datetime
now=datetime.now().strftime("%Y-%m-%d %H:%M (+07)")
dap=Path("out/c5-lab1/dap-ung")
parts=[]
parts.append(f"# R041-b — phụ lục đáp ứng tranh chấp (lab features_all_v2)\n\n")
parts.append(f"1. Số: R041-b. Ngày giờ: {now}. Mốc: M6i-c1. Tiếp R041 khi lab trích xong.\n\n")
parts.append("2. Kiểm features_all_v2 vs features_all: cùng số dòng; 1000 dòng ngẫu nhiên khớp mọi cột cũ.\n\n")
parts.append("3. Ánh xạ cgroup_id: 76058=nginx, 75979=postgres.\n\n")
for name in ["theo_lop_muc.tsv","ti_so_vs_nen.tsv","quan_the_nen_tomtat.tsv","quan_the_nen_top20.tsv","agg_theo_cgroup_muc.tsv"]:
    p=dap/name
    parts.append(f"### {name}\n\n```\n")
    parts.append(p.read_text() if p.exists() else "(thieu)\n")
    parts.append("```\n\n")
# quan_the full is large - only note path
parts.append("File đầy đủ từng tid: `out/c5-lab1/dap-ung/quan_the_nen.tsv`.\n")
parts.append("\n4. Production extract: xem `out/jobs/m6ic1-prodv2.status`.\n")
Path("reports/R041-b-m6ic1-dap-ung.md").write_text("".join(parts))
print("wrote R041-b")
PY

# INDEX
python3 << 'PY'
from pathlib import Path
p=Path("reports/INDEX.md")
t=p.read_text()
line="| [R041-b](R041-b-m6ic1-dap-ung.md) | $(date) | M6i-c1 | Phụ lục đáp ứng tranh chấp trên features_all_v2. | Xong. |\n"
# fix date
import datetime
line="| [R041-b](R041-b-m6ic1-dap-ung.md) | %s | M6i-c1 | Phụ lục đáp ứng tranh chấp trên features_all_v2. | Xong. |\n" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
if "R041-b" not in t:
    p.write_text(t.rstrip()+"\n"+line)
PY

# commit small dap-ung + R041-b (no features)
git add reports/R041-b-m6ic1-dap-ung.md reports/INDEX.md scripts/c5_dap_ung.py
git add -f out/c5-lab1/dap-ung/*.tsv 2>/dev/null || true
# skip quan_the_nen.tsv if huge
if [[ -f out/c5-lab1/dap-ung/quan_the_nen.tsv ]]; then
  sz=$(wc -c < out/c5-lab1/dap-ung/quan_the_nen.tsv)
  if [[ $sz -lt 500000 ]]; then
    git add -f out/c5-lab1/dap-ung/quan_the_nen.tsv
  fi
fi
git commit -m "$(cat <<'EOM'
M6i-c1: R041-b bang dap ung tranh chap tren features_all_v2.

EOM
)" || true
git push github master || true
echo "status=done" >> "$STATUS"
echo "end=$(date -Iseconds)" >> "$STATUS"
echo "XONG_R041B"
