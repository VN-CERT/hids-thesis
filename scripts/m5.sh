#!/usr/bin/env bash
# m5.sh — overhead collector (C0..C3, T1..T4). Can root, cay git sach.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
RECSTAT=./bin/rec-stat
SYSINJ=./bin/sysinj
DATE=$(date +%Y%m%d)
OUTROOT="validation/m5-${DATE}"
RUNS=5
REST=10
N_SYSINJ=10000000
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
M5PY=./analysis/m5_summarize.py

die() { echo "m5: $*" >&2; exit 1; }

require_clean_git() {
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		path="${path%/}"
		[[ $path == out/* || $path == validation/m5* || $path == validation/m5-* ]] && continue
		die "cay git khong sach: $st $path"
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

cgroup_path_of_pid() {
	local pid=$1 cg
	cg=$(awk -F: '$1=="0" {print $3}' "/proc/$pid/cgroup")
	echo "/sys/fs/cgroup${cg}"
}

scope_main_pid() {
	local u=$1
	[[ $u != *.scope ]] && u="${u}.scope"
	systemctl show "$u" -p MainPID --value 2>/dev/null
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong READY: $log"
}

recstat_count() {
	"$RECSTAT" "$1" 2>/dev/null | awk '/tong so ban ghi trong file/{print $NF; exit}'
}

collector_drops() {
	awk '/mat_tong=/{for(i=1;i<=NF;i++) if($i~/^mat_tong=/){split($i,a,"="); print a[2]}}' "$1" 2>/dev/null | tail -1
}

scope_usage_usec() {
	local cg=$1
	[[ -f $cg/cpu.stat ]] && awk '/^usage_usec/{print $2}' "$cg/cpu.stat" || echo 0
}

stress_cpus_complement() {
	# 8 CPU khong thuoc tap load (danh sach truyen vao)
	local -a used=("$@")
	local -a free=()
	local c
	for c in $(seq 0 23); do
		local skip=0 u
		for u in "${used[@]}"; do [[ $c -eq $u ]] && skip=1; done
		[[ $skip -eq 0 ]] && free+=("$c")
	done
	(IFS=,; echo "${free[*]:0:8}")
}

run_sysinj_scope() {
	local unit=$1
	local fifo=$2
	local log=$3
	systemd-run --scope --unit="$unit" --slice=system.slice \
		taskset -c 12 "$SYSINJ" -n "$N_SYSINJ" <"$fifo" >"$log" 2>&1 &
	sleep 0.8
	local pid
	pid=$(scope_main_pid "$unit")
	[[ -n $pid && $pid != 0 ]] || die "khong lay MainPID $unit"
	echo "$pid"
}

t1_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T1/${cond}/run${run}"
	mkdir -p "$dir"
	local fifo unit load_pid cgroup coll_pid coll_log bin stress_pids=() stress_cpus
	fifo=$(mktemp -u)
	mkfifo "$fifo"
	exec 3<>"$fifo"
	unit="hids-m5-t1-${cond}-${run}-$$"
	load_pid=$(run_sysinj_scope "$unit" "$fifo" "$dir/sysinj.log")
	cgroup=$(cgroup_path_of_pid "$load_pid")
	echo "cgroup_tai=$cgroup" >"$dir/meta.txt"

	local t0 t1 ns_per
	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-coll-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration 3600s -out "$dir/collect.bin" \
			>"$dir/collect-scope.log" 2>"$dir/collect.log" &
		coll_pid=$!
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-coll-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 3600s -out "$dir/collect.bin" \
			>"$dir/collect-scope.log" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond $cond";;
	esac

	if [[ $cond == C3 ]]; then
		stress_cpus=$(stress_cpus_complement 12)
		stress-ng --cpu 8 --taskset "$stress_cpus" --timeout 3600 >/dev/null 2>&1 &
		stress_pids+=($!)
	fi

	sleep 1
	t0=$(date +%s%N)
	printf '.\n' >&3
	wait "$load_pid" || true
	t1=$(date +%s%N)
	exec 3>&-
	rm -f "$fifo"

	ns_per=$(awk -v dt="$((t1 - t0))" -v n="$N_SYSINJ" 'BEGIN{printf "%.2f", dt/n}')

	local coll_usec=0 recs=0 drops=0 coll_cg=""
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait "$coll_pid" 2>/dev/null || true
		sleep 2
		coll_cg=$(cgroup_path_of_pid "$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$" 2>/dev/null || echo 0)")
		[[ -d $coll_cg ]] && coll_usec=$(scope_usage_usec "$coll_cg")
		[[ -f $dir/collect.bin ]] && recs=$(recstat_count "$dir/collect.bin")
		drops=$(collector_drops "$dir/collect.log")
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done

	cat >"$dir/result.txt" <<EOF
metric=ns_per_syscall
value=$ns_per
collector_user_usec=$coll_usec
records=$recs
drops=$drops
EOF
	echo "T1 $cond run$run: ${ns_per} ns/syscall"
}

t2_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T2/${cond}/run${run}"
	mkdir -p "$dir"
	local unit pid cgroup coll_pid stress_pids=() stress_cpus out
	unit="hids-m5-t2-${cond}-${run}-$$"
	systemd-run --scope --unit="$unit" --slice=system.slice \
		bash -c 'exec taskset -c 12 perf bench sched pipe -l 1000000' \
		>"$dir/bench.log" 2>&1 &
	sleep 0.8
	pid=$(scope_main_pid "$unit")
	cgroup=$(cgroup_path_of_pid "$pid")

	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-t2c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration 600s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t2c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t2c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 600s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t2c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12)
		stress-ng --cpu 8 --taskset "$stress_cpus" --timeout 600 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	wait "$pid" 2>/dev/null || true
	out=$(grep -i 'Average:' "$dir/bench.log" | tail -1 | awk '{print $2}')
	[[ -n $out ]] || out=$(awk '/Total time:/{t=$3} END{if(t>0) print t*1e6/1000000}' "$dir/bench.log")
	local coll_usec=0 recs=0 drops=0
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait "$coll_pid" 2>/dev/null || true
		sleep 1
		recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
		drops=$(collector_drops "$dir/collect.log")
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
	echo "metric=us_per_iter" >"$dir/result.txt"
	echo "value=$out" >>"$dir/result.txt"
	echo "T2 $cond run$run: ${out} us/iter"
}

docker_cgroup() {
	local name=$1 pid
	pid=$(docker inspect -f '{{.State.Pid}}' "$name")
	cgroup_path_of_pid "$pid"
}

setup_pg() {
	docker rm -f pgtest 2>/dev/null || true
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
	for i in $(seq 1 60); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && break
		sleep 1
	done
	docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null
}

setup_nginx() {
	docker rm -f m5-nginx 2>/dev/null || true
	local tmpd
	tmpd=$(mktemp -d)
	dd if=/dev/urandom of="$tmpd/f.bin" bs=4096 count=1 2>/dev/null
	docker run -d --name m5-nginx --cpuset-cpus 12-15 \
		-v "$tmpd:/usr/share/nginx/html:ro" -p 18080:80 nginx:alpine >/dev/null
	sleep 2
}

t3_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T3/${cond}/run${run}"
	mkdir -p "$dir"
	local cgroup coll_pid stress_pids=() stress_cpus
	cgroup=$(docker_cgroup pgtest)
	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-t3c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t3c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t3c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t3c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12 13 14 15 16 17 18 19)
		stress-ng --cpu 8 --taskset "$stress_cpus" --timeout 120 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres \
		>"$dir/pgbench.log" 2>&1 || true
	local tps lat
	tps=$(awk '/including latency/{f=1} f && /tps =/{print $3; exit}' "$dir/pgbench.log")
	lat=$(awk '/latency average/{print $4; exit}' "$dir/pgbench.log")
	local recs=0 drops=0
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait "$coll_pid" 2>/dev/null || true
		recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
		drops=$(collector_drops "$dir/collect.log")
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
	cat >"$dir/result.txt" <<EOF
metric=tps
value=$tps
latency_ms=$lat
records=$recs
drops=$drops
EOF
	echo "T3 $cond run$run: tps=$tps"
}

t4_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/${cond}/run${run}"
	mkdir -p "$dir"
	local cgroup coll_pid stress_pids=() stress_cpus
	cgroup=$(docker_cgroup m5-nginx)
	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-t4c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t4c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t4c-${cond}-${run}-$$" --slice=system.slice \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t4c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12 13 14 15 16 17 18 19)
		stress-ng --cpu 8 --taskset "$stress_cpus" --timeout 120 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	taskset -c 16-19 wrk -t4 -c64 -d60s "http://127.0.0.1:18080/f.bin" >"$dir/wrk.log" 2>&1 || true
	local rps p50 p99
	rps=$(awk '/Requests\/sec:/{print $2}' "$dir/wrk.log")
	p50=$(awk '/Latency/{getline; print $2}' "$dir/wrk.log" | head -1)
	p99=$(awk '/99%/{print $2}' "$dir/wrk.log")
	local recs=0 drops=0
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait "$coll_pid" 2>/dev/null || true
		recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
		drops=$(collector_drops "$dir/collect.log")
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
	cat >"$dir/result.txt" <<EOF
metric=rps
value=$rps
p50_ms=$p50
p99_ms=$p99
records=$recs
drops=$drops
EOF
	echo "T4 $cond run$run: rps=$rps"
}

bpf_kernel_cost() {
	local dir="$OUTROOT/bpf-kernel-T3-C1"
	mkdir -p "$dir"
	sysctl -w kernel.bpf_stats_enabled=1 >/dev/null
	t3_run C1 99
	bpftool prog show -j >"$dir/progs.json" 2>/dev/null || echo '[]' >"$dir/progs.json"
	sysctl -w kernel.bpf_stats_enabled=0 >/dev/null
	python3 - "$dir" <<'PY'
import json, sys
from pathlib import Path
d = Path(sys.argv[1])
progs = json.loads(d.joinpath("progs.json").read_text())
rows = []
for p in progs:
    name = p.get("name", "")
    if not name.startswith("hids_"):
        continue
    rt = int(p.get("run_time_ns", 0))
    rc = int(p.get("run_cnt", 0))
    avg = rt / rc if rc else 0
    rows.append((name, avg, rc))
for name, avg, rc in sorted(rows):
    print(f"{name}\tavg_ns={avg:.1f}\trun_cnt={rc}")
PY
}

main() {
	[[ $EUID -eq 0 ]] || die "can root"
	require_clean_git
	for f in "$COLLECT" "$RECSTAT" "$SYSINJ"; do
		[[ -x $f ]] || die "thieu $f (make build)"
	done
	command -v docker systemd-run stress-ng perf wrk >/dev/null || {
		apt-get install -y wrk >/dev/null 2>&1 || die "can wrk"
	}
	mkdir -p "$OUTROOT" out
	mkdir -p "$DECOY_CG"

	docker ps --format '{{.Names}}' 2>/dev/null | grep -vE '^(pgtest|m5-nginx)$' >"$OUTROOT/docker-stopped.txt" || true
	while read -r n; do
		[[ -n $n ]] && docker stop "$n" >/dev/null 2>&1 || true
	done <"$OUTROOT/docker-stopped.txt"

	setup_pg
	setup_nginx

	local cond run t
	for t in T1 T2 T3 T4; do
		for cond in C0 C1 C2 C3; do
			for ((run = 1; run <= RUNS; run++)); do
				case $t in
				T1) t1_run "$cond" "$run" ;;
				T2) t2_run "$cond" "$run" ;;
				T3) t3_run "$cond" "$run" ;;
				T4) t4_run "$cond" "$run" ;;
				esac
				sleep "$REST"
			done
		done
	done

	bpf_kernel_cost | tee "$OUTROOT/bpf-kernel-cost.txt"

	docker rm -f pgtest m5-nginx 2>/dev/null || true
	while read -r n; do
		[[ -n $n ]] && docker start "$n" >/dev/null 2>&1 || true
	done <"$OUTROOT/docker-stopped.txt"

	[[ -f $M5PY ]] && python3 "$M5PY" "$OUTROOT" >"$OUTROOT/summary.csv"
	echo "m5 xong: $OUTROOT"
}

main "$@"
