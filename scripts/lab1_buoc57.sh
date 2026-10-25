#!/usr/bin/env bash
# lab1_buoc57.sh — cho slow/B1-300s xong, roi buoc 5 (detector khoi).
# KHONG dung/sua hids-lab1-collector|gen|watch (nen 7 ngay).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DAY="${LAB1_DAY:-20261024}"
REPO=/root/collector
VAL="$REPO/validation/lab1-${DAY}"
DATADIR="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}"
STATUS="$REPO/out/jobs/lab1-buoc57.status"
LOG="$VAL/buoc57.log"
mkdir -p "$VAL" "$(dirname "$STATUS")" "$DATADIR"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

START=$(date -Is)
: >"$LOG"
cat >"$STATUS" <<EOF
name=lab1-buoc57
command=LAB1_DAY=$DAY bash scripts/lab1_buoc57.sh
start=$START
progress=0/3 wait-slow
updated=$START
status=running
exit=
EOF

log "buoc57 bat dau — cho B1-300s + slow-xong (KHONG dung nen 7 ngay)"

DEADLINE=$(( $(date +%s) + 8*3600 ))
while (( $(date +%s) < DEADLINE )); do
	n=0
	for t in B1-60s N1-60s B1-300s N1-300s; do
		if [[ -f $VAL/slow/$t/xac-nhan.txt ]] && grep -q 'ok_cycles_ge20=1' "$VAL/slow/$t/xac-nhan.txt"; then
			n=$((n + 1))
		fi
	done
	sed -i "s|^progress=.*|progress=$n/4 wait-slow|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
	# B1-300s DAT va (slow-xong HOAC slow unit da tat)
	if [[ -f $VAL/slow/B1-300s/xac-nhan.txt ]] && grep -q 'ok_cycles_ge20=1' "$VAL/slow/B1-300s/xac-nhan.txt"; then
		if [[ -f $VAL/slow-xong.txt ]] || ! systemctl is-active hids-lab1-slow >/dev/null 2>&1; then
			log "B1-300s DAT va slow da ket thuc (hoac slow-xong)"
			break
		fi
		# B1-300s xong nhung N1-300s con chay — van cho slow-xong (buoc 5 chi can B1-300s,
		# nhung nhiem vu noi "slow xong")
		log "B1-300s DAT; dang cho slow-xong (N1-300s con?) n=$n/4"
	fi
	sleep 30
done

if [[ ! -f $VAL/slow/B1-300s/xac-nhan.txt ]] || ! grep -q 'ok_cycles_ge20=1' "$VAL/slow/B1-300s/xac-nhan.txt"; then
	log "TIMEOUT/FAIL: B1-300s chua DAT"
	sed -i "s|^status=.*|status=failed|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
	echo "exit=1" >>"$STATUS"
	exit 1
fi

sed -i "s|^progress=.*|progress=1/3 detector|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
log "=== BUOC 5: detector_c5 khoi tren B1-300s ==="

NHAN="$REPO/lab/nhan-tan-cong.tsv"
python3 - "$NHAN" "$VAL" <<'PY'
import sys
nhan, val = sys.argv[1], sys.argv[2]
rows = []
with open(nhan) as f:
    hdr = f.readline().rstrip("\n").split("\t")
    for line in f:
        if not line.strip():
            continue
        d = dict(zip(hdr, line.rstrip("\n").split("\t")))
        rid = d.get("run_id", "")
        nhip = d.get("nhip_tham_so") or ""
        if "B1-300" in rid or (d.get("id") == "B1" and "period=300" in nhip and "slow" in (d.get("ghi_chu") or "")):
            rows.append(d)
if not rows:
    # fallback: moi dong B1 period=300
    with open(nhan) as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for line in f:
            d = dict(zip(hdr, line.rstrip("\n").split("\t")))
            if d.get("id") == "B1" and "period=300" in (d.get("nhip_tham_so") or ""):
                rows.append(d)
if not rows:
    print("LOI: khong tim thay nhan B1-300s", file=sys.stderr)
    sys.exit(1)
d = rows[-1]
open(val + "/b1-300s-meta.env", "w").write(
    "T0=%s\nT1=%s\nRUN_ID=%s\nWALL0=%s\nWALL1=%s\n"
    % (d.get("t_bat_dau_mono_ns"), d.get("t_ket_thuc_mono_ns"),
       d.get("run_id"), d.get("t_bat_dau_wall"), d.get("t_ket_thuc_wall"))
)
print("run_id=%s T0=%s T1=%s" % (d.get("run_id"), d.get("t_bat_dau_mono_ns"), d.get("t_ket_thuc_mono_ns")))
PY

# shellcheck disable=SC1091
source "$VAL/b1-300s-meta.env"
log "nhan RUN_ID=$RUN_ID T0=$T0 T1=$T1 wall $WALL0 -> $WALL1"
cat "$VAL/slow/B1-300s/xac-nhan.txt" | tee -a "$LOG"

TSV="$VAL/detector-b1-300s.tsv"
log "rec-export + loc [$T0,$T1] tu $DATADIR"
python3 - "$REPO/bin/rec-export" "$DATADIR" "$TSV" "$T0" "$T1" <<'PY'
import glob, os, subprocess, sys
rec_export, datadir, tsv, t0, t1 = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
bins = sorted(glob.glob(os.path.join(datadir, "hids-*.bin")))
if not bins:
    print("LOI: khong co .bin", file=sys.stderr)
    sys.exit(1)
n_keep = 0
hdr = None
with open(tsv, "w") as out:
    for b in bins:
        p = subprocess.run([rec_export, b], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        if p.returncode != 0 or not p.stdout:
            print("canh bao: rec-export fail", b, file=sys.stderr)
            continue
        lines = p.stdout.splitlines()
        if not lines:
            continue
        if hdr is None:
            hdr = lines[0]
            out.write(hdr + "\n")
        for line in lines[1:]:
            c = line.split(",")
            if not c:
                continue
            try:
                ts = int(c[0])
            except ValueError:
                continue
            if t0 <= ts <= t1:
                out.write(line + "\n")
                n_keep += 1
print(f"bins={len(bins)} kept={n_keep} tsv={tsv}")
if n_keep < 100:
    sys.exit(2)
PY
ec_exp=$?
NLINES=$(wc -l <"$TSV")
log "export ec=$ec_exp lines=$NLINES"
if ((ec_exp != 0 || NLINES < 100)); then
	log "LOI export"
	sed -i "s|^status=.*|status=failed|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
	echo "exit=2" >>"$STATUS"
	exit 2
fi

OUT="$VAL/detector-khoi.txt"
set +e
python3 "$REPO/analysis/detector_c5.py" \
	--tsv "$TSV" \
	--nhan "$NHAN" \
	--window-s 300 \
	--step-s 30 \
	>"$VAL/detector-khoi-stdout.txt" 2>"$VAL/detector-khoi.stderr"
ec=$?
set -e

{
	echo "LAB-1 buoc 5 — kiem khoi detector_c5 (KHONG chon nguong, KHONG ket luan thong ke)"
	echo "ngay=$(date -Is)"
	echo "run_id=$RUN_ID"
	echo "t_bat_dau_mono_ns=$T0"
	echo "t_ket_thuc_mono_ns=$T1"
	echo "wall=$WALL0 -> $WALL1"
	echo "tsv=$TSV lines=$NLINES"
	echo "detector_exit=$ec"
	echo ""
	cat "$VAL/detector-khoi-stdout.txt"
	if [[ -s $VAL/detector-khoi.stderr ]]; then
		echo ""
		echo "--- stderr ---"
		cat "$VAL/detector-khoi.stderr"
	fi
} | tee "$OUT"

if ((ec != 0)); then
	log "detector_c5 exit=$ec"
	sed -i "s|^status=.*|status=failed|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
	echo "exit=$ec" >>"$STATUS"
	exit "$ec"
fi

# Xac nhan co ca hai nhanh (khong chon nguong)
grep -q 'BASELINE_dt_tho' "$OUT" || { log "thieu BASELINE"; exit 3; }
grep -q 'PHANRA_5tp' "$OUT" || { log "thieu PHANRA"; exit 3; }

echo "buoc5-xong $(date -Is)" | tee "$VAL/buoc5-xong.txt"
echo "ready_for_buoc7=1" >"$VAL/buoc57-ready.txt"
sed -i "s|^progress=.*|progress=3/3 ready-buoc7|;s|^status=.*|status=done|;s|^updated=.*|updated=$(date -Is)|" "$STATUS"
echo "exit=0" >>"$STATUS"
log "BUOC 5 XONG — cho Cursor buoc 7. File: $OUT"
exit 0
