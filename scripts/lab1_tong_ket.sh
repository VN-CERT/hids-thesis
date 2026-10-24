#!/usr/bin/env bash
# lab1_tong_ket.sh — sau 7 ngay benign: dung unit, gop suc-khoe, kiem 5 tieu chi §2, in validation/lab1-FINAL.txt
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
DATADIR="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}"
OUT="${1:-validation/lab1-FINAL.txt}"
mkdir -p "$(dirname "$OUT")"

echo "lab1_tong_ket: dung unit..." | tee "$OUT"
systemctl stop hids-lab1-collector hids-lab1-gen hids-lab1-watch.timer hids-lab1-watch.service 2>/dev/null || true
sleep 3
pkill -x hids-collect 2>/dev/null || true

{
	echo "=== LAB-1 FINAL $(date -Is) ==="
	echo "datadir=$DATADIR"
	echo
	echo "--- suc-khoe.tsv (nguyen van) ---"
	if [[ -f $DATADIR/suc-khoe.tsv ]]; then
		cat "$DATADIR/suc-khoe.tsv"
	else
		echo "THIEU suc-khoe.tsv"
	fi
	echo
	echo "--- kiem 5 tieu chi §2 ---"
	python3 - "$DATADIR" <<'PY'
import os, sys
dd = sys.argv[1]
tsv = os.path.join(dd, "suc-khoe.tsv")
print(f"doc {tsv}")
if not os.path.isfile(tsv):
    print("FAIL: khong co suc-khoe.tsv")
    sys.exit(0)
rows = []
with open(tsv) as f:
    hdr = None
    for line in f:
        line=line.strip()
        if not line: continue
        if hdr is None:
            hdr = line.split("\t")
            continue
        rows.append(dict(zip(hdr, line.split("\t"))))
print(f"so_dong={len(rows)}")
if not rows:
    print("FAIL: rong")
    sys.exit(0)
# 1. drops = 0
kd = sum(float(r.get("kernel_drops_delta") or 0) for r in rows)
pd = sum(float(r.get("proc_drops_delta") or 0) for r in rows)
print(f"1_kernel_drops_sum={kd} proc_drops_sum={pd} -> {'DAT' if kd==0 and pd==0 else 'KHONG_DAT'}")
# 2. PMU in [4,6]
pmus = [float(r.get("pmu_pct") or 0) for r in rows]
ok2 = all(4.0 <= p <= 6.0 for p in pmus) if pmus else False
print(f"2_pmu_pct min={min(pmus) if pmus else 'na'} max={max(pmus) if pmus else 'na'} -> {'DAT' if ok2 else 'KHONG_DAT'}")
# 3. CPU median <= 3% one core — uoc tu cpu_seconds / 3600 * 100 neu dong moi gio
# (chi in so, khong tu ket luan neu thieu)
cpus = [float(r.get("cpu_seconds_total") or 0) for r in rows]
print(f"3_cpu_seconds_total first={cpus[0] if cpus else 'na'} last={cpus[-1] if cpus else 'na'} (doi chieu thu cong <=3% loi)")
# 4. RSS khong tang >20% ngay1 vs ngay7
rss = [float(r.get("rss_bytes") or 0) for r in rows]
if rss and rss[0] > 0:
    pct = (rss[-1] - rss[0]) / rss[0] * 100
    print(f"4_rss first={rss[0]} last={rss[-1]} change_pct={pct:.2f} -> {'DAT' if pct <= 20 else 'KHONG_DAT'}")
else:
    print("4_rss thieu du lieu")
# 5. khoang mu — can phan tich .bin; chi ghi nhac
print("5_khoang_mu: can scripts/phan tich .bin (khong tu dong o day); xem gen nhip-benign.tsv")
print(f"nhip_benign={os.path.join(dd,'gen-logs','nhip-benign.tsv')}")
PY
	echo
	echo "Gui file nay cho kien truc su."
} | tee -a "$OUT"

echo "lab1_tong_ket: viet $OUT"
