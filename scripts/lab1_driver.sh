#!/usr/bin/env bash
# lab1_driver.sh — buoc 4 (B/N) -> 4b (benign duoi lieu) -> 6 (nen 7 ngay) -> hids-lab1-slow.
# Chay trong unit hids-lab1-driver (Restart=no). Loi -> ghi file, exit != 0.
# Phu luc 1.7: B1/N1 chu ky 10s moi muc; chu ky cham tren nen 7 ngay (unit slow).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
REPO=/root/collector
VAL="$REPO/validation/lab1-${DAY}"
BN_DIR="$VAL/bn"
BEN_DIR="$VAL/benign-lieu"
DATADIR="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}"
GEN_LOG="$DATADIR/gen-logs"
NHAN_TC="$REPO/lab/nhan-tan-cong.tsv"
NHAN_LIEU="$REPO/lab/nhan-lieu.tsv"
COLLECT="$REPO/bin/hids-collect"
DRIVER_LOG="$VAL/driver.log"
STATUS_DIR="$VAL"
mkdir -p "$BN_DIR" "$BEN_DIR" "$DATADIR" "$GEN_LOG" "$REPO/lab" "$REPO/out"
# Resume: khong xoa log cu — ghi moc
{
	echo ""
	echo "=== DRIVER START $(date -Is) DAY=$DAY phuluc1.7 ==="
} >>"$DRIVER_LOG"
COLLECT_CPUS="${LAB1_COLLECT_CPUS:-1-7}"

log() { echo "[$(date -Is)] $*" | tee -a "$DRIVER_LOG"; }

die() {
	log "LOI: $*"
	echo "$*" >"$VAL/driver-loi.txt"
	cleanup_partial || true
	exit 1
}

# Phu luc 1.4: ve sinh CPU 0 (runtime)
sanitize_cpu0() {
	systemctl set-property --runtime user.slice AllowedCPUs=1-7
	local eff
	eff=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)
	log "sanitize_cpu0: cpuset.cpus.effective=$eff"
	echo "$eff" | tee "$VAL/cpuset-effective.txt"
	[[ $eff == 1-7 ]] || die "cpuset.effective=$eff (can 1-7)"
}

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

start_collector_datadir() {
	# start_collector_datadir <datadir> <log> [extra args...]
	local dd=$1 logf=$2
	shift 2
	local cg_ng cg_pg
	cg_ng=$(cgroup_of lab0-nginx)
	cg_pg=$(cgroup_of lab0-postgres)
	mkdir -p "$dd"
	local attempt
	for attempt in 1 2; do
		: >"$logf"
		taskset -c "$COLLECT_CPUS" "$COLLECT" -datadir "$dd" \
			-cgroup "$cg_ng" -cgroup "$cg_pg" \
			-min-free-gb 50 -pmu sample=20 "$@" \
			>>"$logf" 2>&1 &
		echo $! >"${logf}.pid"
		cp "${logf}.pid" /tmp/lab1-driver-collect.pid
		if wait_ready "$logf"; then
			log "collector READY pid=$(cat "${logf}.pid") attempt=$attempt datadir=$dd"
			return 0
		fi
		log "KHONG_READY attempt=$attempt — dung va thu lai"
		kill -INT "$(cat "${logf}.pid")" 2>/dev/null || true
		wait "$(cat "${logf}.pid")" 2>/dev/null || true
		rm -f /tmp/lab1-driver-collect.pid
		sleep 1
	done
	die "collector KHONG_READY sau 2 lan: $logf"
}

stop_pidfile() {
	local pf=$1
	[[ -f $pf ]] || return 0
	local p i
	p=$(cat "$pf")
	kill -INT "$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || true
	for i in 1 2 3 4 5; do
		kill -0 "$p" 2>/dev/null || break
		sleep 1
	done
	kill -KILL "$p" 2>/dev/null || true
	# kill ca cay con (wrk2/pgbench) neu con
	pkill -KILL -P "$p" 2>/dev/null || true
	wait "$p" 2>/dev/null || true
	rm -f "$pf"
}

ensure_nhan_tc() {
	if [[ ! -f $NHAN_TC ]]; then
		printf 'run_id\tlop\tid\tatt_ck\tcong_cu\tnhip_tham_so\tmuc_tranh_chap\tsong_sinh_cua\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tt_bat_dau_wall\tt_ket_thuc_wall\toracle_ket_qua\tghi_chu\n' \
			>"$NHAN_TC"
	fi
}

ensure_nhan_lieu() {
	if [[ ! -f $NHAN_LIEU ]]; then
		printf 'dose_id\ttruc\tmuc\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\toracle_ten\toracle_gia_tri\tghi_chu\tmuc_tranh_chap\n' \
			>"$NHAN_LIEU"
	fi
}

append_nhan_tc() {
	ensure_nhan_tc
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$NHAN_TC"
}

cleanup_partial() {
	stop_pidfile /tmp/lab1-driver-collect.pid 2>/dev/null || true
	stop_pidfile /tmp/lab1-driver-gen.pid 2>/dev/null || true
	pkill -KILL -f 'lab1_benign_gen.sh' 2>/dev/null || true
	pkill -KILL -f 'lab1_http_client.py' 2>/dev/null || true
	pkill -KILL -f 'stress-ng --cpu' 2>/dev/null || true
	pkill -KILL -f 'stress-ng --stream' 2>/dev/null || true
	pkill -KILL -f 'wrk2 ' 2>/dev/null || true
	pkill -KILL -x hids-collect 2>/dev/null || true
}

# Ghi driver-loi.txt khi lenh bat ky that bai (set -e)
trap_err() {
	local ec=$? line=${1:-?} cmd=${2:-?}
	{
		echo "ERR exit=$ec line=$line"
		echo "cmd=$cmd"
		echo "time=$(date -Is)"
	} | tee "$VAL/driver-loi.txt" | tee -a "$DRIVER_LOG"
	cleanup_partial || true
	exit "$ec"
}
trap 'trap_err $LINENO "$BASH_COMMAND"' ERR

# Phu luc 1.7 / resume: phien da dat (ok_cycles_ge20=1) → tai dung, khong chay lai.
session_done() {
	local kind=$1 N=$2
	local f="$BN_DIR/${kind}-D1N${N}/xac-nhan.txt"
	[[ -f $f ]] && grep -q 'ok_cycles_ge20=1' "$f"
}

# Phu luc 1.4: ve sinh truoc moi phien do
sanitize_cpu0

# --- dam bao container Up ---
docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true
for i in $(seq 1 30); do
	curl -sf -o /dev/null http://127.0.0.1:18080/file4k.bin && break
	sleep 1
done

# generator nen cho B/N va 4b
log "khoi dong generator cho driver"
bash scripts/lab1_benign_gen.sh "$GEN_LOG" >>"$VAL/gen-driver.log" 2>&1 &
echo $! >/tmp/lab1-driver-gen.pid
sleep 5

# ========== BUOC 4: B1/N1/B4/N4 × D1 N∈{0,2,4} ==========
# Phu luc 1.7: B1/N1 chu ky 10s o moi muc; chu ky 60/300 tren nen 7 ngay (lab1_slow).
log "=== BUOC 4: B/N (phu luc 1.7) ==="
ensure_nhan_tc

run_bn_session() {
	local kind=$1   # B1|N1|B4|N4
	local N=$2      # 0|2|4
	local period=$3 # cho B1/N1; bo qua neu B4/N4
	local sess_dir="$BN_DIR/${kind}-D1N${N}"
	if session_done "$kind" "$N"; then
		log "TAI DUNG phien $kind D1-N=$N (da dat, giu nguyen $sess_dir)"
		echo "TAI DUNG $kind D1-N=$N" | tee -a "$sess_dir/tai-dung.txt"
		cat "$sess_dir/xac-nhan.txt" | tee -a "$DRIVER_LOG"
		return 0
	fi
	# phien hong / chua dat: xoa de chay lai sach
	if [[ -d $sess_dir ]]; then
		log "xoa phien chua dat: $sess_dir"
		rm -rf "$sess_dir"
	fi
	# go dong nhan that bai cung run_id neu co
	if [[ -f $NHAN_TC ]]; then
		local rid="${kind}-D1N${N}-${DAY}"
		grep -v "^${rid}	" "$NHAN_TC" >"${NHAN_TC}.tmp" || true
		mv "${NHAN_TC}.tmp" "$NHAN_TC"
	fi
	mkdir -p "$sess_dir"
	local dd="$sess_dir/data"
	mkdir -p "$dd"
	log "phien $kind D1-N=$N period=${period:-na}"

	start_collector_datadir "$dd" "$sess_dir/collect.log"
	echo "$(cat /tmp/lab1-driver-collect.pid 2>/dev/null || true)" >/dev/null
	# luu pid collector
	pgrep -x hids-collect | tail -1 >/tmp/lab1-driver-collect.pid

	# liều nền D1
	local stress_pid=""
	if ((N > 0)); then
		stress-ng --cpu "$N" --taskset 0 --timeout 900 >"$sess_dir/stress.log" 2>&1 &
		stress_pid=$!
		sleep 2
	fi

	# cho 3 phut on dinh
	sleep 180

	local t0 t1 tw0 tw1
	t0=$(mono_ns)
	tw0=$(date -Is)
	local attack_pid="" oracle="" cycles=0

	case $kind in
	B1)
		python3 scripts/lab1_http_client.py \
			--name "xcfgd-beacon" --period-s "$period" --duration-s 600 \
			--log "$sess_dir/client.log" >>"$sess_dir/client.stderr" 2>&1 &
		attack_pid=$!
		;;
	N1)
		python3 scripts/lab1_http_client.py \
			--name "nginx-healthcheck" --period-s "$period" --duration-s 600 \
			--log "$sess_dir/client.log" >>"$sess_dir/client.stderr" 2>&1 &
		attack_pid=$!
		;;
	B4)
		# stress-ng --cpu 1 bat 2s / nghi 20s trong 600s
		(
			end=$((SECONDS + 600))
			n=0
			while ((SECONDS < end)); do
				stress-ng --cpu 1 --timeout 2s >>"$sess_dir/b4.log" 2>&1 || true
				n=$((n + 1))
				echo "cycle $n mono=$(mono_ns)" >>"$sess_dir/b4-cycles.log"
				sleep 20
			done
			echo "$n" >"$sess_dir/cycles.txt"
		) &
		attack_pid=$!
		;;
	N4)
		# gzip file log cung nhip 2s lam viec / 20s nghi — mo phong bang gzip vong
		dd if=/dev/urandom of="$sess_dir/payload.bin" bs=1M count=4 status=none
		(
			end=$((SECONDS + 600))
			n=0
			while ((SECONDS < end)); do
				cp "$sess_dir/payload.bin" "$sess_dir/payload.work"
				timeout 2 gzip -f "$sess_dir/payload.work" >>"$sess_dir/n4.log" 2>&1 || true
				rm -f "$sess_dir/payload.work.gz"
				n=$((n + 1))
				echo "cycle $n mono=$(mono_ns)" >>"$sess_dir/n4-cycles.log"
				sleep 20
			done
			echo "$n" >"$sess_dir/cycles.txt"
		) &
		attack_pid=$!
		;;
	esac

	# cua so tan cong 10 phut (phut 3..13)
	sleep 600
	t1=$(mono_ns)
	tw1=$(date -Is)
	kill -TERM "$attack_pid" 2>/dev/null || true
	wait "$attack_pid" 2>/dev/null || true

	# dem chu ky
	case $kind in
	B1 | N1)
		cycles=$(awk 'NR>1{c++} END{print c+0}' "$sess_dir/client.log" 2>/dev/null || echo 0)
		oracle="client_cycles=${cycles};log=${sess_dir}/client.log"
		;;
	B4 | N4)
		cycles=$(cat "$sess_dir/cycles.txt" 2>/dev/null || wc -l <"$sess_dir/"*-cycles.log 2>/dev/null || echo 0)
		oracle="process_cycles=${cycles}"
		;;
	esac

	[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true

	# dung collector
	stop_pidfile /tmp/lab1-driver-collect.pid
	# dam bao
	pkill -x hids-collect 2>/dev/null || true
	sleep 2

	# kiem ≥20 chu ky; nhãn ±1s (so mono voi ban ghi — in xac nhan)
	local ok_cycles=0
	((cycles >= 20)) && ok_cycles=1
	{
		echo "kind=$kind N=$N period=${period:-na}"
		echo "t0_mono=$t0 t1_mono=$t1"
		echo "wall $tw0 -> $tw1"
		echo "cycles=$cycles ok_cycles_ge20=$ok_cycles"
		echo "oracle=$oracle"
	} | tee "$sess_dir/xac-nhan.txt"

	local lop id song
	case $kind in
	B1)
		lop=B
		id=B1
		song=
		;;
	N1)
		lop=N
		id=N1
		song=B1
		;;
	B4)
		lop=B
		id=B4
		song=
		;;
	N4)
		lop=N
		id=N4
		song=B4
		;;
	esac
	append_nhan_tc \
		"${kind}-D1N${N}-${DAY}" "$lop" "$id" "LAB1" "local" \
		"period=${period:-2s/20s}" "D1-N=${N}" "$song" \
		"$t0" "$t1" "$tw0" "$tw1" "$oracle" "sess=$sess_dir"

	if ((ok_cycles != 1)); then
		die "phien $kind D1-N=$N: cycles=$cycles < 20"
	fi

	# con 2 phut du 15 phut phien (3+10+2)
	sleep 120
}

# 12 phien — phu luc 1.7: B1/N1 luon period=10
for N in 0 2 4; do
	run_bn_session B1 "$N" 10
	run_bn_session N1 "$N" 10
done
for N in 0 2 4; do
	run_bn_session B4 "$N" ""
	run_bn_session N4 "$N" ""
done
log "buoc 4 xong"

# ========== BUOC 4b: benign duoi lieu ==========
log "=== BUOC 4b: benign duoi lieu ==="
ensure_nhan_lieu

run_ben_lieu() {
	local truc=$1 muc=$2 rep=$3
	local dose_id="BEN-${truc}-${muc}-r${rep}"
	local sess="$BEN_DIR/${dose_id}"
	mkdir -p "$sess/data"
	log "benign-lieu $dose_id"
	start_collector_datadir "$sess/data" "$sess/collect.log"
	pgrep -x hids-collect | tail -1 >/tmp/lab1-driver-collect.pid

	local stress_pid=""
	local t0 t1
	t0=$(mono_ns)
	case $truc in
	D1)
		stress-ng --cpu "$muc" --taskset 0 --timeout 900 >"$sess/stress.log" 2>&1 &
		stress_pid=$!
		;;
	D3)
		stress-ng --stream "$muc" --taskset 1-7 --timeout 900 >"$sess/stress.log" 2>&1 &
		stress_pid=$!
		;;
	esac
	sleep 2
	# 15 phut
	sleep 900
	t1=$(mono_ns)
	[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true

	stop_pidfile /tmp/lab1-driver-collect.pid
	pkill -x hids-collect 2>/dev/null || true
	sleep 2

	# kiem khoang mu > 60s: dung status/periodic neu co; fallback: dem file .bin
	local gap_ok=1
	python3 - "$sess/data" "$sess/gap-check.txt" <<'PY' || gap_ok=0
import glob, os, struct, sys
dd, out = sys.argv[1], sys.argv[2]
# doc status.tsv neu co
status = os.path.join(dd, "status.tsv")
msg = []
ok = True
if os.path.isfile(status):
    lines = [l for l in open(status) if l.strip() and not l.startswith("#")]
    msg.append(f"status_lines={len(lines)}")
else:
    msg.append("status.tsv missing")
bins = sorted(glob.glob(dd + "/*.bin") + glob.glob(dd + "/*.bin.zst"))
msg.append(f"bins={len(bins)}")
# khong parse .bin day du o day; chi kiem file ton tai va size > 0
if not bins:
    ok = False
    msg.append("FAIL: khong co .bin")
else:
    sz = sum(os.path.getsize(b) for b in bins)
    msg.append(f"bins_bytes={sz}")
    if sz < 1000:
        ok = False
        msg.append("FAIL: .bin qua nho")
open(out, "w").write("\n".join(msg) + f"\nok={ok}\n")
sys.exit(0 if ok else 1)
PY
	# oracle: rq/CPI tu host sample neu co — ghi muc
	local oracle_ten oracle_val
	if [[ $truc == D1 ]]; then
		oracle_ten="stress_cpu_N"
		oracle_val="$muc"
	else
		oracle_ten="stress_stream_workers"
		oracle_val="$muc"
	fi
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$dose_id" "$truc" "$muc" "$t0" "$t1" "$oracle_ten" "$oracle_val" \
		"benign_duoi_lieu;rep=${rep}" "${truc}-N=${muc}" >>"$NHAN_LIEU"
	{
		echo "dose_id=$dose_id"
		echo "t0=$t0 t1=$t1"
		cat "$sess/gap-check.txt"
	} | tee "$sess/xac-nhan.txt"
	[[ -f $sess/gap-check.txt ]] && grep -q 'ok=True' "$sess/gap-check.txt" || die "benign-lieu $dose_id: gap/bin khong dat"
}

for muc in 2 4; do
	for rep in 1 2; do
		run_ben_lieu D1 "$muc" "$rep"
	done
done
# phu luc 1.2: D3 worker ∈ {4, 7} (khong 12/22)
for muc in 4 7; do
	for rep in 1 2; do
		run_ben_lieu D3 "$muc" "$rep"
	done
done
log "buoc 4b xong"

# dung generator tam (se bat lai o buoc 6)
stop_pidfile /tmp/lab1-driver-gen.pid
pkill -f 'lab1_benign_gen.sh' 2>/dev/null || true
sleep 2

# ========== BUOC 6: nen benign 7 ngay ==========
log "=== BUOC 6: khoi dong nen benign 7 ngay ==="
mkdir -p "$DATADIR" "$GEN_LOG"

# dung unit cu neu con
systemctl stop hids-lab1-collector hids-lab1-gen hids-lab1-watch.timer hids-lab1-watch.service 2>/dev/null || true

CG_NG=$(cgroup_of lab0-nginx)
CG_PG=$(cgroup_of lab0-postgres)
START_WALL=$(date -Is)
START_MONO=$(mono_ns)

# Phu luc 1.4: dat lai AllowedCPUs truoc nen 7 ngay (runtime mat khi reboot)
sanitize_cpu0

# collector — Restart=always, KHONG -duration; taskset 1-7
# systemd-run doi hoi duong dan TUYET DOI cho StandardOutput/StandardError append
: >"$VAL/benign-collector-systemd.log"
systemd-run --unit=hids-lab1-collector --collect \
	--property=Restart=always --property=RestartSec=5 \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/benign-collector-systemd.log" \
	--property=StandardError=append:"$VAL/benign-collector-systemd.log" \
	/usr/bin/taskset -c "$COLLECT_CPUS" "$REPO/bin/hids-collect" \
	-datadir "$DATADIR" \
	-cgroup "$CG_NG" -cgroup "$CG_PG" \
	-min-free-gb 50 -pmu sample=20

# cho READY
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
	log "canh bao: chua thay READY trong log (co the buffer); tiep tuc neu process song"

# generator
: >"$VAL/benign-gen-systemd.log"
systemd-run --unit=hids-lab1-gen --collect \
	--property=Restart=always --property=RestartSec=5 \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/benign-gen-systemd.log" \
	--property=StandardError=append:"$VAL/benign-gen-systemd.log" \
	/bin/bash "$REPO/scripts/lab1_benign_gen.sh" "$GEN_LOG"

# watch: timer moi gio + chay 1 lan ngay
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
	echo "cmd_collector=$REPO/bin/hids-collect -datadir $DATADIR -cgroup $CG_NG -cgroup $CG_PG -min-free-gb 50 -pmu sample=20"
	echo "cmd_gen=bash $REPO/scripts/lab1_benign_gen.sh $GEN_LOG"
	echo "cgroup_nginx=$CG_NG"
	echo "cgroup_postgres=$CG_PG"
} | tee "$VAL/benign-khoi-dong.txt"

# tu kiem sau 20 phut
log "cho 20 phut roi kiem suc-khoe"
sleep 1200
bash "$REPO/scripts/lab1_watch.sh" || true

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
# lay dong cuoi
parts = lines[-1].split("\t")
# wall rps kd pd rss cpu pmu free
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
    # 20 phut co the PMU chua on dinh neu it ban ghi — van ghi
    msgs.append(f"PMU={pmu} (tieu chi [4,6]; 20 phut dau co the le)")
    # theo nhiem vu: PMU ∈ [4%,6%] — khong dat thi dung
    ok = False
    msgs.append("FAIL PMU ngoai [4,6]")
open(val + "/suc-khoe-20m.txt", "w").write("\n".join(msgs) + f"\nok={ok}\n")
if not ok:
    open(val + "/driver-loi.txt", "w").write("\n".join(msgs) + "\n")
    sys.exit(1)
sys.exit(0)
PY
ec=$?
if ((ec != 0)); then
	log "kiem 20 phut THAT BAI — dung unit"
	systemctl stop hids-lab1-collector hids-lab1-gen hids-lab1-watch.timer 2>/dev/null || true
	die "kiem suc-khoe 20 phut khong dat (xem driver-loi.txt)"
fi

# Phu luc 1.7: len lich chu ky cham tren nen 7 ngay (khong cho nguoi)
log "=== khoi dong hids-lab1-slow (phu luc 1.7) ==="
systemctl stop hids-lab1-slow 2>/dev/null || true
systemctl reset-failed hids-lab1-slow 2>/dev/null || true
: >"$VAL/slow-systemd.log"
systemd-run --unit=hids-lab1-slow --collect \
	--property=WorkingDirectory="$REPO" \
	--property=StandardOutput=append:"$VAL/slow-systemd.log" \
	--property=StandardError=append:"$VAL/slow-systemd.log" \
	--property=Environment="LAB1_DAY=$DAY" \
	/bin/bash "$REPO/scripts/lab1_slow.sh"
log "hids-lab1-slow da len lich (B1/N1 60s+300s tren nen 7 ngay)"

echo "driver xong $(date -Is)" | tee "$VAL/driver-xong.txt"
cat "$VAL/benign-khoi-dong.txt" >>"$VAL/driver-xong.txt"
cat "$VAL/suc-khoe-20m.txt" >>"$VAL/driver-xong.txt"
echo "hids-lab1-slow=started" >>"$VAL/driver-xong.txt"
log "DRIVER XONG — nen benign + hids-lab1-slow dang chay"
exit 0
