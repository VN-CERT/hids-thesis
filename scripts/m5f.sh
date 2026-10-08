#!/usr/bin/env bash
# M5f: G7 verify, T4 kịch trần (wrk2), T3-R/T4-R + m5f_parse.py
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" PATH="/usr/local/go/bin:/root/go/bin:/usr/local/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

DATE=$(date +%Y%m%d)
OUTROOT="${M5F_OUT:-validation/m5f-${DATE}}"
LOG="out/jobs/m5f.log"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
COLLECT=./bin/hids-collect
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
RUNS_SAT=${M5F_SAT_RUNS:-7}
RUNS_FIXED=${M5F_FIXED_RUNS:-3}
REST=${M5F_REST:-10}
PARSE_TSV="$OUTROOT/m5f_parse.tsv"
M5F_PARSE=./analysis/m5f_parse.py

die() { echo "m5f: $*" >&2; exit 1; }

stop_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker stop "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}
start_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker start "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}
trap 'start_containers; hids_print_df_at_job_end' EXIT

require_clean_git() {
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		path="${path%/}"
		[[ $path == out/* || $path == validation/* || $path == reports/* ]] && continue
		die "cay git khong sach: $st $path"
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

docker_cgroup() { cgroup_path_of_pid "$(docker inspect -f '{{.State.Pid}}' "$1")"; }
cgroup_path_of_pid() {
	local cg
	cg=$(awk -F: '$1=="0" {print $3}' "/proc/$1/cgroup")
	echo "/sys/fs/cgroup${cg}"
}
scope_main_pid() {
	local u=$1 cg pid
	[[ $u != *.scope ]] && u="${u}.scope"
	cg=$(systemctl show "$u" -p ControlGroup --value 2>/dev/null) || return 1
	pid=$(head -1 "/sys/fs/cgroup${cg}/cgroup.procs" 2>/dev/null)
	[[ -n $pid ]] && echo "$pid"
}
wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong READY: $log"
}
wait_pid_gone() {
	local pid=$1 i
	for ((i = 0; i < 6000; i++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	die "pid $pid khong ket thuc"
}
scope_usage_usec() {
	local cg=$1
	[[ -f $cg/cpu.stat ]] && awk '/^usage_usec/{print $2}' "$cg/cpu.stat" || echo 0
}

setup_pg() {
	docker rm -f pgtest 2>/dev/null || true
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || die "pgtest khong ready"
	for i in $(seq 1 5); do
		docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 && return 0
		sleep 3
	done
	die "pgbench -i that bai"
}

setup_nginx() {
	docker rm -f m5-nginx 2>/dev/null || true
	local tmpd
	tmpd=$(mktemp -d)
	dd if=/dev/urandom of="$tmpd/f.bin" bs=4096 count=1 2>/dev/null
	chmod 755 "$tmpd" "$tmpd/f.bin"
	docker run -d --name m5-nginx --cpuset-cpus 12-15 \
		-v "$tmpd:/usr/share/nginx/html:ro" -p 18080:80 nginx:alpine >/dev/null
	sleep 2
}

step2_verify() {
	mkdir -p "$OUTROOT/step2"
	echo "=== M5f step2 G7a ===" | tee "$OUTROOT/step2/g7a.log"
	G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh a 1000000 2>&1 | tee -a "$OUTROOT/step2/g7a.log"
	echo "=== M5f step2 G7-cap nproc=2 60s ===" | tee -a "$OUTROOT/step2/g7cap.log"
	G7_CAP_OUT="$OUTROOT/step2/g7-cap" G7_CAP_DURATION=60 bash scripts/m5f_g7cap2.sh 2>&1 | tee -a "$OUTROOT/step2/g7cap.log"
}

c0_rps_t4() {
	python3 - "$OUTROOT" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1]) / "T4" / "C0"
rates = []
for d in sorted(root.glob("run*")):
    p = d / "wrk2.txt"
    if not p.exists():
        continue
    m = re.search(r"Requests/sec:\s*([\d.]+)", p.read_text())
    if m:
        rates.append(float(m.group(1)))
if not rates:
    raise SystemExit("khong co RPS T4 C0")
print(sum(rates) / len(rates))
PY
}

c0_tps_t3() {
	python3 - "$OUTROOT" <<'PY'
import subprocess, sys
from pathlib import Path
root = Path(sys.argv[1]) / "T3-C0-sat"
files = list(root.glob("pglog.*"))
if not files:
    raise SystemExit("thieu pglog T3-C0-sat")
out = subprocess.check_output(["python3", "analysis/m5f_parse.py", "pgbench"] + [str(f) for f in files], text=True)
print(float(out.strip().split("\t")[2]))
PY
}

frac_target() {
	python3 - "$1" "$2" <<'PY'
import sys
b, p = float(sys.argv[1]), float(sys.argv[2])
print(b * p / 100.0)
PY
}

record_parse() {
	local label=$1
	shift
	local line
	line=$(python3 "$M5F_PARSE" "$@")
	echo "$label	$line" >>"$PARSE_TSV"
	echo "$line"
	if echo "$line" | awk -F'\t' '$(NF)=="NGHI_NGO" || $(NF-1)=="LECH" {e=1} END{exit e?0:1}'; then
		return 1
	fi
	return 0
}

t3_c0_sat() {
	local dir="$OUTROOT/T3-C0-sat"
	mkdir -p "$dir"
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	local cg
	cg=$(docker_cgroup pgtest)
	echo "cgroup_cpu_usec=$(scope_usage_usec "$cg")" >"$dir/meta.txt"
}

t4_sat_load() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/${cond}/run${run}"
	mkdir -p "$dir"
	local cgroup coll_pid="" usec0 usec1
	cgroup=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cgroup")
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="hids-m5f-t4-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cgroup" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t4-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5f-t4-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t4-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond $cond";;
	esac
	taskset -c 16-19 wrk2 -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cgroup")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
}

t3r_load() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
	mkdir -p "$dir"
	local rate base coll_pid="" usec0 usec1 cg
	base=$(c0_tps_t3)
	rate=$(frac_target "$base" "$pct")
	cg=$(docker_cgroup pgtest)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="hids-m5f-t3r-${pct}-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cg" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t3r-${pct}-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5f-t3r-${pct}-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t3r-${pct}-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond";;
	esac
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -R $rate -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cg")
	echo "target_tps=$rate cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
}

t3r_run() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
	local rate base label="T3-R${pct} ${cond} run${run}"
	base=$(c0_tps_t3)
	rate=$(frac_target "$base" "$pct")
	t3r_load "$pct" "$cond" "$run"
	if ! record_parse "$label" pgbench --target "$rate" "$dir"/pglog.*; then
		echo "m5f: retry $label" >&2
		t3r_load "$pct" "$cond" "$run"
		record_parse "$label" pgbench --target "$rate" "$dir"/pglog.* || \
			echo "m5f: $label van NGHI_NGO/LECH" >>"$OUTROOT/parse-warnings.txt"
	fi
}

t4r_load() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T4-R${pct}/${cond}/run${run}"
	mkdir -p "$dir"
	local rate base coll_pid="" usec0 usec1 cg rate_int
	base=$(c0_rps_t4)
	rate=$(frac_target "$base" "$pct")
	rate_int=$(python3 -c "import math; print(max(1,int(math.floor($rate))))")
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="hids-m5f-t4r-${pct}-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cg" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t4r-${pct}-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5f-t4r-${pct}-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t4r-${pct}-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond";;
	esac
	taskset -c 16-19 wrk2 -t4 -c64 -d60s -R "$rate_int" --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cg")
	echo "target_rps=$rate_int cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
}

t4r_run() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T4-R${pct}/${cond}/run${run}"
	local rate_int label="T4-R${pct} ${cond} run${run}"
	t4r_load "$pct" "$cond" "$run"
	rate_int=$(awk -F= '/target_rps/{print $2}' "$dir/meta.txt")
	if ! record_parse "$label" wrk2 --target "$rate_int" "$dir/wrk2.txt"; then
		echo "m5f: retry $label" >&2
		t4r_load "$pct" "$cond" "$run"
		rate_int=$(awk -F= '/target_rps/{print $2}' "$dir/meta.txt")
		record_parse "$label" wrk2 --target "$rate_int" "$dir/wrk2.txt" || \
			echo "m5f: $label van NGHI_NGO/LECH" >>"$OUTROOT/parse-warnings.txt"
	fi
}

step6_benchmark() {
	command -v wrk2 docker systemd-run >/dev/null || die "thieu wrk2/docker"
	mkdir -p "$OUTROOT" out "$DECOY_CG"
	{
		echo -n "label	"
		python3 "$M5F_PARSE" --header
	} >"$PARSE_TSV"
	stop_containers
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	setup_pg
	setup_nginx
	t3_c0_sat
	local cond run pct
	for ((run = 1; run <= RUNS_SAT; run++)); do
		for cond in C0 C1 C2; do
			t4_sat_load "$cond" "$run"
			sleep "$REST"
		done
	done
	for pct in 25 50; do
		for ((run = 1; run <= RUNS_FIXED; run++)); do
			for cond in C0 C1 C2; do
				t3r_run "$pct" "$cond" "$run"
				sleep "$REST"
			done
		done
	done
	for pct in 25 50; do
		for ((run = 1; run <= RUNS_FIXED; run++)); do
			for cond in C0 C1 C2; do
				t4r_run "$pct" "$cond" "$run"
				sleep "$REST"
			done
		done
	done
	docker rm -f pgtest m5-nginx 2>/dev/null || true
}

git_push_times() {
	: >"$OUTROOT/git-push-reflog.txt"
	local ref
	for ref in .git/refs/remotes/github/*; do
		[[ -e $ref ]] || continue
		refname=${ref#.git/}
		echo "=== $refname ===" >>"$OUTROOT/git-push-reflog.txt"
		git reflog show --date=iso "$refname" >>"$OUTROOT/git-push-reflog.txt" 2>&1 || true
	done
}

main() {
	mkdir -p out/jobs "$OUTROOT"
	exec >>"$LOG" 2>&1
	echo "=== m5f $(date -Iseconds) out=$OUTROOT ==="
	hids_require_disk_for_long_job
	make build
	[[ ${M5F_SKIP_STEP2:-} != 1 ]] && step2_verify
	[[ ${M5F_ONLY_STEP2:-} == 1 ]] && exit 0
	require_clean_git
	step6_benchmark
	git_push_times
	echo "=== m5f xong $OUTROOT ==="
}

main "$@"
