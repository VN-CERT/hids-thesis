#!/usr/bin/env bash
# lab1_ben_d1_v18.sh — phu luc 1.8: chay lai BEN-D1 N∈{8,16} taskset 0-7.
# 4 phien × 15 phut. Generator + collector -pmu sample=20.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DAY="${LAB1_DAY:-20261024}"
REPO=/root/collector
VAL="$REPO/validation/lab1-${DAY}"
BEN_DIR="$VAL/benign-lieu"
NHAN_LIEU="$REPO/lab/nhan-lieu.tsv"
COLLECT="$REPO/bin/hids-collect"
COLLECT_CPUS="${LAB1_COLLECT_CPUS:-1-7}"
LOG="$VAL/ben-d1-v18.log"
mkdir -p "$BEN_DIR" "$REPO/lab"
: >>"$LOG"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

cgroup_of() {
	local id
	id=$(docker inspect -f '{{.Id}}' "$1")
	echo "/sys/fs/cgroup/system.slice/docker-${id}.scope"
}

wait_ready() {
	local logf=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$logf" 2>/dev/null && return 0
		sleep 0.01
	done
	return 1
}

start_collector() {
	local dd=$1 logf=$2
	local cg_ng cg_pg
	cg_ng=$(cgroup_of lab0-nginx)
	cg_pg=$(cgroup_of lab0-postgres)
	mkdir -p "$dd"
	local attempt
	for attempt in 1 2; do
		: >"$logf"
		taskset -c "$COLLECT_CPUS" "$COLLECT" -datadir "$dd" \
			-cgroup "$cg_ng" -cgroup "$cg_pg" \
			-min-free-gb 50 -pmu sample=20 \
			>>"$logf" 2>&1 &
		echo $! >"${logf}.pid"
		cp "${logf}.pid" /tmp/lab1-bend1-collect.pid
		if wait_ready "$logf"; then
			log "collector READY pid=$(cat "${logf}.pid") attempt=$attempt"
			return 0
		fi
		kill -INT "$(cat "${logf}.pid")" 2>/dev/null || true
		wait "$(cat "${logf}.pid")" 2>/dev/null || true
		sleep 1
	done
	log "LOI: collector KHONG_READY"
	exit 1
}

stop_collect() {
	local pf=/tmp/lab1-bend1-collect.pid
	[[ -f $pf ]] || return 0
	local p
	p=$(cat "$pf")
	kill -INT "$p" 2>/dev/null || true
	for i in 1 2 3 4 5; do
		kill -0 "$p" 2>/dev/null || break
		sleep 1
	done
	kill -KILL "$p" 2>/dev/null || true
	wait "$p" 2>/dev/null || true
	rm -f "$pf"
	pkill -KILL -x hids-collect 2>/dev/null || true
}

# Danh dau phien cu
for old in BEN-D1-2-r1 BEN-D1-2-r2 BEN-D1-4-r1 BEN-D1-4-r2; do
	d="$BEN_DIR/$old"
	[[ -d $d ]] || continue
	echo "liều không tác dụng (dịch vụ dời CPU) — phụ lục 1.8; giữ file, không dùng" \
		>"$d/KHONG-DUNG-phuluc1.8.txt"
	log "danh dau $old: khong dung"
done

# Dam bao lab0 + generator
systemctl set-property --runtime user.slice AllowedCPUs=1-7 || true
docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true
for i in $(seq 1 30); do
	curl -sf -o /dev/null http://127.0.0.1:18080/file4k.bin && break
	sleep 1
done

GEN_LOG="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}/gen-logs"
mkdir -p "$GEN_LOG"
if ! pgrep -f 'lab1_benign_gen.sh' >/dev/null; then
	log "khoi dong generator"
	bash "$REPO/scripts/lab1_benign_gen.sh" "$GEN_LOG" >>"$VAL/gen-bend1-v18.log" 2>&1 &
	echo $! >/tmp/lab1-bend1-gen.pid
	sleep 5
fi

ensure_nhan() {
	if [[ ! -f $NHAN_LIEU ]]; then
		printf 'dose_id\ttruc\tmuc\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\toracle_ten\toracle_gia_tri\tghi_chu\tmuc_tranh_chap\n' \
			>"$NHAN_LIEU"
	fi
}
ensure_nhan

run_one() {
	local muc=$1 rep=$2
	local dose_id="BEN-D1-${muc}-r${rep}"
	local sess="$BEN_DIR/${dose_id}"
	rm -rf "$sess"
	mkdir -p "$sess/data"
	log "=== $dose_id stress-ng --cpu $muc --taskset 0-7 ==="

	start_collector "$sess/data" "$sess/collect.log"

	local t0 t1 stress_pid
	t0=$(mono_ns)
	# phu luc 1.8: phu moi CPU
	stress-ng --cpu "$muc" --taskset 0-7 --timeout 900 >"$sess/stress.log" 2>&1 &
	stress_pid=$!
	sleep 2
	sleep 900
	t1=$(mono_ns)
	kill "$stress_pid" 2>/dev/null || true
	wait "$stress_pid" 2>/dev/null || true

	stop_collect
	sleep 2

	python3 - "$sess/data" "$sess/gap-check.txt" <<'PY'
import glob, os, sys
dd, out = sys.argv[1], sys.argv[2]
msg = []
ok = True
status = os.path.join(dd, "status.tsv")
if os.path.isfile(status):
    lines = [l for l in open(status) if l.strip() and not l.startswith("#") and not l.startswith("wall")]
    msg.append(f"status_lines={len(lines)}")
else:
    msg.append("status.tsv missing"); ok = False
bins = sorted(glob.glob(dd + "/*.bin"))
msg.append(f"bins={len(bins)}")
if not bins:
    ok = False; msg.append("FAIL: khong co .bin")
else:
    sz = sum(os.path.getsize(b) for b in bins)
    msg.append(f"bins_bytes={sz}")
    if sz < 1000: ok = False; msg.append("FAIL: .bin qua nho")
open(out, "w").write("\n".join(msg) + f"\nok={ok}\n")
sys.exit(0 if ok else 1)
PY

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$dose_id" "D1" "$muc" "$t0" "$t1" "stress_cpu_N_taskset0-7" "$muc" \
		"phuluc1.8;benign_duoi_lieu;rep=${rep}" "D1-N=${muc}" >>"$NHAN_LIEU"
	{
		echo "dose_id=$dose_id"
		echo "t0=$t0 t1=$t1"
		echo "stress=stress-ng --cpu $muc --taskset 0-7"
		echo "phuluc=1.8"
		cat "$sess/gap-check.txt"
	} | tee "$sess/xac-nhan.txt" | tee -a "$LOG"

	grep -q 'ok=True' "$sess/gap-check.txt" || { log "LOI gap $dose_id"; exit 1; }
	log "$dose_id DAT gap"
}

log "LAB-1 BEN-D1 phu luc 1.8 bat dau"
for muc in 8 16; do
	for rep in 1 2; do
		run_one "$muc" "$rep"
	done
done

# dung generator neu ta khoi dong
if [[ -f /tmp/lab1-bend1-gen.pid ]]; then
	kill "$(cat /tmp/lab1-bend1-gen.pid)" 2>/dev/null || true
	pkill -f 'lab1_benign_gen.sh' 2>/dev/null || true
	rm -f /tmp/lab1-bend1-gen.pid
fi

echo "ben-d1-v18 xong $(date -Is)" | tee "$VAL/ben-d1-v18-xong.txt"
log "XONG 4 phien BEN-D1-8/16"
exit 0
