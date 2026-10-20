#!/usr/bin/env bash
# m6b11_gate.sh — cong M6b-1.1 phan C: pre24h (G7a, G7b-nho, G3, G9b, host10m)
# + gate (G8, G10, ...) + chay 1 gio cau hinh 24h. Khong doi tieu chi san co.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/hids_data_policy.sh

OUTROOT="${M6B11_OUT:-validation/m6b11-20261020/C}"
mkdir -p "$OUTROOT" out/jobs
exec > >(tee -a "$OUTROOT/gate-c.log") 2>&1

echo "=== m6b11_gate bat dau $(date -Is) ==="
[[ $EUID -eq 0 ]] || { echo "can root"; exit 1; }
hids_require_clean_git || { echo "cay git khong sach"; exit 1; }
git rev-parse --short HEAD | tee "$OUTROOT/git-head.txt"
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py | tee "$OUTROOT/architect-sha256.txt"

echo "--- kiem tra chi mot collector: bpftool prog show | grep -c hids_ ---"
n=$(bpftool prog show 2>/dev/null | grep -c hids_ || true)
echo "bpftool_hids_count=$n"
[[ "$n" == "0" ]] || { echo "DUNG: con chuong trinh hids_ trong kernel"; exit 1; }
if pgrep -a hids-collect; then echo "DUNG: con hids-collect dang chay"; exit 1; fi
echo "khong co collector nao dang chay"

echo "=== Buoc C1: m6b1_pre24h.sh (G7a, G7b-nho, G3, G9b, host10m) start=$(date -Is) ==="
PRE24H_RC=0
M6B1_PRE24H_OUT="$OUTROOT/pre24h" bash scripts/m6b1_pre24h.sh || PRE24H_RC=$?
echo "pre24h_exit=$PRE24H_RC end=$(date -Is)"

echo "=== G3: trich xuat doi chieu bpftrace S2 S3 S5 (nguyen van) ==="
python3 - "$OUTROOT/pre24h/g3" <<'PY' | tee "$OUTROOT/g3-bpftrace-compare.txt"
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
for s in ("S2", "S3", "S5"):
    p = root / f"{s}-ketqua.txt"
    print(f"--- {s}: {p} ---")
    if not p.exists():
        print("(khong co file ket qua)")
        continue
    lines = p.read_text(errors="replace").splitlines()
    for line in lines:
        if line.startswith("@rq_sau_wakeup_ns") or line.startswith("@so_lan") or line.startswith("@w:"):
            print(line)
    for line in lines:
        ls = line.strip()
        if ls.startswith("rq ") and "bpftrace @rq_sau_wakeup_ns" in ls:
            f = ls.split()
            coll, ref = int(f[1]), int(f[2])
            dev = abs(coll - ref) / ref * 100 if ref else float("nan")
            print(line)
            print(f"LECH_RQ_{s}: collector={coll} bpftrace={ref} lech={dev:.2f}% (tieu chi them: <=5%)")
        if ls.startswith("so_lan_wakeup") and "bpftrace @so_lan" in ls:
            print(line)
PY

echo "=== Buoc C2: m6b1_gate.sh (G7a, G3, G8, G9, G10, host-stats) start=$(date -Is) ==="
GATE_RC=0
M6B1_OUT="$OUTROOT/gate" bash scripts/m6b1_gate.sh || GATE_RC=$?
echo "gate_exit=$GATE_RC end=$(date -Is)"

echo "--- sau gate: bpftool prog show | grep -c hids_ ---"
bpftool prog show 2>/dev/null | grep -c hids_ || true

echo "=== Buoc C3: chay 1 gio cau hinh 24h start=$(date -Is) ==="
bash scripts/m6b11_1h.sh "$OUTROOT/run1h" || echo "run1h_exit=$?"
echo "=== m6b11_gate xong $(date -Is) pre24h_exit=$PRE24H_RC gate_exit=$GATE_RC ==="
echo "pre24h_exit=$PRE24H_RC gate_exit=$GATE_RC" > "$OUTROOT/gate-c.status"
