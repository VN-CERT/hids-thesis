#!/usr/bin/env bash
# lab1_benign_gen.sh <thu_muc_log>
# Generator tai benign LAB-1 (§2b giao-thuc-lab1.md): vong lap vo han, moi nhip 5 phut.
# Dung sach khi SIGTERM.
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "cach dung: $0 <thu_muc_log>" >&2
	exit 2
fi
LOG_DIR=$1
mkdir -p "$LOG_DIR"
NHIP_TSV="$LOG_DIR/nhip-benign.tsv"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PG_LOAD="$REPO/scripts/lab0-load-postgres.sh"
URL="${LAB1_NGINX_URL:-http://127.0.0.1:18080/file4k.bin}"
NHIP_ID=0
STOP=0

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

on_term() {
	STOP=1
	echo "lab1_benign_gen: nhan SIGTERM, dung sau nhip hien tai" >&2
	# kill wrk2/pgbench con neu con
	jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
}
trap on_term TERM INT

# Header TSV
if [[ ! -f $NHIP_TSV ]]; then
	printf 'nhip_id\tdich_vu\tmuc\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\n' >"$NHIP_TSV"
fi

# Chon muc theo gio trong ngay (dem 00-06 thap, ngay cao) + jitter ±20%
pick_rps() {
	local h jitter base
	h=$(date +%H)
	h=$((10#$h))
	if ((h >= 0 && h < 6)); then
		base=20
	elif ((h < 12)); then
		base=50
	elif ((h < 18)); then
		base=120
	else
		base=200
	fi
	# clamp ve tap {20,50,120,200} sau jitter: chon muc gan nhat trong tap
	jitter=$(python3 -c "import random; print(1.0 + random.uniform(-0.20, 0.20))")
	python3 -c "
cands=[20,50,120,200]
v=int(round($base * $jitter))
print(min(cands, key=lambda x: abs(x-v)))
"
}

pick_tps() {
	local h jitter base
	h=$(date +%H)
	h=$((10#$h))
	if ((h >= 0 && h < 6)); then
		base=15
	elif ((h < 12)); then
		base=40
	else
		base=100
	fi
	jitter=$(python3 -c "import random; print(1.0 + random.uniform(-0.20, 0.20))")
	python3 -c "
cands=[15,40,100]
v=int(round($base * $jitter))
print(min(cands, key=lambda x: abs(x-v)))
"
}

echo "lab1_benign_gen: bat dau, log=$LOG_DIR" >&2
while ((STOP == 0)); do
	NHIP_ID=$((NHIP_ID + 1))
	rps=$(pick_rps)
	tps=$(pick_tps)
	t0=$(mono_ns)

	# nginx 290s
	t_ng0=$(mono_ns)
	taskset -c 0-3 wrk2 -t2 -c16 -R "$rps" -d290s --latency "$URL" \
		>"$LOG_DIR/wrk2-nhip${NHIP_ID}.log" 2>&1 &
	wrk_pid=$!
	# postgres 290s (VACUUM+CHECKPOINT ben trong script)
	t_pg0=$(mono_ns)
	"$PG_LOAD" "$tps" 290 "$LOG_DIR" \
		>"$LOG_DIR/pgbench-nhip${NHIP_ID}.log" 2>&1 &
	pg_pid=$!

	wait "$wrk_pid" || true
	t_ng1=$(mono_ns)
	printf '%s\t%s\t%s\t%s\t%s\n' "$NHIP_ID" "nginx" "$rps" "$t_ng0" "$t_ng1" >>"$NHIP_TSV"

	wait "$pg_pid" || true
	t_pg1=$(mono_ns)
	printf '%s\t%s\t%s\t%s\t%s\n' "$NHIP_ID" "postgres" "$tps" "$t_pg0" "$t_pg1" >>"$NHIP_TSV"

	t1=$(mono_ns)
	echo "lab1_benign_gen: nhip=$NHIP_ID rps=$rps tps=$tps elapsed_ns=$((t1 - t0))" >&2

	# Nhip danh nghia 5 phut; neu da ~290s thi nghi den du ~300s
	elapsed_s=$(( (t1 - t0) / 1000000000 ))
	if ((elapsed_s < 300 && STOP == 0)); then
		sleep $((300 - elapsed_s)) || true
	fi
done
echo "lab1_benign_gen: thoat sach" >&2
exit 0
