#!/usr/bin/env bash
# m6b12_g3.sh <stop|run> <outdir>
# G3 S1-S5 voi bpftrace da mo rong (@rq_sau_preempt_ns).
#   stop: dung tat ca container that truoc khi chay, chay xong khoi dong lai.
#   run:  chay khi container dang chay.
# Tieu chi them: lech rq collector so voi TONG bpftrace <= 5% o S2, S3, S5.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

MODE="${1:?stop|run}"
OUTROOT="${2:?outdir}"
mkdir -p "$OUTROOT"
exec > >(tee -a "$OUTROOT/g3-run.log") 2>&1

echo "=== m6b12_g3 mode=$MODE start=$(date -Is) ==="
git rev-parse --short HEAD
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py
echo "--- bpftool prog show | grep -c hids_ (phai = 0) ---"
n=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
echo "bpftool_hids_count=$n"
[[ "$n" == "0" ]] || { echo "DUNG: con chuong trinh hids_"; exit 1; }
pgrep -a hids-collect && { echo "DUNG: con collector"; exit 1; } || echo "khong co collector"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "container dang chay truoc: ${RUNNING[*]}"
if [[ "$MODE" == "stop" ]]; then
	docker stop "${RUNNING[@]}" || exit 1
	echo "da dung container: $(docker ps --format '{{.Names}}' | wc -l) con chay"
fi

G3_OUTROOT="$OUTROOT/g3" bash scripts/g3.sh m5d
GRC=$?
echo "g3_exit=$GRC"

if [[ "$MODE" == "stop" ]]; then
	docker start "${RUNNING[@]}" || echo "LOI khoi dong lai container"
	echo "container dang chay sau: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
fi

echo "=== trich xuat bpftrace + lech rq so voi TONG ==="
python3 - "$OUTROOT/g3" <<'PY' | tee "$OUTROOT/g3-rq-tong.txt"
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for s in ("S2", "S3", "S5"):
    p = root / f"{s}-ketqua.txt"
    print(f"--- {s}: {p} ---")
    if not p.exists():
        print("(khong co file ket qua)")
        continue
    lines = p.read_text(errors="replace").splitlines()
    for line in lines:
        if line.startswith("@rq_sau_wakeup_ns") or line.startswith("@rq_sau_preempt_ns") or line.startswith("@rq_tong_ns") or line.startswith("@so_lan"):
            print(line)
    for line in lines:
        ls = line.strip()
        if ls.startswith("rq_sau_preempt"):
            print(line)
        if ls.startswith("rq ") and "bpftrace TONG" in ls:
            f = ls.split()
            coll, ref = int(f[1]), int(f[2])
            dev = abs(coll - ref) / ref * 100 if ref else float("nan")
            print(line)
            print(f"LECH_RQ_TONG_{s}: collector={coll} bpftrace_tong={ref} lech={dev:.2f}% (tieu chi: <=5%)")
PY

echo "=== G5 max + recursion_misses ==="
python3 - "$OUTROOT/g3" <<'PY' | tee "$OUTROOT/g3-g5-max.txt"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
for p in sorted(root.glob("S*-ketqua.txt")):
    lines = p.read_text(errors="replace").splitlines()
    m = None
    for i, line in enumerate(lines):
        if "G5 phan du |tat ca (tru FIRST)|" in line:
            for j in range(i + 1, min(i + 8, len(lines))):
                mm = re.match(r"max\s+(\d+)", lines[j].strip())
                if mm:
                    m = int(mm.group(1))
                    break
            break
    print(f"{p.name}: g5_max_ns={m}")
    for line in lines:
        if line.startswith("recursion_misses"):
            print(f"{p.name}: {line.strip()}")
PY
echo "=== m6b12_g3 xong $(date -Is) g3_exit=$GRC ==="
