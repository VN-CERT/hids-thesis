#!/usr/bin/env bash
# lab1_driver6.sh — CHI buoc 6 (+ hids-lab1-slow). Khong chay lai 4/4b.
# Loi script cu: StandardOutput append path tuong doi → systemd-run tu choi.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DAY="${LAB1_DAY:-20261024}"
REPO=/root/collector
VAL="$REPO/validation/lab1-${DAY}"
DATADIR="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}"
GEN_LOG="$DATADIR/gen-logs"
COLLECT="$REPO/bin/hids-collect"
DRIVER_LOG="$VAL/driver6.log"
COLLECT_CPUS="${LAB1_COLLECT_CPUS:-1-7}"
mkdir -p "$VAL" "$DATADIR" "$GEN_LOG"

log() { echo "[$(date -Is)] $*" | tee -a "$DRIVER_LOG"; }

die() {
	log "LOI: $*"
	echo "$*" >"$VAL/driver-loi.txt"
	exit 1
}

trap_err() {
	local ec=$? line=${1:-?} cmd=${2:-?}
	{
		echo "ERR exit=$ec line=$line"
		echo "cmd=$cmd"
		echo "time=$(date -Is)"
	} | tee "$VAL/driver-loi.txt" | tee -a "$DRIVER_LOG"
	exit "$ec"
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

cgroup_of() {
	local id
	id=$(docker inspect -f '{{.Id}}' "$1")
	echo "/sys/fs/cgroup/system.slice/docker-${id}.scope"
}

sanitize_cpu0() {
	systemctl set-property --runtime user.slice AllowedCPUs=1-7
	local eff
	eff=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)
	log "sanitize_cpu0: cpuset.cpus.effective=$eff"
	echo "$eff" | tee "$VAL/cpuset-effective.txt"
	[[ $eff == 1-7 ]] || die "cpuset.effective=$eff (can 1-7)"
}

{
	echo ""
	echo "=== DRIVER6 START $(date -Is) DAY=$DAY ==="
} >>"$DRIVER_LOG"

log "=== BUOC 6 (driver6): khoi dong nen benign 7 ngay ==="
mkdir -p "$DATADIR" "$GEN_LOG"

docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true
for i in $(seq 1 30); do
	curl -sf -o /dev/null http://127.0.0.1:18080/file4k.bin && break
	sleep 1
done

systemctl stop hids-lab1-collector hids-lab1-gen hids-lab1-watch.timer hids-lab1-watch.service hids-lab1-slow 2>/dev/null || true
systemctl reset-failed hids-lab1-collector hids-lab1-gen hids-lab1-watch hids-lab1-slow 2>/dev/null || true
pkill -KILL -x hids-collect 2>/dev/null || true
pkill -KILL -f 'lab1_benign_gen.sh' 2>/dev/null || true
sleep 1

CG_NG=$(cgroup_of lab0-nginx)
CG_PG=$(cgroup_of lab0-postgres)
START_WALL=$(date -Is)
START_MONO=$(mono_ns)

sanitize_cpu0

: >"$VAL/benign-collector-systemd.log"
systemd-run --unit=hids-lab1-collector --collect \
	--property=Restart=always --property=RestartSec=5 \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/benign-collector-systemd.log" \
	--property=StandardError=append:"$VAL/benign-collector-systemd.log" \
	/usr/bin/taskset -c "$COLLECT_CPUS" "$COLLECT" \
	-datadir "$DATADIR" \
	-cgroup "$CG_NG" -cgroup "$CG_PG" \
	-min-free-gb 50 -pmu sample=20

for i in $(seq 1 40); do
	if grep -qx READY "$VAL/benign-collector-systemd.log" 2>/dev/null; then
		break
	fi
	if [[ -f $DATADIR/status.tsv ]] || ls "$DATADIR"/*.bin >/dev/null 2>&1; then
		break
	fi
	sleep 0.5
done
pgrep -x hids-collect >/dev/null || die "hids-lab1-collector khong chay"
grep -qx READY "$VAL/benign-collector-systemd.log" 2>/dev/null || \
	log "canh bao: chua thay READY trong log; tiep neu process song"

: >"$VAL/benign-gen-systemd.log"
systemd-run --unit=hids-lab1-gen --collect \
	--property=Restart=always --property=RestartSec=5 \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/benign-gen-systemd.log" \
	--property=StandardError=append:"$VAL/benign-gen-systemd.log" \
	/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$GEN_LOG"

systemd-run --unit=hids-lab1-watch --collect \
	--on-calendar='*-*-* *:05:00' \
	/bin/bash "$REPO/scripts/lab1_watch.sh"
bash "$REPO/scripts/lab1_watch.sh" || true

{
	echo "start_wall=$START_WALL"
	echo "start_mono_ns=$START_MONO"
	echo "datadir=$DATADIR"
	echo "unit_collector=hids-lab1-collector"
	echo "unit_gen=hids-lab1-gen"
	echo "unit_watch=hids-lab1-watch.timer"
	echo "cmd_collector=$COLLECT -datadir $DATADIR -cgroup $CG_NG -cgroup $CG_PG -min-free-gb 50 -pmu sample=20"
	echo "cmd_gen=bash $REPO/scripts/lab1_benign_gen.sh $GEN_LOG"
	echo "cgroup_nginx=$CG_NG"
	echo "cgroup_postgres=$CG_PG"
	echo "driver6=1"
} | tee "$VAL/benign-khoi-dong.txt"

log "cho 20 phut roi kiem suc-khoe"
sleep 1200
bash "$REPO/scripts/lab1_watch.sh" || true

set +e
python3 - "$DATADIR/suc-khoe.tsv" "$VAL" <<'PY'
import sys
tsv, val = sys.argv[1], sys.argv[2]
try:
    lines = [l for l in open(tsv) if l.strip() and not l.startswith("wall")]
except FileNotFoundError:
    open(val + "/driver-loi.txt", "w").write("suc-khoe.tsv khong ton tai sau 20 phut\n")
    sys.exit(1)
if len(lines) < 1:
    open(val + "/driver-loi.txt", "w").write("suc-khoe.tsv khong co dong hop le\n")
    sys.exit(1)
parts = lines[-1].split("\t")
if len(parts) < 8:
    open(val + "/driver-loi.txt", "w").write(f"dong malform: {lines[-1]}\n")
    sys.exit(1)
kd, pd, pmu = parts[2], parts[3], float(parts[6] or 0)
ok = True
msgs = [f"dong={lines[-1].strip()}"]
if float(kd or 0) != 0 or float(pd or 0) != 0:
    ok = False
    msgs.append(f"FAIL drops kd={kd} pd={pd}")
if not (4.0 <= pmu <= 6.0):
    msgs.append(f"PMU={pmu} (tieu chi [4,6])")
    ok = False
    msgs.append("FAIL PMU ngoai [4,6]")
open(val + "/suc-khoe-20m.txt", "w").write("\n".join(msgs) + f"\nok={ok}\n")
if not ok:
    open(val + "/driver-loi.txt", "w").write("\n".join(msgs) + "\n")
    sys.exit(1)
sys.exit(0)
PY
ec=$?
set -e
if ((ec != 0)); then
	log "kiem 20 phut THAT BAI — dung unit"
	systemctl stop hids-lab1-collector hids-lab1-gen hids-lab1-watch.timer 2>/dev/null || true
	die "kiem suc-khoe 20 phut khong dat (xem driver-loi.txt)"
fi

log "=== khoi dong hids-lab1-slow (phu luc 1.7) ==="
: >"$VAL/slow-systemd.log"
systemd-run --unit=hids-lab1-slow --collect \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/slow-systemd.log" \
	--property=StandardError=append:"$VAL/slow-systemd.log" \
	--property=Environment="LAB1_DAY=$DAY" \
	/bin/bash "$REPO/scripts/lab1_slow.sh"
log "hids-lab1-slow da len lich"

echo "driver xong $(date -Is) (driver6)" | tee "$VAL/driver-xong.txt"
cat "$VAL/benign-khoi-dong.txt" >>"$VAL/driver-xong.txt"
cat "$VAL/suc-khoe-20m.txt" >>"$VAL/driver-xong.txt"
echo "hids-lab1-slow=started" >>"$VAL/driver-xong.txt"
log "DRIVER6 XONG — nen benign + hids-lab1-slow dang chay"
exit 0
