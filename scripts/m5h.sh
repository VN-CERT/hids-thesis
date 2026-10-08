#!/usr/bin/env bash
# M5h bước 3–4: overhead BPF r2 (T1/T3/T4 + tải cố định).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" PATH="/usr/local/bin:/usr/local/go/bin:/root/go/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

OUTROOT="${M5H_OUT:-validation/m5h-$(date +%Y%m%d)}"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj
M5F_PARSE=./analysis/m5f_parse.py
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
N_SYSINJ=${M5H_N_SYSINJ:-10000000}
REST=${M5H_REST:-10}
LOG=out/jobs/m5h-bench.log
PARSE_SAT="$OUTROOT/m5f_parse_sat.tsv"
PARSE_FIXED="$OUTROOT/m5f_parse.tsv"
C1_METRICS="$OUTROOT/c1_collect_metrics.tsv"
T1_CONDS=(C0 C1-tracepoint C1-fentry C2-tracepoint C2-fentry)
T4_CONDS=(C0 C1-tracepoint C1-fentry C2-tracepoint C2-fentry)
T3_CONDS=(C0 C1 C2)

die() { echo "m5h: $*" >&2; exit 1; }

meta_field() {
	local file=$1 key=$2
	grep -oE "${key}=[0-9]+" "$file" | head -1 | cut -d= -f2
}

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

m5h_cond_base() {
	case $1 in
	C0) echo C0 ;;
	C1|C1-tracepoint|C1-fentry) echo C1 ;;
	C2|C2-tracepoint|C2-fentry) echo C2 ;;
	*) die "cond $1" ;;
	esac
}
m5h_cond_hook() {
	case $1 in
	C0|C1|C2) echo tracepoint ;;
	C1-tracepoint|C2-tracepoint) echo tracepoint ;;
	C1-fentry|C2-fentry) echo fentry ;;
	*) die "hook $1" ;;
	esac
}
collect_hook_args() {
	local hook=$1
	[[ $hook == tracepoint ]] && return 0
	printf '%s\n' -sys-enter-hook "$hook"
}

append_c1_metrics() {
	local load=$1 cond=$2 run=$3 log=$4
	local base recs mat secs rps
	base=$(m5h_cond_base "$cond")
	[[ $base == C1 ]] || return 0
	recs=$(sed -n 's/.*ban ghi doc duoc: \([0-9]*\).*/\1/p' "$log" | tail -1)
	mat=$(sed -n 's/.*mat: \([0-9]*\).*/\1/p' "$log" | tail -1)
	secs=$(sed -n 's/.*thoi gian chay: \([0-9.]*\) s.*/\1/p' "$log" | tail -1)
	[[ -z $recs || -z $secs ]] && return 0
	rps=$(awk -v r="$recs" -v s="$secs" 'BEGIN{if(s>0) printf "%.2f", r/s; else print "0"}')
	echo -e "${load}\t${cond}\trun${run}\t${recs}\t${mat}\t${secs}\t${rps}" >>"$C1_METRICS"
}

start_collector() {
	local unit=$1 cgroup=$2 hook=$3 dir=$4
	local -a hook_args=()
	read -ra hook_args <<<"$(collect_hook_args "$hook" | xargs)" || true
	mkdir -p "$dir"
	case $(m5h_cond_base "$(basename "$(dirname "$dir")")" 2>/dev/null || echo C1) in
	esac
	local coll_pid=""
	local base=${5:-C1}
	if [[ $base == C0 ]]; then
		return 0
	fi
	local cg_target=$cgroup
	if [[ $base == C2 ]]; then
		mkdir -p "$DECOY_CG"
		cg_target=$DECOY_CG
	fi
	systemd-run --scope --unit="$unit" --slice=system.slice -- \
		"$COLLECT" "${hook_args[@]}" -cgroup "$cg_target" -duration 3600s -out "$dir/collect.bin" \
		2>"$dir/collect.log" &
	sleep 0.5
	coll_pid=$(scope_main_pid "$unit") || coll_pid=""
	wait_ready "$dir/collect.log"
	echo "$coll_pid"
}

run_sysinj_scope() {
	local unit=$1 fifo=$2 log=$3
	systemd-run --scope --unit="$unit" --slice=system.slice \
		taskset -c 12 "$SYSINJ" -n "$N_SYSINJ" <"$fifo" >"$log" 2>&1 &
	sleep 0.8
	local pid
	pid=$(scope_main_pid "$unit") || pid=""
	echo "$pid"
}

t1_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T1/${cond}/run${run}"
	if [[ -f $dir/result.txt ]]; then
		echo "T1 $cond run$run: (bo qua, da co ket qua)"
		return 2
	fi
	mkdir -p "$dir"
	local base hook fifo unit load_pid cgroup coll_pid="" coll_unit
	base=$(m5h_cond_base "$cond")
	hook=$(m5h_cond_hook "$cond")
	fifo=$(mktemp -u)
	mkfifo "$fifo"
	exec 3<>"$fifo"
	unit="hids-m5h-t1-${cond}-${run}-$$"
	load_pid=$(run_sysinj_scope "$unit" "$fifo" "$dir/sysinj.log")
	cgroup=$(cgroup_path_of_pid "$load_pid")
	coll_unit="hids-m5h-t1c-${cond}-${run}-$$"
	if [[ $base != C0 ]]; then
		local cg_target=$cgroup
		[[ $base == C2 ]] && cg_target=$DECOY_CG && mkdir -p "$DECOY_CG"
		local -a ha=()
		mapfile -t ha < <(collect_hook_args "$hook")
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" "${ha[@]}" -cgroup "$cg_target" -duration 3600s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid="" || coll_pid=""
		wait_ready "$dir/collect.log"
	fi
	sleep 1
	local t0 t1
	t0=$(date +%s%N)
	printf '.\n' >&3
	wait_pid_gone "$load_pid"
	t1=$(date +%s%N)
	exec 3>&-
	rm -f "$fifo"
	local ns_per
	ns_per=$(awk -v dt="$((t1 - t0))" -v n="$N_SYSINJ" 'BEGIN{printf "%.2f", dt/n}')
	if [[ $base != C0 && -n $coll_pid ]]; then
		kill -TERM "$coll_pid" 2>/dev/null || true
		wait_pid_gone "$coll_pid"
		append_c1_metrics T1 "$cond" "$run" "$dir/collect.log"
		hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	fi
	echo "metric=ns_per_syscall value=$ns_per" >"$dir/result.txt"
	echo "T1 $cond run$run: $ns_per ns/syscall"
}

t4_sat() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/${cond}/run${run}"
	if [[ -f $dir/wrk.txt && -f $dir/meta.txt ]]; then
		echo "T4-sat $cond run$run: (bo qua)"
		return 2
	fi
	echo "T4-sat $cond run$run: bat dau"
	mkdir -p "$dir"
	local base hook cgroup coll_pid="" coll_unit usec0 usec1
	base=$(m5h_cond_base "$cond")
	hook=$(m5h_cond_hook "$cond")
	cgroup=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cgroup")
	coll_unit="hids-m5h-t4-${cond}-${run}-$$"
	if [[ $base != C0 ]]; then
		local cg_target=$cgroup
		[[ $base == C2 ]] && cg_target=$DECOY_CG && mkdir -p "$DECOY_CG"
		local -a ha=()
		mapfile -t ha < <(collect_hook_args "$hook")
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" "${ha[@]}" -cgroup "$cg_target" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
	fi
	taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk.txt" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cgroup")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	[[ $base == C1 ]] && append_c1_metrics T4 "$cond" "$run" "$dir/collect.log"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	local line
	line=$(python3 "$M5F_PARSE" wrk2 "$dir/wrk.txt" 2>"$dir/parse.err") || line="PARSE_FAIL"
	echo "T4-sat ${cond} run${run}	$line" >>"$PARSE_SAT"
	local mat
	mat=$(sed -n 's/.*mat: \([0-9]*\).*/\1/p' "$dir/collect.log" 2>/dev/null | tail -1)
	[[ -n $mat && $mat != 0 ]] && echo "T4 $cond run$run mat=$mat" >>"$OUTROOT/t4_sat_loss.txt"
}

pg_maintain() {
	docker exec pgtest psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'VACUUM;' -c 'CHECKPOINT;'
}
setup_pg() {
	docker rm -f pgtest 2>/dev/null || true
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine \
		-c checkpoint_timeout=30min -c max_wal_size=8GB -c autovacuum=off >/dev/null
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || die "pgtest khong ready"
	for i in $(seq 1 5); do
		if docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >>"$OUTROOT/setup-pg-pgbench.log" 2>&1; then
			return 0
		fi
		sleep 3
	done
	die "pgbench -i that bai (xem $OUTROOT/setup-pg-pgbench.log)"
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

t3_sat() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T3/${cond}/run${run}"
	[[ -f $dir/meta.txt && -f $dir/pglog.1 ]] && return 0
	mkdir -p "$dir"
	pg_maintain
	local cg coll_pid="" usec0 usec1 coll_unit
	cg=$(docker_cgroup pgtest)
	usec0=$(scope_usage_usec "$cg")
	coll_unit="hids-m5h-t3-${cond}-${run}-$$"
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cg" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
		;;
	*) die "t3 cond";;
	esac
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cg")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	[[ $cond == C1 ]] && append_c1_metrics T3 "$cond" "$run" "$dir/collect.log"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	shopt -s nullglob
	local pgf=("$dir"/pglog.*)
	shopt -u nullglob
	line=$(python3 "$M5F_PARSE" pgbench "${pgf[@]}" 2>"$dir/parse.err") || line="PARSE_FAIL"
	echo "T3-sat ${cond} run${run}	$line" >>"$PARSE_SAT"
}

c0_tps_t3() {
	python3 - "$OUTROOT" <<'PY'
import subprocess, sys
from pathlib import Path
root = Path(sys.argv[1]) / "T3" / "C0"
rates = []
for d in sorted(root.glob("run*")):
    pg = list(d.glob("pglog.*"))
    if not pg:
        continue
    out = subprocess.check_output(["python3", "analysis/m5f_parse.py", "pgbench"] + [str(p) for p in pg], text=True)
    rates.append(float(out.strip().split("\t")[2]))
if not rates:
    raise SystemExit("khong co TPS T3 C0")
print(sum(rates)/len(rates))
PY
}
c0_rps_t4() {
	python3 - "$OUTROOT" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1]) / "T4" / "C0"
rates = []
for d in sorted(root.glob("run*")):
    p = d / "wrk.txt"
    if not p.exists():
        continue
    m = re.search(r"Requests/sec:\s*([\d.]+)", p.read_text())
    if m:
        rates.append(float(m.group(1)))
if not rates:
    raise SystemExit("khong co RPS T4 C0")
print(sum(rates)/len(rates))
PY
}
frac_target() {
	python3 - "$1" "$2" <<'PY'
import sys
print(float(sys.argv[1]) * float(sys.argv[2]) / 100.0)
PY
}

record_parse_fixed() {
	local label=$1
	shift
	local line
	line=$(python3 "$M5F_PARSE" "$@" 2>>"$OUTROOT/parse-errors.log") || line="PARSE_FAIL"
	echo "$label	$line" >>"$PARSE_FIXED"
}

t3r_run() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
	mkdir -p "$dir"
	pg_maintain
	local rate base coll_pid="" usec0 usec1 cg coll_unit
	base=$(c0_tps_t3)
	rate=$(frac_target "$base" "$pct")
	cg=$(docker_cgroup pgtest)
	usec0=$(scope_usage_usec "$cg")
	coll_unit="hids-m5h-t3r-${pct}-${cond}-${run}-$$"
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cg" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
		;;
	*) die "t3r";;
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
	[[ $cond == C1 ]] && append_c1_metrics "T3-R${pct}" "$cond" "$run" "$dir/collect.log"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	rate=$(meta_field "$dir/meta.txt" target_tps)
	shopt -s nullglob
	local pgf=("$dir"/pglog.*)
	shopt -u nullglob
	record_parse_fixed "T3-R${pct} ${cond} run${run}" pgbench --target "$rate" "${pgf[@]}"
}

t4r_run() {
	local pct=$1 cond=$2 run=$3 hook=${4:-tracepoint}
	local dir
	if [[ $cond == C2-fentry ]]; then
		dir="$OUTROOT/T4-R${pct}/C2-fentry/run${run}"
	else
		dir="$OUTROOT/T4-R${pct}/${cond}/run${run}"
	fi
	mkdir -p "$dir"
	local rate base coll_pid="" usec0 usec1 cg rate_int coll_unit
	base=$(c0_rps_t4)
	rate=$(frac_target "$base" "$pct")
	rate_int=$(python3 -c "import math; print(max(1,int(math.floor($rate))))")
	cg=$(docker_cgroup m5-nginx)
	usec0=$(scope_usage_usec "$cg")
	local base_c cond_label
	if [[ $cond == C2-fentry ]]; then
		base_c=C2
		cond_label=C2-fentry
	else
		base_c=$cond
		cond_label=$cond
	fi
	coll_unit="hids-m5h-t4r-${pct}-${cond_label}-${run}-$$"
	if [[ $base_c != C0 ]]; then
		local cg_target=$cg
		[[ $base_c == C2 ]] && cg_target=$DECOY_CG && mkdir -p "$DECOY_CG"
		local -a ha=()
		mapfile -t ha < <(collect_hook_args "$hook")
		systemd-run --scope --unit="$coll_unit" --slice=system.slice -- \
			"$COLLECT" "${ha[@]}" -cgroup "$cg_target" -duration 120s -out "$dir/collect.bin" \
			2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit") || coll_pid=""
		wait_ready "$dir/collect.log"
	fi
	taskset -c 16-19 /usr/local/bin/wrk2 -t4 -c64 -d60s -R "$rate_int" --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cg")
	echo "target_rps=$rate_int cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	[[ $base_c == C1 ]] && append_c1_metrics "T4-R${pct}" "$cond_label" "$run" "$dir/collect.log"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	rate_int=$(meta_field "$dir/meta.txt" target_rps)
	record_parse_fixed "T4-R${pct} ${cond_label} run${run}" wrk2 --target "$rate_int" "$dir/wrk2.txt"
}

main() {
	mkdir -p out/jobs "$OUTROOT" out "$DECOY_CG"
	exec >>"$LOG" 2>&1
	echo "=== m5h bench $(date -Iseconds) ==="
	hids_require_disk_for_long_job
	hids_require_clean_git || die "git khong sach"
	if [[ ${M5H_SKIP_BUILD:-} != 1 ]]; then
		make build
		git checkout HEAD -- internal/syscallbpf/sysenter_x86_bpfel.o internal/stealbpf/stealsnaprq_x86_bpfel.o 2>/dev/null || true
	fi
	command -v wrk wrk2 docker systemd-run >/dev/null || die "thieu cong cu"
	[[ -x /usr/local/bin/wrk2 ]] || die "thieu wrk2"

	[[ -s $C1_METRICS ]] || echo "load	cond	run	records	drops	secs	recs_per_s" >"$C1_METRICS"
	[[ -s $PARSE_FIXED ]] || echo "label	kieu	n	toc_do_per_s	lat_tb_ms	p50_ms	p99_ms	max_ms	lag_tb_ms	lag_p99_ms	loi	dat_muc	hop_ly" >"$PARSE_FIXED"
	[[ -s $PARSE_SAT ]] || echo "label	kieu	n	toc_do_per_s	(note: sat)" >"$PARSE_SAT"

	stop_containers
	local run cond pct
	for ((run = 1; run <= 5; run++)); do
		for cond in "${T1_CONDS[@]}"; do
			local tr=0
			t1_run "$cond" "$run" || tr=$?
			[[ $tr -eq 2 ]] || sleep "$REST"
		done
	done
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	setup_pg
	setup_nginx
	for ((run = 1; run <= 5; run++)); do
		for cond in "${T4_CONDS[@]}"; do
			local t4r=0
			t4_sat "$cond" "$run" || t4r=$?
			[[ $t4r -eq 2 ]] || sleep "$REST"
		done
	done
	for ((run = 1; run <= 3; run++)); do
		for cond in "${T3_CONDS[@]}"; do
			t3_sat "$cond" "$run"
			sleep "$REST"
		done
	done
	for pct in 25 50; do
		for ((run = 1; run <= 3; run++)); do
			for cond in C0 C1 C2; do
				t3r_run "$pct" "$cond" "$run"
				sleep "$REST"
			done
		done
	done
	for pct in 25 50; do
		for ((run = 1; run <= 3; run++)); do
			for cond in C0 C1 C2; do
				t4r_run "$pct" "$cond" "$run" tracepoint
				sleep "$REST"
			done
		done
	done
	for ((run = 1; run <= 3; run++)); do
		t4r_run 50 C2-fentry "$run" fentry
		sleep "$REST"
	done
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	echo "=== m5h bench xong ==="
}

main "$@"
