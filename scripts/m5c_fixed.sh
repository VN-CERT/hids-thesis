#!/usr/bin/env bash
# m5c_fixed.sh — buoc 3 M5c: T3-R/T4-R 25%/50% x C0/C1/C2, 3 run.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
RECSTAT=./bin/rec-stat
SYSINJ=./bin/sysinj
DATE=$(date +%Y%m%d)
OUTROOT="${M5C_FIXED_OUT:-validation/m5c-${DATE}/fixed}"
HOOK="${M5C_BEST_HOOK:-tracepoint}"
export HIDS_COLLECT_EXTRA="-sys-enter-hook ${HOOK}"
DIAG_SUMMARY="${M5C_DIAG_SUMMARY:-validation/m5c-${DATE}/diag/diag-summary.tsv}"
RUNS=${M5C_FIXED_RUNS:-3}
CONTAINERS_RESTORE="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
STRESS_CPU_METHOD=(--cpu-method int64)
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
		if [[ $path == out/* || $path == validation/* || $path == reports/* || $path == internal/syscallbpf/* || $path == scripts/m5c* ]]; then
			continue
		fi
		die "cay git khong sach: $st $path"
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

require_from_m6a() {
	git rev-parse m6a >/dev/null 2>&1 || die "khong co tag m6a"
	git merge-base --is-ancestor m6a HEAD || die "HEAD khong phai tu tag m6a tro di (can checkout/commit sau m6a)"
}

stop_production_containers() {
	[[ -f $CONTAINERS_RESTORE ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker stop "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS_RESTORE"
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
	awk '/mat_tong=/{for(i=1;i<=NF;i++) if($i~/^mat_tong=/){split($i,a,"="); print a[2]}}' "$1" 2>/dev/null | tail -1
}

scope_usage_usec() {
	local cg=$1
	[[ -f $cg/cpu.stat ]] && awk '/^usage_usec/{print $2}' "$cg/cpu.stat" || echo 0
}

m5_drop_collect_artifacts() {
	local dir=$1
	local bf="$dir/collect.bin"
	if [[ -f $bf ]]; then
		echo "bin_bytes=$(stat -c %s "$bf" 2>/dev/null || echo 0)" >>"$dir/result.txt"
		rm -f "$dir/collect.bin" "$dir/collect.bin.periodic" "$dir/collect.bin.stats"
	fi
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
		stress-ng --cpu 8 "${STRESS_CPU_METHOD[@]}" --taskset "$stress_cpus" --timeout 120 >/dev/null 2>&1 &
		stress_pids+=($!)
	}
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres \
		>"$dir/pgbench.log" 2>&1 || true
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

c0_metric_from_diag() {
	local load=$1
	[[ -f $DIAG_SUMMARY ]] || die "khong co $DIAG_SUMMARY"
	awk -F'\t' -v ld="$load" '$1==ld && $2=="C0" {print $3; exit}' "$DIAG_SUMMARY"
}

frac_c0_metric() {
	local load=$1 pct=$2
	local base
	base=$(c0_metric_from_diag "$load")
	python3 - "$base" "$pct" <<'PY'
import sys
b, p = float(sys.argv[1]), float(sys.argv[2])
print(b * p / 100.0)
PY
}

write_observer_cost() {
	python3 - "$OUTROOT" <<'PY'
import csv, sys
from pathlib import Path
root = Path(sys.argv[1])
rows = list(csv.DictReader((root / "summary.csv").open()))
c0 = next((r for r in rows if r["load"] == "T1" and r["condition"] == "C0"), None)
c1 = next((r for r in rows if r["load"] == "T1" and r["condition"] == "C1"), None)
if not c0 or not c1:
    raise SystemExit("thieu T1 C0/C1 trong summary.csv")
cost = float(c1["mean"]) - float(c0["mean"])
(root / "observer_cost_ns.txt").write_text(f"{cost}\n")
print(f"chi_phi_nguoi_quan_sat_ns={cost}")
PY
}

t3_fixed_run() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
	[[ -f $dir/result.txt ]] && return 0
	mkdir -p "$dir"
	local rate load_cg coll_cg coll_pid="" usec0 usec1 unit
	rate=$(frac_c0_metric T3 "$pct")
	[[ -n $rate && $rate != 0 ]] || die "khong tinh duoc ${pct}% TPS T3-C0"
	load_cg=$(docker_cgroup pgtest)
	usec0=$(scope_usage_usec "$load_cg")
	case $cond in
	C0) ;;
	C1)
		coll_cg="$load_cg"
		unit="hids-m5c-t3r${pct}-${cond}-${run}-$$"
		systemd-run --scope --unit="$unit" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$coll_cg" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$unit")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		unit="hids-m5c-t3r${pct}-${cond}-${run}-$$"
		systemd-run --scope --unit="$unit" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$unit")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond $cond";;
	esac
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -R "$rate" -U postgres -d postgres \
		>"$dir/pgbench.log" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$load_cg")
	local tps lat_avg lat_p99 recs drops
	tps=$(awk '/^tps =/{print $3; exit}' "$dir/pgbench.log")
	lat_avg=$(awk '/latency average =/{print $4; exit}' "$dir/pgbench.log")
	lat_p99=$(awk '/^  p99 =/{print $3; exit}' "$dir/pgbench.log")
	recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
	drops=$(collector_drops "$dir/collect.log")
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
	cat >"$dir/result.txt" <<EOF
metric=tps
value=$tps
latency_ms=$lat_avg
p99_ms=$lat_p99
cgroup_cpu_usec=$((usec1 - usec0))
target_tps=$rate
pct_c0=$pct
condition=$cond
records=$recs
drops=$drops
EOF
	echo "T3-R${pct} $cond run$run: tps=$tps lat=$lat_avg p99=$lat_p99"
}

t4_fixed_run() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T4-R${pct}/${cond}/run${run}"
	[[ -f $dir/result.txt ]] && return 0
	mkdir -p "$dir"
	local rate load_cg coll_pid="" usec0 usec1 hey unit
	rate=$(frac_c0_metric T4 "$pct")
	[[ -n $rate && $rate != 0 ]] || die "khong tinh duoc ${pct}% RPS T4-C0"
	hey="${HEY:-./bin/hey}"
	[[ -x $hey ]] || die "can bin/hey"
	load_cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$load_cg")
	case $cond in
	C0) ;;
	C1)
		unit="hids-m5c-t4r${pct}-${cond}-${run}-$$"
		systemd-run --scope --unit="$unit" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$load_cg" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$unit")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		unit="hids-m5c-t4r${pct}-${cond}-${run}-$$"
		systemd-run --scope --unit="$unit" --slice=system.slice -- \
			"$COLLECT" ${HIDS_COLLECT_EXTRA:-} -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$unit")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond $cond";;
	esac
	local workers=64
	local qps
	qps=$(python3 - "$rate" "$workers" <<'PY'
import sys
rate, w = float(sys.argv[1]), int(sys.argv[2])
print(max(1, int(rate / w)))
PY
)
	taskset -c 16-19 "$hey" -z 60s -q "$qps" -c "$workers" "http://127.0.0.1:18080/f.bin" >"$dir/hey.log" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$load_cg")
	local rps p50 p99 recs drops
	rps=$(awk '/Requests\/sec:/{print $2; exit}' "$dir/hey.log")
	p50=$(awk '/Latency Distribution/{f=1;next} f&&/50%/{print $2; exit}' "$dir/hey.log")
	p99=$(awk '/Latency Distribution/{f=1;next} f&&/99%/{print $2; exit}' "$dir/hey.log")
	recs=$(recstat_count "$dir/collect.bin" 2>/dev/null || echo 0)
	drops=$(collector_drops "$dir/collect.log")
	[[ $cond != C0 ]] && m5_drop_collect_artifacts "$dir"
	cat >"$dir/result.txt" <<EOF
metric=rps
value=$rps
latency_ms=$p50
p99_ms=$p99
cgroup_cpu_usec=$((usec1 - usec0))
target_rps=$rate
pct_c0=$pct
condition=$cond
tool=hey
records=$recs
drops=$drops
EOF
	echo "T4-R${pct} $cond run$run: rps=$rps p50=$p50 p99=$p99"
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
	trap 'write_m5_summary; restore_production_containers' EXIT
	require_clean_git
	for f in "$COLLECT" "$RECSTAT"; do
		[[ -x $f ]] || die "thieu $f (make build)"
	done
	[[ -x ${HEY:-./bin/hey} ]] || die "can bin/hey"
	[[ -f $DIAG_SUMMARY ]] || die "can $DIAG_SUMMARY (chay m5c_diag.sh truoc)"
	mkdir -p "$OUTROOT" out "$DECOY_CG"
	stop_production_containers
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	setup_pg
	setup_nginx
	local pct cond run
	for pct in 25 50; do
		for cond in C0 C1 C2; do
			for ((run = 1; run <= RUNS; run++)); do
				t3_fixed_run "$pct" "$cond" "$run"
				write_m5_summary
				sleep "$REST"
			done
		done
	done
	for pct in 25 50; do
		for cond in C0 C1 C2; do
			for ((run = 1; run <= RUNS; run++)); do
				t4_fixed_run "$pct" "$cond" "$run"
				write_m5_summary
				sleep "$REST"
			done
		done
	done
	M5_SKIP_GIT_CHECK=1 M5C_REGRESS_HOOK="$HOOK" M5C_REGRESS_MODE=step2 M5_OUTROOT="$OUTROOT/mini-t1" M5_RUNS=5 \
		bash scripts/m5.sh || true
	cp -f "$OUTROOT/mini-t1/summary.csv" "$OUTROOT/t1-t2-mini.csv" 2>/dev/null || true
	python3 - "$OUTROOT" <<'PY' | tee "$OUTROOT/observer_cost.txt" || true
import csv, sys
from pathlib import Path
p = Path(sys.argv[1]) / "mini-t1" / "summary.csv"
if not p.exists():
    sys.exit(0)
rows = list(csv.DictReader(p.open()))
c0 = next((r for r in rows if r["load"]=="T1" and r["condition"]=="C0"), None)
c1 = next((r for r in rows if r["load"]=="T1" and r["condition"]=="C1"), None)
if c0 and c1:
    cost = float(c1["mean"]) - float(c0["mean"])
    print(f"chi_phi_nguoi_quan_sat_ns={cost}")
    Path(sys.argv[1]).joinpath("observer_cost_ns.txt").write_text(f"{cost}\n")
PY
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	write_m5_summary
	echo "m5c_fixed xong: $OUTROOT hook=$HOOK"
}

main "$@"
