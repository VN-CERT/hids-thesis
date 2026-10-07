#!/usr/bin/env bash
# m5c_diag.sh — buoc 1 M5c: T3/T4, C0 + (a)(b)(f), 60s.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
DATE=$(date +%Y%m%d)
OUTROOT="${M5C_DIAG_OUT:-validation/m5c-${DATE}/diag}"
DURATION=60s
RESULT="$OUTROOT/diag-summary.tsv"
IDLE_BPF="$OUTROOT/bpf-idle.tsv"
CONTAINERS_RESTORE="${M5C_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
TMPFS_MNT="$OUTROOT/tmpfs-collect"
DECOY_CG="/sys/fs/cgroup/hids-m5c-idle"

die() { echo "m5c_diag: $*" >&2; exit 1; }

stop_production_containers() {
	[[ -f $CONTAINERS_RESTORE ]] || return 0
	: >"$OUTROOT/containers-stopped.txt"
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker stop "$n" >/dev/null 2>&1 && echo "$n" >>"$OUTROOT/containers-stopped.txt" || true
	done <"$CONTAINERS_RESTORE"
}

restore_production_containers() {
	[[ -f $CONTAINERS_RESTORE ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker start "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS_RESTORE"
}

cleanup() {
	umount "$TMPFS_MNT" 2>/dev/null || true
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	restore_production_containers
	sysctl -w kernel.bpf_stats_enabled=0 >/dev/null 2>&1 || true
}
trap cleanup EXIT

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

cgroup_usage_usec() {
	local cg=$1
	[[ -f $cg/cpu.stat ]] && awk '/^usage_usec/{print $2}' "$cg/cpu.stat" || echo 0
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong READY: $log"
}

irq_line_totals() {
	awk -v want="$1" '
		/^ *[A-Z0-9]+:/ {
			split($1, a, ":");
			if (a[1] != want) next;
			s = 0;
			for (i = 2; i <= NF; i++) s += $i;
			t += s;
		}
		END { print t+0 }
	' /proc/interrupts
}

irq_deltas() {
	local iwi0 cal0 res0 iwi1 cal1 res1
	iwi0=$(irq_line_totals IWI)
	cal0=$(irq_line_totals CAL)
	res0=$(irq_line_totals RES)
	echo "$iwi0 $cal0 $res0" >"$2.irq_before"
	sleep "$1" || true
	iwi1=$(irq_line_totals IWI)
	cal1=$(irq_line_totals CAL)
	res1=$(irq_line_totals RES)
	echo "$((iwi1-iwi0)) $((cal1-cal0)) $((res1-res0))"
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
	docker run -d --name m5-nginx --cpuset-cpus 12-15 \
		-v "$tmpd:/usr/share/nginx/html:ro" -p 18080:80 nginx:alpine >/dev/null
	sleep 2
}

docker_cgroup() {
	local name=$1 pid
	pid=$(docker inspect -f '{{.State.Pid}}' "$name")
	cgroup_path_of_pid "$pid"
}

parse_pgbench() {
	local log=$1
	local tps lat p99
	tps=$(awk '/^tps =/{print $3; exit}' "$log")
	lat=$(awk '/latency average =/{print $4; exit}' "$log")
	p99=$(awk '/^  p99 =/{print $3; exit}' "$log")
	p99=${p99:-$(awk '/^latency percentiles:/{f=1;next} f&&/p99/{print $3; exit}' "$log")}
	echo "$tps $lat $p99"
}

parse_wrk() {
	local log=$1
	local rps p50 p99
	rps=$(awk '/Requests\/sec:/{print $2; exit}' "$log")
	p50=$(awk '/Latency Distribution/{f=1;next} f&&/50%/{print $2; exit}' "$log")
	p99=$(awk '/Latency Distribution/{f=1;next} f&&/99%/{print $2; exit}' "$log")
	echo "$rps $p50 $p99"
}

dump_bpf_hids() {
	local json=$1 out=$2
	bpftool prog show -j >"$json" 2>/dev/null || echo '[]' >"$json"
	python3 - "$json" >"$out" <<'PY'
import json, sys
from pathlib import Path
progs = json.loads(Path(sys.argv[1]).read_text())
for p in sorted(progs, key=lambda x: x.get("name", "")):
    n = p.get("name", "")
    if not n.startswith("hids_"):
        continue
    rt = int(p.get("run_time_ns", 0))
    rc = int(p.get("run_cnt", 0))
    avg = rt / rc if rc else 0.0
    print(f"{n}\t{avg:.1f}\t{rc}\t{rc/60:.2f}")
PY
}

measure_idle_bpf() {
	mkdir -p "$DECOY_CG"
	sysctl -w kernel.bpf_stats_enabled=1 >/dev/null
	local log="$OUTROOT/idle-collect.log"
	systemd-run --scope --unit="hids-m5c-idle-$$" --slice=system.slice \
		"$COLLECT" -cgroup "$DECOY_CG" -duration 15s -zstd-level 0 -out "$OUTROOT/idle.bin" \
		>"$OUTROOT/idle-scope.log" 2>"$log" || true
	sleep 16
	sysctl -w kernel.bpf_stats_enabled=0 >/dev/null
	dump_bpf_hids "$OUTROOT/bpf-idle.json" "$IDLE_BPF"
}

run_t3_load() {
	local log=$1
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -r -U postgres -d postgres \
		>"$log" 2>&1 || true
}

run_t4_load() {
	local log=$1
	taskset -c 16-19 wrk -t4 -c64 -d60s "http://127.0.0.1:18080/f.bin" >"$log" 2>&1 || true
}

run_variant() {
	local load=$1 variant=$2
	local dir="$OUTROOT/${load}/${variant}"
	mkdir -p "$dir"
	local cgroup load_cg
	case $load in
	T3) cgroup=$(docker_cgroup pgtest); load_cg="$cgroup" ;;
	T4) cgroup=$(docker_cgroup m5-nginx); load_cg="$cgroup" ;;
	*) die "load $load";;
	esac

	local coll_pid="" coll_unit coll_log out_path coll_flags=() bpf_note=""
	local usec0 usec1
	usec0=$(cgroup_usage_usec "$load_cg")
	local iwi0 cal0 res0
	iwi0=$(irq_line_totals IWI)
	cal0=$(irq_line_totals CAL)
	res0=$(irq_line_totals RES)

	case $variant in
	C0) ;;
	a)
		sysctl -w kernel.bpf_stats_enabled=1 >/dev/null
		out_path="$dir/collect.bin"
		coll_unit="hids-m5c-${load}-${variant}-$$"
		coll_log="$dir/collect.log"
		systemd-run --scope --unit="$coll_unit" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration "$DURATION" -out "$out_path" \
			>"$dir/collect-scope.log" 2>"$coll_log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit")
		wait_ready "$coll_log"
		;;
	b)
		out_path="$dir/collect.bin"
		coll_unit="hids-m5c-${load}-${variant}-$$"
		coll_log="$dir/collect.log"
		systemd-run --scope --unit="$coll_unit" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration "$DURATION" -out "$out_path" -discard \
			>"$dir/collect-scope.log" 2>"$coll_log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit")
		wait_ready "$coll_log"
		;;
	f)
		mkdir -p "$TMPFS_MNT"
		mountpoint -q "$TMPFS_MNT" || mount -t tmpfs -o size=4G tmpfs "$TMPFS_MNT"
		out_path="$TMPFS_MNT/${load}-${variant}-$$.bin"
		coll_unit="hids-m5c-${load}-${variant}-$$"
		coll_log="$dir/collect.log"
		systemd-run --scope --unit="$coll_unit" --slice=system.slice \
			"$COLLECT" -cgroup "$cgroup" -duration "$DURATION" -out "$out_path" \
			>"$dir/collect-scope.log" 2>"$coll_log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "$coll_unit")
		wait_ready "$coll_log"
		;;
	*) die "variant $variant";;
	esac

	local load_log="$dir/load.log"
	case $load in
	T3) run_t3_load "$load_log" ;;
	T4) run_t4_load "$load_log" ;;
	esac

	if [[ $variant == a ]]; then
		dump_bpf_hids "$dir/bpf-progs.json" "$dir/bpf-hids.tsv"
		sysctl -w kernel.bpf_stats_enabled=0 >/dev/null
		bpf_note=$(awk '$1=="hids_sys_enter" || $1=="hids_sys_enter_fentry" {print $2"\t"$4; exit}' "$dir/bpf-hids.tsv")
	fi

	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	for ((i = 0; i < 600; i++)); do
		[[ -z $coll_pid ]] && break
		kill -0 "$coll_pid" 2>/dev/null || break
		sleep 0.1
	done

	usec1=$(cgroup_usage_usec "$load_cg")
	local diwi dcal dres
	diwi=$(irq_line_totals IWI); diwi=$((diwi - iwi0))
	dcal=$(irq_line_totals CAL); dcal=$((dcal - cal0))
	dres=$(irq_line_totals RES); dres=$((dres - res0))

	local metric lat p99
	case $load in
	T3) read -r metric lat p99 < <(parse_pgbench "$load_log") ;;
	T4) read -r metric lat p99 < <(parse_wrk "$load_log") ;;
	esac

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$load" "$variant" "$metric" "$lat" "$p99" "$diwi" "$dcal" "$dres" \
		"$((usec1 - usec0))" "$bpf_note" "$dir" >>"$RESULT"

	echo "$load $variant: metric=$metric lat=$lat p99=$p99 IWI=$diwi CAL=$dcal RES=$dres cgroup_usec=$((usec1-usec0))"
}

main() {
	[[ $EUID -eq 0 ]] || die "can root"
	[[ -x $COLLECT ]] || die "make build"
	command -v docker wrk bpftool systemd-run >/dev/null || die "thieu cong cu"
	mkdir -p "$OUTROOT"
	echo -e "load\tvariant\tmetric\tlat_avg\tp99\tIWI_delta\tCAL_delta\tRES_delta\tcgroup_usec_delta\tbpf_sys_enter_avg_ns_runs_per_s\tdir" >"$RESULT"

	stop_production_containers
	measure_idle_bpf

	setup_pg
	for v in C0 a b f; do run_variant T3 "$v"; done
	docker rm -f pgtest 2>/dev/null || true

	setup_nginx
	for v in C0 a b f; do run_variant T4 "$v"; done
	docker rm -f m5-nginx 2>/dev/null || true

	echo "luu $RESULT va $IDLE_BPF"
	column -t -s $'\t' "$RESULT" 2>/dev/null || cat "$RESULT"
}

main "$@"
