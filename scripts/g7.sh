#!/usr/bin/env bash
# g7.sh: kiem chung collector M2 bang so dem cua perf.
#
#   g7.sh a [N]   mot sysinj, mac dinh N=1000000
#   g7.sh b [N]   24 sysinj song song + stress-ng --cpu 24
#   g7.sh c       loc theo cgroup cua container caddy
#
# Moi phan in nguyen van output cua perf.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
RECSTAT=./bin/rec-stat
SYSINJ=./bin/sysinj
GO_FILE=/tmp/hids-go
GETPPID_NR=110

die() {
	echo "g7: $*" >&2
	exit 1
}

check_common() {
	[[ $EUID -eq 0 ]] || die "can chay bang root"
	for f in "$COLLECT" "$RECSTAT" "$SYSINJ"; do
		[[ -x $f ]] || die "khong thay $f, chay 'make build' truoc"
	done
	command -v perf >/dev/null || die "khong co perf"
	mkdir -p out
}

stop_collector() {
	local pid=$1
	kill -INT "$pid" 2>/dev/null
	wait "$pid"
}

part_a() {
	local n=$1
	local ts bin
	ts=$(date +%Y%m%d-%H%M%S)
	bin="out/g7a-$ts.bin"

	echo "=== G7a: mot sysinj, N=$n ==="
	rm -f "$GO_FILE"

	"$SYSINJ" -n "$n" >"out/g7a-$ts-sysinj.log" 2>&1 &
	local sysinj_pid=$!
	echo "sysinj pid=$sysinj_pid"

	"$COLLECT" -pid "$sysinj_pid" -out "$bin" 2>"out/g7a-$ts-collect.log" &
	local collect_pid=$!

	perf stat -e raw_syscalls:sys_enter -p "$sysinj_pid" 2>"out/g7a-$ts-perf-all.txt" &
	local perf_all=$!
	perf stat -e raw_syscalls:sys_enter --filter "id == $GETPPID_NR" -p "$sysinj_pid" 2>"out/g7a-$ts-perf-getppid.txt" &
	local perf_gp=$!

	sleep 2
	touch "$GO_FILE"
	wait "$sysinj_pid"
	sleep 2
	stop_collector "$collect_pid"
	wait "$perf_all" "$perf_gp" 2>/dev/null

	echo
	echo "--- N theo thiet ke: $n"
	echo
	echo "--- perf stat, tat ca syscall (nguyen van) ---"
	cat "out/g7a-$ts-perf-all.txt"
	echo "--- perf stat, rieng getppid id == $GETPPID_NR (nguyen van) ---"
	cat "out/g7a-$ts-perf-getppid.txt"
	echo "--- log collector ---"
	cat "out/g7a-$ts-collect.log"
	echo
	echo "--- rec-stat ---"
	"$RECSTAT" -nr "$GETPPID_NR" "$bin"
	echo
	echo "du lieu: $bin"
}

part_b() {
	local n=$1
	local ts bin
	ts=$(date +%Y%m%d-%H%M%S)
	bin="out/g7b-$ts.bin"

	echo "=== G7b: 24 sysinj song song, moi cai N=$n, co stress-ng --cpu 24 ==="
	command -v stress-ng >/dev/null || die "khong co stress-ng"
	rm -f "$GO_FILE"

	local -a sysinj_pids=()
	local i
	for ((i = 0; i < 24; i++)); do
		"$SYSINJ" -n "$n" >"out/g7b-$ts-sysinj-$i.log" 2>&1 &
		sysinj_pids+=($!)
	done
	echo "sysinj pids: ${sysinj_pids[*]}"

	local -a pid_args=()
	local p
	for p in "${sysinj_pids[@]}"; do
		pid_args+=(-pid "$p")
	done
	"$COLLECT" "${pid_args[@]}" -out "$bin" 2>"out/g7b-$ts-collect.log" &
	local collect_pid=$!

	local -a perf_pids=()
	for p in "${sysinj_pids[@]}"; do
		perf stat -e raw_syscalls:sys_enter -p "$p" 2>"out/g7b-$ts-perf-$p.txt" &
		perf_pids+=($!)
	done

	sleep 2
	stress-ng --cpu 24 --timeout 3600s >"out/g7b-$ts-stress.log" 2>&1 &
	local stress_pid=$!
	touch "$GO_FILE"

	for p in "${sysinj_pids[@]}"; do
		wait "$p"
	done
	kill -INT "$stress_pid" 2>/dev/null
	wait "$stress_pid" 2>/dev/null

	sleep 2
	stop_collector "$collect_pid"
	for p in "${perf_pids[@]}"; do
		wait "$p" 2>/dev/null
	done

	echo
	echo "--- perf stat cua tung sysinj (nguyen van) ---"
	for p in "${sysinj_pids[@]}"; do
		echo "### pid $p"
		cat "out/g7b-$ts-perf-$p.txt"
	done

	echo "--- log collector ---"
	cat "out/g7b-$ts-collect.log"

	echo
	echo "--- bang theo tung PID ---"
	printf '%10s %14s %14s\n' "pid" "perf_sys_enter" "ban_ghi"
	local total_perf=0 total_rec=0
	for p in "${sysinj_pids[@]}"; do
		local pc rc
		pc=$(awk '/raw_syscalls:sys_enter/ {gsub(/,/, "", $1); print $1; exit}' "out/g7b-$ts-perf-$p.txt")
		rc=$("$RECSTAT" -tgid "$p" "$bin" | awk -F: '/^so ban ghi sau khi loc/ {gsub(/ /, "", $2); print $2; exit}')
		printf '%10s %14s %14s\n' "$p" "${pc:-?}" "${rc:-?}"
		[[ ${pc:-} =~ ^[0-9]+$ ]] && total_perf=$((total_perf + pc))
		[[ ${rc:-} =~ ^[0-9]+$ ]] && total_rec=$((total_rec + rc))
	done

	local drops
	drops=$("$RECSTAT" "$bin" | awk -F: '/tong bo dem mat/ {gsub(/ /, "", $2); print $2; exit}')
	drops=${drops:-0}
	printf '%10s %14s %14s   (ban ghi + mat = %s, mat = %s)\n' "TONG" "$total_perf" "$total_rec" \
		"$((total_rec + drops))" "$drops"
	echo "ghi chu: bo dem mat la so toan cuc theo CPU, khong tach duoc theo PID."

	echo
	echo "--- rec-stat toan bo ---"
	"$RECSTAT" -nr "$GETPPID_NR" "$bin"
	echo
	echo "du lieu: $bin"
}

part_c() {
	local ts bin cid cg rel t0 t1
	ts=$(date +%Y%m%d-%H%M%S)
	bin="out/g7c-$ts.bin"

	echo "=== G7c: loc theo cgroup cua container caddy ==="
	command -v docker >/dev/null || die "khong co docker"
	command -v python3 >/dev/null || die "khong co python3"

	cid=$(docker inspect -f '{{.Id}}' caddy) || die "khong doc duoc id container caddy"
	cg="/sys/fs/cgroup/system.slice/docker-$cid.scope"
	[[ -d $cg ]] || die "khong thay thu muc cgroup $cg"
	rel=${cg#/sys/fs/cgroup/}
	echo "container caddy id=$cid"
	echo "cgroup=$cg"
	echo "cgroup tuong doi=$rel"
	echo "inode=$(stat -c %i "$cg")"

	"$COLLECT" -cgroup "$cg" -duration 70s -out "$bin" 2>"out/g7c-$ts-collect.log" &
	local collect_pid=$!
	sleep 2

	t0=$(python3 -c 'import time;print(time.monotonic_ns())')
	perf stat -a -e raw_syscalls:sys_enter -G "$rel" -- sleep 60 2>"out/g7c-$ts-perf.txt"
	t1=$(python3 -c 'import time;print(time.monotonic_ns())')

	wait "$collect_pid"

	echo
	echo "--- cua so do (CLOCK_MONOTONIC ns) ---"
	echo "truoc perf: $t0"
	echo "sau perf  : $t1"
	echo
	echo "--- perf stat (nguyen van) ---"
	cat "out/g7c-$ts-perf.txt"
	echo "--- log collector ---"
	cat "out/g7c-$ts-collect.log"
	echo
	echo "--- rec-stat trong cua so tren ---"
	"$RECSTAT" -from-mono "$t0" -to-mono "$t1" "$bin"
	echo
	echo "du lieu: $bin"
}

main() {
	local part=${1:-}
	local n=${2:-1000000}

	check_common
	case "$part" in
	a) part_a "$n" ;;
	b) part_b "$n" ;;
	c) part_c ;;
	*)
		echo "cach dung: $0 <a|b|c> [N]" >&2
		exit 2
		;;
	esac
}

main "$@"
