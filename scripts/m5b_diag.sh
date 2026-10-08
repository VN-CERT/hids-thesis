#!/usr/bin/env bash
# m5b_diag.sh — buoc 1 M5b: T3-C1 va T4-C1, bien the (a)–(e), 60 giay moi lan.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

COLLECT=./bin/hids-collect
DATE=$(date +%Y%m%d)
OUTROOT="${M5B_DIAG_OUT:-validation/m5b-${DATE}/diag}"
DURATION=60s
RESULT="$OUTROOT/diag-summary.tsv"

die() { echo "m5b_diag: $*" >&2; exit 1; }

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

scope_usage_usec() {
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

irq_iwi_cal_totals() {
	# Tong dem tren moi CPU cho dong bat dau bang IWI: hoac CAL:
	awk '
		/^ *[A-Z0-9]+:/ {
			n = split($1, a, ":");
			t = a[1];
			if (t != "IWI" && t != "CAL") next;
			s = 0;
			for (i = 2; i <= NF; i++) s += $i;
			if (t == "IWI") iwi += s;
			if (t == "CAL") cal += s;
		}
		END { printf "%d %d\n", iwi+0, cal+0 }
	' /proc/interrupts
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

run_variant() {
	local load=$1 variant=$2
	local dir="$OUTROOT/${load}-C1/${variant}"
	mkdir -p "$dir"
	local cgroup coll_unit coll_log coll_pid coll_cg
	case $load in
	T3) cgroup=$(docker_cgroup pgtest) ;;
	T4) cgroup=$(docker_cgroup m5-nginx) ;;
	*) die "load $load";;
	esac

	local discard_flag=() bpf_stats=0
	case $variant in
	a) ;;
	b) discard_flag=(-discard) ;;
	c) bpf_stats=1 ;;
	d|e) ;;
	*) die "variant $variant";;
	esac

	local iwi0 cal0 iwi1 cal1
	read -r iwi0 cal0 < <(irq_iwi_cal_totals)

	[[ $bpf_stats -eq 1 ]] && sysctl -w kernel.bpf_stats_enabled=1 >/dev/null

	coll_unit="hids-m5b-diag-${load}-${variant}-$$"
	coll_log="$dir/collect.log"
	systemd-run --scope --unit="$coll_unit" --slice=system.slice \
		"$COLLECT" -cgroup "$cgroup" -duration "$DURATION" -out "$dir/collect.bin" \
		"${discard_flag[@]}" >"$dir/collect-scope.log" 2>"$coll_log" &
	sleep 0.5
	coll_pid=$(scope_main_pid "$coll_unit")
	wait_ready "$coll_log"
	coll_cg=$(systemctl show "${coll_unit}.scope" -p ControlGroup --value 2>/dev/null || true)
	local usec0=0
	[[ -n $coll_cg ]] && usec0=$(scope_usage_usec "/sys/fs/cgroup${coll_cg}")

	local load_log="$dir/load.log"
	case $load in
	T3)
		taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres \
			>"$load_log" 2>&1 || true
		metric=$(awk '/^tps =/{print $3; exit}' "$load_log")
		;;
	T4)
		taskset -c 16-19 wrk -t4 -c64 -d60s "http://127.0.0.1:18080/f.bin" >"$load_log" 2>&1 || true
		metric=$(awk '/Requests\/sec:/{print $2}' "$load_log")
		;;
	esac

	local bpf_note=""
	if [[ $bpf_stats -eq 1 ]]; then
		bpftool prog show -j >"$dir/bpf-progs.json" 2>/dev/null || echo '[]' >"$dir/bpf-progs.json"
		python3 - "$dir/bpf-progs.json" >"$dir/bpf-hids.tsv" <<'PY'
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
		bpf_note=$(awk '$1=="hids_sys_enter"{print $2"\t"$4}' "$dir/bpf-hids.tsv" | head -1)
	fi

	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	for ((i = 0; i < 600; i++)); do
		kill -0 "$coll_pid" 2>/dev/null || break
		sleep 0.1
	done
	[[ $bpf_stats -eq 1 ]] && sysctl -w kernel.bpf_stats_enabled=0 >/dev/null

	local usec1=0
	[[ -n $coll_cg ]] && usec1=$(scope_usage_usec "/sys/fs/cgroup${coll_cg}")
	local coll_delta=$((usec1 - usec0))

	read -r iwi1 cal1 < <(irq_iwi_cal_totals)
	local diwi=$((iwi1 - iwi0)) dcal=$((cal1 - cal0))

	local drops recs
	drops=$(sed -n 's/.*mat: \([0-9]*\).*/\1/p' "$coll_log" | tail -1)
	recs=$(sed -n 's/.*ban ghi doc duoc: \([0-9]*\).*/\1/p' "$coll_log" | tail -1)

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$load" "$variant" "$metric" "$coll_delta" "$diwi" "$dcal" "$recs" "$drops" "$bpf_note" "$dir" \
		>>"$RESULT"

	echo "$load $variant: metric=$metric coll_usec_delta=$coll_delta IWI_delta=$diwi CAL_delta=$dcal"
	hids_drop_collect_bin "$dir/collect.bin"
}

main() {
	[[ $EUID -eq 0 ]] || die "can root"
	trap hids_print_df_at_job_end EXIT
	hids_require_disk_for_long_job
	[[ -x $COLLECT ]] || die "make build"
	command -v docker wrk bpftool systemd-run >/dev/null || die "thieu cong cu"
	mkdir -p "$OUTROOT"
	echo -e "load\tvariant\tmetric\tcoll_usec_delta\tIWI_delta\tCAL_delta\trecords\tdrops\tbpf_sys_enter_avg_ns_runs_per_s\tdir" >"$RESULT"

	setup_pg
	for v in a b c d e; do run_variant T3 "$v"; done
	docker rm -f pgtest 2>/dev/null || true

	setup_nginx
	for v in a b c d e; do run_variant T4 "$v"; done
	docker rm -f m5-nginx 2>/dev/null || true

	echo "luu $RESULT"
	column -t -s $'\t' "$RESULT" 2>/dev/null || cat "$RESULT"
}

main "$@"
