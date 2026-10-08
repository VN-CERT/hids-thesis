#!/usr/bin/env bash
# m5.sh — overhead collector (C0..C3, T1..T4). Can root, cay git sach.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

COLLECT=./bin/hids-collect
RECSTAT=./bin/rec-stat
SYSINJ=./bin/sysinj
DATE=$(date +%Y%m%d)
OUTROOT="${M5_OUTROOT:-validation/m5-${DATE}-m6a}"
CONTAINERS_RESTORE="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
STRESS_CPU_METHOD=(--cpu-method int64)
RUNS=${M5_RUNS:-5}
REST=${M5_REST:-10}
N_SYSINJ=${M5_N_SYSINJ:-10000000}
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
M5PY=./analysis/m5_summarize.py
M5_PYTHON=(env PYTHONNOUSERSITE=1 /usr/bin/python3)

write_m5_summary() {
	[[ -d $OUTROOT ]] || return 0
	[[ -f $M5PY ]] || return 0
	"${M5_PYTHON[@]}" "$M5PY" "$OUTROOT" >"$OUTROOT/summary.csv" 2>/dev/null || true
}

die() { echo "m5: $*" >&2; exit 1; }

require_clean_git() {
	[[ ${M5_SKIP_GIT_CHECK:-} == 1 ]] && return 0
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		path="${path%/}"
		if [[ $path == out/* || $path == validation/* || $path == reports/* || $path == internal/syscallbpf/* ]]; then
			continue
		fi
		die "cay git khong sach: $st $path"
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

require_from_m6a() {
	git rev-parse m6a >/dev/null 2>&1 || die "khong co tag m6a"
	git merge-base --is-ancestor m6a HEAD || die "HEAD khong phai tu tag m6a tro di (can checkout/commit sau m6a)"
}

restore_production_containers() {
	[[ -f $CONTAINERS_RESTORE ]] || {
		echo "m5: khong co $CONTAINERS_RESTORE, bo qua docker start" >&2
		return 0
	}
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker start "$n" >/dev/null 2>&1 || echo "m5: docker start that bai: $n" >&2
	done <"$CONTAINERS_RESTORE"
}

cgroup_path_of_pid() {
	local pid=$1 cg
	cg=$(awk -F: '$1=="0" {print $3}' "/proc/$pid/cgroup")
	echo "/sys/fs/cgroup${cg}"
}

scope_main_pid() {
	local u=$1 cg pid
	[[ $u != *.scope ]] && u="${u}.scope"
	cg=$(systemctl show "$u" -p ControlGroup --value 2>/dev/null) || return 1
	pid=$(head -1 "/sys/fs/cgroup${cg}/cgroup.procs" 2>/dev/null)
	[[ -n $pid ]] && echo "$pid"
}

wait_pid_gone() {
	local pid=$1 i
	for ((i = 0; i < 600000; i++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	die "pid $pid khong ket thuc"
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
	[[ -f $1 ]] || { echo 0; return 0; }
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
	[[ -f $dir/result.txt ]] && return 0
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
		systemd-run --scope --unit="hids-m5-coll-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$cgroup" -duration 3600s -out "$dir/collect.bin" \
			>"$dir/collect-scope.log" 2>"$dir/collect.log" &
		coll_pid=$!
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-coll-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 3600s -out "$dir/collect.bin" \
			>"$dir/collect-scope.log" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond $cond";;
	esac

	if [[ $cond == C3 ]]; then
		stress_cpus=$(stress_cpus_complement 12)
		stress-ng --cpu 8 "${STRESS_CPU_METHOD[@]}" --taskset "$stress_cpus" --timeout 3600 >/dev/null 2>&1 &
		stress_pids+=($!)
	fi

	sleep 1
	t0=$(date +%s%N)
	printf '.\n' >&3
	wait_pid_gone "$load_pid"
	t1=$(date +%s%N)
	exec 3>&-
	rm -f "$fifo"

	ns_per=$(awk -v dt="$((t1 - t0))" -v n="$N_SYSINJ" 'BEGIN{printf "%.2f", dt/n}')

	local coll_usec=0 recs=0 drops=0 coll_cg=""
	if [[ $cond != C0 ]]; then
		[[ -n ${coll_pid:-} ]] && kill -TERM "$coll_pid" 2>/dev/null || true
		[[ -n ${coll_pid:-} ]] && wait_pid_gone "$coll_pid"
		sleep 1
		coll_cg=$(cgroup_path_of_pid "$(scope_main_pid "hids-m5-coll-${cond}-${run}-$$" 2>/dev/null || echo 0)" 2>/dev/null || true)
		[[ -n ${coll_cg:-} && -d $coll_cg ]] && coll_usec=$(scope_usage_usec "$coll_cg")
		recs=$(awk '/ban ghi doc duoc/{print $4; exit}' "$dir/collect.log" 2>/dev/null)
		drops=$(awk '/ban ghi doc duoc/{for(i=1;i<=NF;i++) if($i=="mat:") print $(i+1); exit}' "$dir/collect.log" 2>/dev/null)
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done

	cat >"$dir/result.txt" <<EOF
metric=ns_per_syscall
value=$ns_per
collector_user_usec=$coll_usec
records=$recs
drops=$drops
EOF
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
	echo "T1 $cond run$run: ${ns_per} ns/syscall"
}

t2_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T2/${cond}/run${run}"
	[[ -f $dir/result.txt ]] && return 0
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
		systemd-run --scope --unit="hids-m5-t2c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$cgroup" -duration 600s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t2c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t2c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 600s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t2c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12)
		stress-ng --cpu 8 "${STRESS_CPU_METHOD[@]}" --taskset "$stress_cpus" --timeout 600 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	wait_pid_gone "$pid"
	out=$(grep -E 'usecs/op' "$dir/bench.log" | tail -1 | awk '{print $1}')
	if [[ -z $out ]]; then
		out=$(grep -i 'Average:' "$dir/bench.log" | tail -1 | awk '{print $2}')
	fi
	if [[ -z $out ]]; then
		out=$(awk '/Total time:/{t=$(NF-1)} END{if(t>0) print t*1e6/1000000}' "$dir/bench.log")
	fi
	[[ -n $out ]] || die "T2: khong parse bench.log $dir"
	local coll_usec=0 recs=0 drops=0
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait_pid_gone "$coll_pid"
		sleep 1
		recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
		drops=$(collector_drops "$dir/collect.log")
	fi
	for p in "${stress_pids[@]:-}"; do kill "$p" 2>/dev/null || true; done
	echo "metric=us_per_iter" >"$dir/result.txt"
	echo "value=$out" >>"$dir/result.txt"
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
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
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || die "pgtest khong ready sau 90s"
	sleep 2
	for i in $(seq 1 5); do
		if docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1; then
			return 0
		fi
		sleep 3
	done
	die "pgbench -i that bai trong pgtest"
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
	[[ -f $dir/result.txt ]] && return 0
	mkdir -p "$dir"
	local cgroup coll_pid stress_pids=() stress_cpus
	cgroup=$(docker_cgroup pgtest)
	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-t3c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$cgroup" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t3c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t3c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t3c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12 13 14 15 16 17 18 19)
		stress-ng --cpu 8 "${STRESS_CPU_METHOD[@]}" --taskset "$stress_cpus" --timeout 120 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres \
		>"$dir/pgbench.log" 2>/dev/null || true
	local tps lat
	tps=$(awk '/^tps =/{print $3; exit}' "$dir/pgbench.log")
	lat=$(awk '/latency average =/{print $4; exit}' "$dir/pgbench.log")
	local recs=0 drops=0
	if [[ $cond != C0 ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait_pid_gone "$coll_pid"
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
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
	echo "T3 $cond run$run: tps=$tps"
}

t4_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/${cond}/run${run}"
	[[ -f $dir/result.txt ]] && return 0
	mkdir -p "$dir"
	local cgroup coll_pid stress_pids=() stress_cpus
	cgroup=$(docker_cgroup m5-nginx)
	case $cond in
	C0) ;;
	C1|C3)
		systemd-run --scope --unit="hids-m5-t4c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$cgroup" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t4c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5-t4c-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5-t4c-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	esac
	[[ $cond == C3 ]] && {
		stress_cpus=$(stress_cpus_complement 12 13 14 15 16 17 18 19)
		stress-ng --cpu 8 "${STRESS_CPU_METHOD[@]}" --taskset "$stress_cpus" --timeout 120 >/dev/null 2>&1 &
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
		wait_pid_gone "$coll_pid"
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
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
	echo "T4 $cond run$run: rps=$rps"
}

bpf_kernel_cost() {
	local dir="$OUTROOT/bpf-kernel-T3-C1"
	mkdir -p "$dir"
	if [[ -f $OUTROOT/bpf-kernel-cost.txt ]]; then
		cat "$OUTROOT/bpf-kernel-cost.txt"
		return 0
	fi
	sysctl -w kernel.bpf_stats_enabled=1 >/dev/null
	t3_run C1 99
	rm -rf "$OUTROOT/T3/C1/run99"
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

m5_progress() {
	local msg=$1
	local st="${M5_STATUS_FILE:-out/jobs/m5.status}"
	mkdir -p "$(dirname "$st")"
	echo "updated=$(date -Iseconds) $msg" >>"$st"
}

main() {
	[[ $EUID -eq 0 ]] || die "can root"
	if [[ -n ${M5C_REGRESS_HOOK:-} && -z ${HIDS_COLLECT_EXTRA:-} ]]; then
		export HIDS_COLLECT_EXTRA="-sys-enter-hook ${M5C_REGRESS_HOOK}"
	fi
	trap 'hids_print_df_at_job_end; write_m5_summary; restore_production_containers' EXIT
	hids_require_disk_for_long_job
	if [[ -n ${M5_ONLY_T1_COND:-} ]]; then
		require_clean_git
		require_from_m6a
		for f in "$COLLECT" "$RECSTAT" "$SYSINJ"; do
			[[ -x $f ]] || die "thieu $f (make build)"
		done
		mkdir -p "$OUTROOT" out "$DECOY_CG"
		local run
		for ((run = 1; run <= RUNS; run++)); do
			t1_run "$M5_ONLY_T1_COND" "$run"
		done
		write_m5_summary
		exit 0
	fi
	require_clean_git
	require_from_m6a
	for f in "$COLLECT" "$RECSTAT" "$SYSINJ"; do
		[[ -x $f ]] || die "thieu $f (make build)"
	done
	command -v docker systemd-run stress-ng perf wrk >/dev/null || {
		apt-get install -y wrk >/dev/null 2>&1 || die "can wrk"
	}
	mkdir -p "$OUTROOT" out
	mkdir -p "$DECOY_CG"

	cp -f "$CONTAINERS_RESTORE" "$OUTROOT/containers-restore.txt" 2>/dev/null || true
	docker rm -f pgtest m5-nginx 2>/dev/null || true

	setup_pg
	setup_nginx

	local cond run t total=0 done=0
	total=$((4 * 4 * RUNS))
	m5_progress "status=running outroot=$OUTROOT total_runs=$total done=0"
	for t in T1 T2 T3 T4; do
		[[ ${M5C_REGRESS_MODE:-} == step2 && $t == T3 ]] && continue
		for cond in C0 C1 C2 C3; do
			[[ ${M5D_MODE:-} == 1 && $cond == C3 ]] && continue
			[[ ${M5C_REGRESS_MODE:-} == step2 && $t == T4 && $cond != C1 ]] && continue
			[[ ${M5C_REGRESS_MODE:-} == step2 && $cond == C3 ]] && continue
			for ((run = 1; run <= RUNS; run++)); do
				case $t in
				T1) t1_run "$cond" "$run" ;;
				T2) t2_run "$cond" "$run" ;;
				T3) t3_run "$cond" "$run" ;;
				T4) t4_run "$cond" "$run" ;;
				esac
				done=$((done + 1))
				write_m5_summary
				m5_progress "status=running $t $cond run$run/$RUNS progress=$done/$total"
				sleep "$REST"
			done
		done
		write_m5_summary
		m5_progress "status=running finished_load=$t"
	done

	bpf_kernel_cost | tee "$OUTROOT/bpf-kernel-cost.txt"

	docker rm -f pgtest m5-nginx 2>/dev/null || true
	restore_production_containers

	write_m5_summary
	m5_progress "status=done outroot=$OUTROOT"
	echo "m5 xong: $OUTROOT (summary: $OUTROOT/summary.csv)"
}

main "$@"
