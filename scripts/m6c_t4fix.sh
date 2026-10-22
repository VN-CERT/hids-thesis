#!/usr/bin/env bash
# M6c sua T4: wrk2 ban nay bat buoc -R nen T4 kich tran dot dau hong (wrk2 in
# "Throughput MUST be specified"). Chay lai T4 kich tran bang -R rat cao
# (mo vong, khong dat duoc muc -> kich tran), sau do T4-R25/T4-R50 theo C0 moi.
# Them: chay lai T3 C1 run10 (dot dau collector khong READY vi kiem tra steal).
# Ghi de vao cung OUTROOT cua bo overhead; file hong cu giu nguyen trong run dir.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" PATH="/usr/local/go/bin:/root/go/bin:/usr/local/bin:${PATH}"
source scripts/hids_data_policy.sh

OUTROOT="${1:?can thu muc overhead}"
RUNS="${M6C_RUNS:-10}"
REST="${M6C_REST:-10}"
COLLECT=./bin/hids-collect
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
PARSE=./analysis/m5f_parse.py
STATUS="out/jobs/m6c-t4fix.status"
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
wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	say "LOI: collector khong READY: $log"; return 1
}
wait_pid_gone() {
	local pid=$1 i
	for ((i = 0; i < 600; i++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	return 1
}
COLL_PID=""
start_collector() {
	local cond=$1 cg=$2 dir=$3 tag=$4 extra=(-pmu on)
	[[ $cond == "C1n" ]] && extra=(-pmu off)
	mkdir -p "$DECOY_CG"
	local unit="hids-m6c-t4fix-$tag"
	systemd-run --scope --unit="$unit" --slice=system.slice -- \
		"$COLLECT" -cgroup "$cg" "${extra[@]}" -duration 180s -out "$dir/collect.bin" 2>"$dir/collect.log" &
	sleep 0.5
	COLL_PID=$(scope_main_pid "$unit") || COLL_PID=""
	wait_ready "$dir/collect.log"
}
stop_collector() {
	[[ -n $COLL_PID ]] && kill -INT "$COLL_PID" 2>/dev/null || true
	[[ -n $COLL_PID ]] && wait_pid_gone "$COLL_PID"
	COLL_PID=""
}
coll_stats() {
	local dir=$1
	python3 - "$dir" <<'PY'
import re, subprocess, sys, pathlib
d = pathlib.Path(sys.argv[1])
log = (d / "collect.log").read_text(errors="replace") if (d / "collect.log").exists() else ""
m = re.search(r"ban ghi doc duoc: (\d+) \| so lan dinh ghi: (\d+) \| mat: (\d+)", log)
recs = int(m.group(1)) if m else 0
drops = m.group(3) if m else "?"
rps = "?"
binp = d / "collect.bin"
if binp.exists() and recs:
    out = subprocess.run(["./bin/rec-stat", str(binp)], capture_output=True, text=True).stdout
    mm = re.search(r"ts_enter nho nhat / lon nhat: (\d+) / (\d+)", out)
    if mm:
        span = (int(mm.group(2)) - int(mm.group(1))) / 1e9
        if span > 0:
            rps = f"{recs / span:.1f}"
(d / "collect-stats.txt").write_text(f"ban_ghi={recs} ban_ghi_giay={rps} mat={drops}\n")
print(f"ban_ghi={recs} ban_ghi_giay={rps} mat={drops}")
PY
}
setup_pg() {
	docker rm -f pgtest >/dev/null 2>&1 || true
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || { say "LOI pgtest"; exit 1; }
	for i in $(seq 1 5); do
		docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 && return 0
		sleep 3
	done
	say "LOI pgbench -i"; exit 1
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

t4_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/$cond/run$run"
	mkdir -p "$dir"
	# Giu dau vet dot hong: doi ten file cu.
	[[ -f $dir/wrk2.txt ]] && mv "$dir/wrk2.txt" "$dir/wrk2-hong-dot1.txt"
	local cg usec0 usec1
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1|C1n) start_collector "$cond" "$cg" "$dir" "t4-$cond-$run" ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t4-C2-$run" ;;
	esac
	taskset -c 16-19 /usr/local/bin/wrk2 -t4 -c64 -d60s -R 10000000 --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	grep -oE "Requests/sec:\s*[0-9.]+" "$dir/wrk2.txt" | awk '{print $2}' >"$dir/value.txt" || true
	[[ $cond == "C1" || $cond == "C1n" ]] && coll_stats "$dir" || true
	say "T4 $cond run$run: $(cat "$dir/value.txt" 2>/dev/null) req/s"
}
t4r_run() {
	local pct=$1 cond=$2 run=$3 base=$4
	local dir="$OUTROOT/T4-R$pct/$cond/run$run"
	mkdir -p "$dir"
	[[ -f $dir/wrk2.txt ]] && mv "$dir/wrk2.txt" "$dir/wrk2-hong-dot1.txt"
	local rate cg usec0 usec1
	rate=$(python3 -c "import math; print(max(1,int($base * $pct / 100.0)))")
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1) start_collector C1 "$cg" "$dir" "t4r$pct-$cond-$run" ;;
	C2) start_collector C2 "$DECOY_CG" "$dir" "t4r$pct-$cond-$run" ;;
	esac
	taskset -c 16-19 /usr/local/bin/wrk2 -t4 -c64 -d60s -R "$rate" --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	stop_collector
	usec1=$(scope_usage_usec "$cg")
	echo "target_rps=$rate cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	python3 "$PARSE" wrk2 --target "$rate" "$dir/wrk2.txt" >"$dir/parse.txt" 2>&1 || true
	[[ $cond == "C1" ]] && coll_stats "$dir" || true
	say "T4-R$pct $cond run$run xong"
}
t3_c1_redo() {
	local dir="$OUTROOT/T3/C1/run10"
	[[ -f $dir/pglog.1 ]] && mv "$dir/pglog.1" "$dir/pglog-hong-dot1.txt"
	[[ -f $dir/collect.log ]] && mv "$dir/collect.log" "$dir/collect-hong-dot1.log"
	local cg usec0 usec1
	cg=$(docker_cgroup pgtest)
	docker exec -u postgres pgtest psql -U postgres -d postgres -c "VACUUM; CHECKPOINT;" >/dev/null 2>&1 || true
	usec0=$(scope_usage_usec "$cg")
	start_collector C1 "$cg" "$dir" "t3-C1-10b"
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
	coll_stats "$dir" || true
	say "T3 C1 run10 chay lai: $(cat "$dir/value.txt") tps"
}

say "t4fix bat dau"
if ((${#RUNNING_CONTAINERS[@]})); then
	docker stop "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
fi
setup_nginx
setup_pg

for ((run = 1; run <= RUNS; run++)); do
	for cond in C0 C1 C1n C2; do t4_sat_run "$cond" "$run"; sleep "$REST"; done
done
T4_C0=$(python3 - "$OUTROOT" <<'PY'
import glob, statistics, sys
vals = [float(open(p).read().strip()) for p in glob.glob(sys.argv[1] + "/T4/C0/run*/value.txt") if open(p).read().strip()]
print(statistics.median(vals))
PY
)
say "T4 C0 kich tran (trung vi dot sua) = $T4_C0"
for pct in 25 50; do
	for ((run = 1; run <= RUNS; run++)); do
		for cond in C0 C1 C2; do t4r_run "$pct" "$cond" "$run" "$T4_C0"; sleep "$REST"; done
	done
done
t3_c1_redo

say "tong hop TSV T4 + T3"
python3 - "$OUTROOT" <<'PY'
import csv, glob, pathlib, re, sys
root = pathlib.Path(sys.argv[1])

def w(name, rows):
    with open(root / name, "w", newline="") as f:
        wtr = csv.writer(f, delimiter="\t")
        wtr.writerow(["load", "cond", "run", "value"])
        wtr.writerows(rows)

for load in ("T4", "T3"):
    rows = []
    for vf in sorted(glob.glob(str(root / load / "*" / "run*" / "value.txt"))):
        p = pathlib.Path(vf)
        txt = p.read_text().strip()
        if txt:
            rows.append([load, p.parent.parent.name, p.parent.name.replace("run", ""), txt])
    w(f"{load}.tsv", rows)

for load in ("T4-R25", "T4-R50"):
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
for f in "$OUTROOT"/T4.tsv "$OUTROOT"/T3.tsv "$OUTROOT"/T4-R25-*.tsv "$OUTROOT"/T4-R50-*.tsv; do
	[[ -f $f ]] || continue
	echo "===== $f ====="
	python3 analysis/m6c_stats.py "$f" | tee "$OUTROOT/$(basename "$f" .tsv).stats.txt"
done
say "t4fix XONG"
