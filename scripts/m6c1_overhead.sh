#!/usr/bin/env bash
# M6c-1 muc 4: bo overhead CUOI, cau hinh production. Ban sao cua
# scripts/m6c_overhead.sh voi cac khac biet:
#  - Dieu kien: C0 khong collector; C1 bi do -pmu host (tuong minh); C2 khong bi
#    do (cgroup decoy) -pmu host. Moi co khac MAC DINH. Khong co o -pmu on/off.
#  - T4 kich tran dung wrk GOC (nhu M5f/M5h), khong phai wrk2.
#  - pgtest dung dung tuy chon chong nhieu cua M5h (checkpoint_timeout=30min,
#    max_wal_size=8GB, autovacuum=off); VACUUM + CHECKPOINT truoc moi luot T3.
#  - Them T3-R50. Mot luot C0 cua T3 ghi kem iostat.
#  - M6c-1 1d: cho READY toi da 20s; khong thay -> ghi KHONG_READY vao log luot
#    va tu chay lai luot (toi da 2 lan chay lai). Sau luot C1: ban ghi/giay > 0,
#    bang 0 -> luot hong, chay lai. Khong thay so tay.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" PATH="/usr/local/go/bin:/root/go/bin:/usr/local/bin:${PATH}"
source scripts/hids_data_policy.sh

OUTROOT="${1:?can thu muc output}"
RUNS="${M6C_RUNS:-10}"
REST="${M6C_REST:-10}"
mkdir -p "$OUTROOT"
LOG="$OUTROOT/overhead.log"
exec >>"$LOG" 2>&1
COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
PARSE=./analysis/m5f_parse.py
STATUS="out/jobs/m6c1-overhead.status"

say() { echo "[$(date -Is)] $*"; echo "$(date -Is) $*" >"$STATUS"; }

mapfile -t RUNNING_CONTAINERS < <(docker ps --format '{{.Names}}')
cleanup() {
	docker rm -f pgtest m5-nginx >/dev/null 2>&1 || true
	if ((${#RUNNING_CONTAINERS[@]})); then
		docker start "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

cgroup_path_of_pid() { echo "/sys/fs/cgroup$(awk -F: '$1=="0" {print $3}' "/proc/$1/cgroup")"; }
docker_cgroup() { cgroup_path_of_pid "$(docker inspect -f '{{.State.Pid}}' "$1")"; }
scope_main_pid() {
	local u=$1 cg pid
	[[ $u != *.scope ]] && u="${u}.scope"
	cg=$(systemctl show "$u" -p ControlGroup --value 2>/dev/null) || return 1
	pid=$(head -1 "/sys/fs/cgroup${cg}/cgroup.procs" 2>/dev/null)
	[[ -n $pid ]] && echo "$pid"
}
scope_usage_usec() { awk '/^usage_usec/{print $2}' "$1/cpu.stat" 2>/dev/null || echo 0; }

# Cho READY toi da 20 giay. 0 = thay READY, 1 = khong.
wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	return 1
}
wait_pid_gone() {
	local pid=$1 i
	for ((i = 0; i < 600; i++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	say "LOI: pid $pid khong ket thuc"; return 1
}

CELL_FAIL=0
COLL_PID=""
# start_collector <cond> <cgroup dich> <dir> <tag>
start_collector() {
	local cond=$1 cg=$2 dir=$3 tag=$4
	mkdir -p "$DECOY_CG"
	local unit="hids-m6c1-oh-$tag"
	systemd-run --scope --unit="$unit" --slice=system.slice -- \
		"$COLLECT" -cgroup "$cg" -pmu host -duration 180s -out "$dir/collect.bin" 2>"$dir/collect.log" &
	sleep 0.5
	COLL_PID=$(scope_main_pid "$unit") || COLL_PID=""
	if ! wait_ready "$dir/collect.log"; then
		echo "KHONG_READY" >>"$dir/collect.log"
		say "KHONG_READY $tag"
		CELL_FAIL=1
		stop_collector
		return 1
	fi
	return 0
}
stop_collector() {
	[[ -n $COLL_PID ]] && kill -INT "$COLL_PID" 2>/dev/null || true
	[[ -n $COLL_PID ]] && wait_pid_gone "$COLL_PID"
	COLL_PID=""
}
# coll_stats <dir>: ghi ban ghi, ban ghi/giay va mat; rps <= 0 -> CELL_FAIL=1.
coll_stats() {
	local dir=$1
	python3 - "$dir" <<'PY'
import re, subprocess, sys, pathlib
d = pathlib.Path(sys.argv[1])
log = (d / "collect.log").read_text(errors="replace") if (d / "collect.log").exists() else ""
m = re.search(r"ban ghi doc duoc: (\d+) \| so lan dinh ghi: (\d+) \| mat: (\d+)", log)
recs = int(m.group(1)) if m else 0
drops = m.group(3) if m else "?"
rps = 0.0
binp = d / "collect.bin"
if binp.exists() and recs:
    out = subprocess.run(["./bin/rec-stat", str(binp)], capture_output=True, text=True).stdout
    mm = re.search(r"ts_enter nho nhat / lon nhat: (\d+) / (\d+)", out)
    if mm:
        span = (int(mm.group(2)) - int(mm.group(1))) / 1e9
        if span > 0:
            rps = recs / span
(d / "collect-stats.txt").write_text(f"ban_ghi={recs} ban_ghi_giay={rps:.1f} mat={drops}\n")
print(f"ban_ghi={recs} ban_ghi_giay={rps:.1f} mat={drops}")
sys.exit(0 if rps > 0 else 1)
PY
}

# attempt_cell <nhan> <ham> <args...>: chay lai toi da 2 lan khi CELL_FAIL.
attempt_cell() {
	local label=$1; shift
	local try
	for try in 1 2 3; do
		CELL_FAIL=0
		"$@" || CELL_FAIL=1
		if [[ $CELL_FAIL == 0 ]]; then
			[[ $try -gt 1 ]] && say "$label dat o lan thu $try"
			return 0
		fi
		say "$label hong (lan $try/3), chay lai"
	done
	say "LOI: $label hong ca 3 lan"
	return 1
}

setup_pg() {
	docker rm -f pgtest >/dev/null 2>&1 || true
	# Dung dung M5h: kem tuy chon chong nhieu cua postgres.
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine \
		-c checkpoint_timeout=30min -c max_wal_size=8GB -c autovacuum=off >/dev/null
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || { say "LOI: pgtest khong ready"; exit 1; }
	for i in $(seq 1 5); do
		docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 && return 0
		sleep 3
	done
	say "LOI: pgbench -i that bai"; exit 1
}
setup_nginx() {
	docker rm -f m5-nginx >/dev/null 2>&1 || true
	local tmpd
	tmpd=$(mktemp -d)
	dd if=/dev/urandom of="$tmpd/f.bin" bs=4096 count=1 2>/dev/null
	chmod 755 "$tmpd" "$tmpd/f.bin"
	docker run -d --name m5-nginx --cpuset-cpus 12-15 \
		-v "$tmpd:/usr/share/nginx/html:ro" -p 18080:80 nginx:alpine >/dev/null
	sleep 2
}
# Dung dung M5h pg_maintain.
pg_prep() { docker exec pgtest psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'VACUUM;' -c 'CHECKPOINT;' >/dev/null 2>&1 || true; }

# ---------- T1 ----------
t1_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T1/$cond/run$run"
	mkdir -p "$dir"
	local spid t0 t1 fifo="$dir/in.fifo"
	rm -f "$fifo"; mkfifo "$fifo"
	exec 8<>"$fifo"
	taskset -c 12 "$SYSINJ" -n 10000000 <"$fifo" >"$dir/sysinj.log" 2>&1 &
	spid=$!
	sleep 0.3
	if [[ $cond == "C1" ]]; then
		"$COLLECT" -pid "$spid" -pmu host -duration 60s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		COLL_PID=$!
		if ! wait_ready "$dir/collect.log"; then
			echo "KHONG_READY" >>"$dir/collect.log"
			say "KHONG_READY t1-$cond-$run"
			exec 8>&-; rm -f "$fifo"
			stop_collector
			return 1
		fi
	elif [[ $cond == "C2" ]]; then
		start_collector C2 "$DECOY_CG" "$dir" "t1-$cond-$run" || { exec 8>&-; rm -f "$fifo"; return 1; }
	fi
	t0=$(date +%s%N)
	printf '.' >&8
	wait "$spid" 2>/dev/null || true
	t1=$(date +%s%N)
	exec 8>&-
	rm -f "$fifo"
	stop_collector
	if [[ $cond == "C1" ]]; then
		coll_stats "$dir" >>"$LOG" 2>&1 || return 1
	fi
	python3 -c "
ns = ($t1 - $t0) / 10000000
print(f'{ns:.2f}')" >"$dir/value.txt"
	echo "T1 $cond run$run: $(cat "$dir/value.txt") ns/syscall"
	return 0
}

# ---------- T4 kich tran (wrk goc nhu M5f/M5h) ----------
t4_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/$cond/run$run"
	mkdir -p "$dir"
	local cg usec0 usec1
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1) start_collector C1 "$cg" "$dir" "t4-$cond-$run" || return 1 ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t4-$cond-$run" || return 1 ;;
	esac
	taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk.txt" 2>&1 || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	grep -oE "Requests/sec:\s*[0-9.]+" "$dir/wrk.txt" | awk '{print $2}' >"$dir/value.txt" || true
	if [[ $cond == "C1" ]]; then
		coll_stats "$dir" >>"$LOG" 2>&1 || return 1
	fi
	echo "T4 $cond run$run: $(cat "$dir/value.txt" 2>/dev/null) req/s"
	return 0
}

# ---------- T3 kich tran ----------
t3_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T3/$cond/run$run"
	mkdir -p "$dir"
	local cg usec0 usec1
	cg=$(docker_cgroup pgtest)
	pg_prep
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0)
		if [[ $run == 1 ]]; then
			# Ghi kem iostat cho thiet bi chua du lieu pgtest trong luot C0 dau.
			local dev
			dev=$(df --output=source /var/lib/docker 2>/dev/null | tail -1)
			{ echo "thiet_bi_df=$dev"; lsblk -no NAME,TYPE "$dev" 2>/dev/null || true; } >"$dir/iostat-meta.txt"
			(iostat -x 1 60 >"$dir/iostat.txt" 2>&1 &)
		fi
		;;
	C1) start_collector C1 "$cg" "$dir" "t3-$cond-$run" || return 1 ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t3-$cond-$run" || return 1 ;;
	esac
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	python3 "$PARSE" pgbench "$dir/pglog.1" >"$dir/parse.txt" 2>&1 || true
	awk -F'\t' '{print $3}' "$dir/parse.txt" >"$dir/value.txt"
	if [[ $cond == "C1" ]]; then
		coll_stats "$dir" >>"$LOG" 2>&1 || return 1
	fi
	echo "T3 $cond run$run: $(cat "$dir/value.txt" 2>/dev/null) tps"
	return 0
}

median_of() {
	python3 - "$1" <<'PY'
import glob, statistics, sys
vals = [float(open(p).read().strip()) for p in glob.glob(sys.argv[1]) if open(p).read().strip()]
print(statistics.median(vals))
PY
}

# ---------- tai co dinh ----------
t3r_run() {
	local pct=$1 cond=$2 run=$3 base=$4
	local dir="$OUTROOT/T3-R$pct/$cond/run$run"
	mkdir -p "$dir"
	local rate cg usec0 usec1
	rate=$(python3 -c "print($base * $pct / 100.0)")
	cg=$(docker_cgroup pgtest)
	pg_prep
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1) start_collector C1 "$cg" "$dir" "t3r$pct-$cond-$run" || return 1 ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t3r$pct-$cond-$run" || return 1 ;;
	esac
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -R $rate -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "target_tps=$rate cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	python3 "$PARSE" pgbench --target "$rate" "$dir/pglog.1" >"$dir/parse.txt" 2>&1 || true
	if [[ $cond == "C1" ]]; then
		coll_stats "$dir" >>"$LOG" 2>&1 || return 1
	fi
	echo "T3-R$pct $cond run$run xong"
	return 0
}
t4r_run() {
	local pct=$1 cond=$2 run=$3 base=$4
	local dir="$OUTROOT/T4-R$pct/$cond/run$run"
	mkdir -p "$dir"
	local rate cg usec0 usec1
	rate=$(python3 -c "import math; print(max(1,int($base * $pct / 100.0)))")
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1) start_collector C1 "$cg" "$dir" "t4r$pct-$cond-$run" || return 1 ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t4r$pct-$cond-$run" || return 1 ;;
	esac
	taskset -c 16-19 /usr/local/bin/wrk2 -t4 -c64 -d60s -R "$rate" --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "target_rps=$rate cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	python3 "$PARSE" wrk2 --target "$rate" "$dir/wrk2.txt" >"$dir/parse.txt" 2>&1 || true
	if [[ $cond == "C1" ]]; then
		coll_stats "$dir" >>"$LOG" 2>&1 || return 1
	fi
	echo "T4-R$pct $cond run$run xong"
	return 0
}

# ================= main =================
say "m6c1 overhead bat dau, RUNS=$RUNS, out=$OUTROOT"
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py analysis/m6c_stats.py tools/coreclk.c || true
git rev-parse --short HEAD
command -v wrk || { say "DUNG: khong co wrk goc"; exit 1; }
if ((${#RUNNING_CONTAINERS[@]})); then
	docker stop "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
fi
setup_pg
setup_nginx

say "T1"
for ((run = 1; run <= RUNS; run++)); do
	for cond in C0 C1 C2; do attempt_cell "T1-$cond-$run" t1_run "$cond" "$run"; done
done

say "T4 kich tran (wrk goc)"
for ((run = 1; run <= RUNS; run++)); do
	for cond in C0 C1 C2; do attempt_cell "T4-$cond-$run" t4_sat_run "$cond" "$run"; sleep "$REST"; done
done

say "T3 kich tran"
for ((run = 1; run <= RUNS; run++)); do
	for cond in C0 C1 C2; do attempt_cell "T3-$cond-$run" t3_sat_run "$cond" "$run"; sleep "$REST"; done
done

T3_C0=$(median_of "$OUTROOT/T3/C0/run*/value.txt")
T4_C0=$(median_of "$OUTROOT/T4/C0/run*/value.txt")
say "C0 kich tran dot nay: T3 median=$T3_C0 tps, T4 median=$T4_C0 req/s"

for pct in 25 50; do
	say "T3-R$pct"
	for ((run = 1; run <= RUNS; run++)); do
		for cond in C0 C1 C2; do attempt_cell "T3-R$pct-$cond-$run" t3r_run "$pct" "$cond" "$run" "$T3_C0"; sleep "$REST"; done
	done
done
for pct in 25 50; do
	say "T4-R$pct"
	for ((run = 1; run <= RUNS; run++)); do
		for cond in C0 C1 C2; do attempt_cell "T4-R$pct-$cond-$run" t4r_run "$pct" "$cond" "$run" "$T4_C0"; sleep "$REST"; done
	done
done

say "tong hop TSV"
python3 - "$OUTROOT" <<'PY'
import csv, glob, pathlib, re, sys
root = pathlib.Path(sys.argv[1])

def w(name, rows):
    with open(root / name, "w", newline="") as f:
        wtr = csv.writer(f, delimiter="\t")
        wtr.writerow(["load", "cond", "run", "value"])
        wtr.writerows(rows)

for load in ("T1", "T3", "T4"):
    rows = []
    for vf in sorted(glob.glob(str(root / load / "*" / "run*" / "value.txt"))):
        p = pathlib.Path(vf)
        txt = p.read_text().strip()
        if txt:
            rows.append([load, p.parent.parent.name, p.parent.name.replace("run", ""), txt])
    w(f"{load}.tsv", rows)

for load in ("T3-R25", "T3-R50", "T4-R25", "T4-R50"):
    for metric, idx in (("lat_avg", 3), ("p50", 4), ("p99", 5)):
        rows = []
        for pf in sorted(glob.glob(str(root / load / "*" / "run*" / "parse.txt"))):
            p = pathlib.Path(pf)
            parts = p.read_text().strip().split("\t")
            if len(parts) >= 7:
                rows.append([load, p.parent.parent.name, p.parent.name.replace("run", ""), parts[idx]])
        w(f"{load}-{metric}.tsv", rows)
    rows = []
    for mf in sorted(glob.glob(str(root / load / "*" / "run*" / "meta.txt"))):
        p = pathlib.Path(mf)
        m = re.search(r"cgroup_cpu_usec=(\d+)", p.read_text())
        if m:
            rows.append([load, p.parent.parent.name, p.parent.name.replace("run", ""), m.group(1)])
    w(f"{load}-cgroupcpu.tsv", rows)
print("tsv xong")
PY
for f in "$OUTROOT"/T1.tsv "$OUTROOT"/T3.tsv "$OUTROOT"/T4.tsv "$OUTROOT"/T3-R25-*.tsv "$OUTROOT"/T3-R50-*.tsv "$OUTROOT"/T4-R25-*.tsv "$OUTROOT"/T4-R50-*.tsv; do
	[[ -f $f ]] || continue
	echo "===== $f ====="
	python3 analysis/m6c_stats.py "$f" | tee "$OUTROOT/$(basename "$f" .tsv).stats.txt"
done

say "m6c1 overhead XONG"
