#!/usr/bin/env bash
# M5f tiếp tục: Case A T4 wrk, T3 cấu hình mới, T3-R/T4-R, R021.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" PATH="/usr/local/bin:/usr/local/go/bin:/root/go/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

OUTROOT="${M5F_OUT:-validation/m5f-20261008}"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
COLLECT=./bin/hids-collect
DECOY_CG="/sys/fs/cgroup/hids-m5-decoy"
M5F_PARSE=./analysis/m5f_parse.py
PARSE_FIXED="$OUTROOT/m5f_parse.tsv"
PARSE_SAT="$OUTROOT/m5f_parse_sat.tsv"
REST=${M5F_REST:-10}
LOG=out/jobs/m5f-resume.log

die() { echo "m5f-resume: $*" >&2; exit 1; }

# meta.txt: "target_tps=123 cgroup_cpu_usec=456" (không dùng awk -F= — $2 sẽ là "123 cgroup_cpu_usec=456").
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

step1_archive_invalid_t4() {
	mkdir -p "$OUTROOT/T4-khong-hop-le"
	if [[ -d $OUTROOT/T4 && ! -L $OUTROOT/T4 ]]; then
		mv "$OUTROOT/T4" "$OUTROOT/T4-khong-hop-le/T4-wrk2-khong-rate"
	fi
	cat >"$OUTROOT/T4-khong-hop-le/README.md" <<'EOF'
# T4 kịch trần không hợp lệ (M5f bước 1 — trường hợp A)

wrk2 bắt buộc tham số `-R`; chạy không `-R` chỉ in usage. 21 lượt `wrk2.txt` trong `T4-wrk2-khong-rate/` không dùng cho T4-R.
EOF
	echo "CASE=A" >"$OUTROOT/step1-case.txt"
}

t4_sat_wrk() {
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
	*) die "cond";;
	esac
	taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk.txt" 2>&1 || true
	[[ -n $coll_pid ]] && kill -TERM "$coll_pid" 2>/dev/null || true
	[[ -n $coll_pid ]] && wait_pid_gone "$coll_pid"
	usec1=$(scope_usage_usec "$cgroup")
	echo "cgroup_cpu_usec=$((usec1 - usec0))" >"$dir/meta.txt"
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	local label="T4-sat ${cond} run${run}"
	local line
	line=$(python3 "$M5F_PARSE" wrk2 "$dir/wrk.txt")
	echo "$label	$line" >>"$PARSE_SAT"
}

t3_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T3/${cond}/run${run}"
	mkdir -p "$dir"
	pg_maintain
	local cgroup coll_pid="" usec0 usec1 cg
	cg=$(docker_cgroup pgtest)
	cgroup=$cg
	usec0=$(scope_usage_usec "$cg")
	case $cond in
	C0) ;;
	C1)
		systemd-run --scope --unit="hids-m5f-t3-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$cg" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t3-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	C2)
		mkdir -p "$DECOY_CG"
		systemd-run --scope --unit="hids-m5f-t3-${cond}-${run}-$$" --slice=system.slice -- \
			"$COLLECT" -cgroup "$DECOY_CG" -duration 120s -out "$dir/collect.bin" 2>"$dir/collect.log" &
		sleep 0.5
		coll_pid=$(scope_main_pid "hids-m5f-t3-${cond}-${run}-$$")
		wait_ready "$dir/collect.log"
		;;
	*) die "cond";;
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
	hids_drop_collect_artifacts "$dir" 2>/dev/null || true
	local label="T3-sat ${cond} run${run}"
	local line
	shopt -s nullglob
	local pgf=("$dir"/pglog.*)
	shopt -u nullglob
	line=$(python3 "$M5F_PARSE" pgbench "${pgf[@]}")
	echo "$label	$line" >>"$PARSE_SAT"
}

c0_tps_t3() {
	python3 - "$OUTROOT" <<'PY'
import re, subprocess, sys
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
	line=$(python3 "$M5F_PARSE" "$@")
	echo "$label	$line" >>"$PARSE_FIXED"
	echo "$line"
	if echo "$line" | awk -F'\t' '$(NF)=="NGHI_NGO" || $(NF-1)=="LECH" {e=1} END{exit e?0:1}'; then
		return 1
	fi
	return 0
}

t3r_load() {
	local pct=$1 cond=$2 run=$3
	local dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
	mkdir -p "$dir"
	pg_maintain
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
	local rate label="T3-R${pct} ${cond} run${run}"
	t3r_load "$pct" "$cond" "$run"
	rate=$(meta_field "$dir/meta.txt" target_tps)
	shopt -s nullglob
	local pgf=("$dir"/pglog.*)
	shopt -u nullglob
	if ! record_parse_fixed "$label" pgbench --target "$rate" "${pgf[@]}"; then
		echo "m5f: retry $label" >&2
		t3r_load "$pct" "$cond" "$run"
		rate=$(meta_field "$dir/meta.txt" target_tps)
		pgfiles=("$dir"/pglog.*)
		record_parse_fixed "$label" pgbench --target "$rate" "${pgfiles[@]}" || \
			echo "$label van NGHI_NGO/LECH" >>"$OUTROOT/parse-warnings.txt"
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
	taskset -c 16-19 /usr/local/bin/wrk2 -t4 -c64 -d60s -R "$rate_int" --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk2.txt" 2>&1 || true
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
	rate_int=$(meta_field "$dir/meta.txt" target_rps)
	if ! record_parse_fixed "$label" wrk2 --target "$rate_int" "$dir/wrk2.txt"; then
		echo "m5f: retry $label" >&2
		t4r_load "$pct" "$cond" "$run"
		rate_int=$(meta_field "$dir/meta.txt" target_rps)
		record_parse_fixed "$label" wrk2 --target "$rate_int" "$dir/wrk2.txt" || \
			echo "$label van NGHI_NGO/LECH" >>"$OUTROOT/parse-warnings.txt"
	fi
}

archive_old_t3r() {
	mkdir -p "$OUTROOT/T3-R-cau-hinh-cu"
	for d in T3-R25 T3-R50 T3-C0-sat; do
		[[ -e $OUTROOT/$d ]] && mv "$OUTROOT/$d" "$OUTROOT/T3-R-cau-hinh-cu/"
	done
	rm -f "$OUTROOT/m5f_parse.tsv"
}

git_push_times() {
	: >"$OUTROOT/git-push-reflog.txt"
	for ref in .git/refs/remotes/github/*; do
		[[ -e $ref ]] || continue
		refname=${ref#.git/}
		echo "=== $refname ===" >>"$OUTROOT/git-push-reflog.txt"
		git reflog show --date=iso "$refname" >>"$OUTROOT/git-push-reflog.txt" 2>&1 || true
	done
}

main() {
	mkdir -p out/jobs "$OUTROOT" out "$DECOY_CG"
	exec >>"$LOG" 2>&1
	echo "=== m5f-resume $(date -Iseconds) ==="
	hids_require_disk_for_long_job
	stop_containers
	hids_require_clean_git || die "git khong sach"
	make build
	command -v wrk wrk2 docker systemd-run >/dev/null || die "thieu cong cu"

	echo "label	kieu	n	toc_do_per_s	lat_tb_ms	p50_ms	p99_ms	max_ms	lag_tb_ms	lag_p99_ms	loi	dat_muc	hop_ly" >"$PARSE_FIXED"
	echo "label	kieu	n	toc_do_per_s	(note: T4/T3 sat chi dung toc_do_per_s)" >"$PARSE_SAT"

	step1_archive_invalid_t4
	local cond run pct
	for ((run = 1; run <= 7; run++)); do
		for cond in C0 C1 C2; do
			t4_sat_wrk "$cond" "$run"
			sleep "$REST"
		done
	done

	archive_old_t3r
	docker rm -f pgtest m5-nginx 2>/dev/null || true
	setup_pg
	setup_nginx

	for ((run = 1; run <= 3; run++)); do
		for cond in C0 C1 C2; do
			t3_sat_run "$cond" "$run"
			sleep "$REST"
		done
	done

	for pct in 25 50; do
		rm -rf "$OUTROOT/T3-R${pct}"
		for ((run = 1; run <= 3; run++)); do
			for cond in C0 C1 C2; do
				t3r_run "$pct" "$cond" "$run"
				sleep "$REST"
			done
		done
	done

	for pct in 25 50; do
		rm -rf "$OUTROOT/T4-R${pct}"
		for ((run = 1; run <= 3; run++)); do
			for cond in C0 C1 C2; do
				t4r_run "$pct" "$cond" "$run"
				sleep "$REST"
			done
		done
	done

	docker rm -f pgtest m5-nginx 2>/dev/null || true
	git_push_times
	echo "=== m5f-resume xong ==="
}

main "$@"
