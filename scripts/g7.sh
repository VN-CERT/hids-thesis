#!/usr/bin/env bash
# g7.sh: kiem chung collector M2 bang so dem cua perf.
#
#   g7.sh a [N]        mot sysinj, mac dinh N=1000000, ring buffer 64 MiB
#   g7.sh b [N]        24 sysinj song song + stress-ng --cpu 24, ring buffer 64 MiB
#   g7.sh b-nho [N]    giong b nhung ring buffer 1 MiB, de ep ring buffer day
#   g7.sh c            loc theo cgroup cua container caddy
#   g7.sh d [N]        loc theo cgroup CHA, sysinj nam trong cgroup CON
#
# Trinh tu cua phan a/b/b-nho duoc thiet ke de perf va collector dem dung cung
# mot tap su kien:
#   1. chay sysinj, stdin noi vao mot FIFO; sysinj in PID roi chan tai mot lenh
#      read() duy nhat, tu luc do khong sinh them syscall nao;
#   2. chay hids-collect, cho toi khi no in dong READY (tracepoint da gan);
#   3. chay perf stat -p cho tung PID, cho toi khi perf da mo perf_event fd;
#   4. cho 2 giay;
#   5. ghi vao FIFO de sysinj bat dau;
#   6. cho sysinj thoat, cho them 2 giay, dung collector.
#
# Moi phan in nguyen van output cua perf.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
RECSTAT=./bin/rec-stat
SYSINJ=./bin/sysinj
GETPPID_NR=110

die() {
	echo "g7: $*" >&2
	exit 1
}

require_clean_git() {
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		if [[ $path != out/* ]]; then
			die "cay git khong sach (thay doi ngoai out/): $st $path — commit truoc khi chay g7"
		fi
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
}

check_common() {
	[[ $EUID -eq 0 ]] || die "can chay bang root"
	require_clean_git
	for f in "$COLLECT" "$RECSTAT" "$SYSINJ"; do
		[[ -x $f ]] || die "khong thay $f, chay 'make build' truoc"
	done
	command -v perf >/dev/null || die "khong co perf"
	mkdir -p out
}

# wait_ready cho toi khi file log cua collector co dong READY.
wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong in READY sau 30 giay, xem $log"
}

# wait_perf cho toi khi tien trinh perf da mo perf_event fd, tuc la da gan xong.
wait_perf() {
	local pid=$1 i
	for ((i = 0; i < 3000; i++)); do
		if ls -l "/proc/$pid/fd" 2>/dev/null | grep -q 'perf_event'; then
			return 0
		fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	return 1
}

perf_count() {
	awk '/raw_syscalls:sys_enter/ {gsub(/,/, "", $1); print $1; exit}' "$1"
}

recstat_field() {
	awk -F: -v k="$2" 'index($0, k) == 1 {gsub(/[ \t]/, "", $2); print $2; exit}' "$1"
}

check_kernel_clean() {
	echo "--- kiem tra kernel sau khi collector thoat ---"
	echo "\$ bpftool prog list | grep -ci hids"
	bpftool prog list | grep -ci hids
	echo "\$ bpftool link list | grep -ci hids"
	bpftool link list | grep -ci hids
	echo "\$ bpftool map list | grep -ciE 'hids_|ringbuf'"
	bpftool map list | grep -ciE 'hids_|ringbuf'
	echo "\$ ls -A /sys/fs/bpf | wc -l"
	ls -A /sys/fs/bpf | wc -l
}

# run_injection <nhan> <so_tien_trinh> <N> <ringbuf_mb> <stress: 0|1>
run_injection() {
	local label=$1 nproc=$2 n=$3 ringmb=$4 use_stress=$5
	local ts bin fifo prefix i p
	ts=$(date +%Y%m%d-%H%M%S)
	prefix="out/$label-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"

	echo "=== $label: $nproc sysinj, moi cai N=$n, ring buffer $ringmb MiB, stress-ng=$use_stress ==="
	[[ $use_stress -eq 1 ]] && { command -v stress-ng >/dev/null || die "khong co stress-ng"; }

	mkfifo "$fifo" || die "khong tao duoc fifo $fifo"
	# Mo FIFO o che do doc-ghi de sysinj mo duoc ngay, va de script giu dau ghi.
	exec 9<>"$fifo"

	# 1. sysinj: in PID roi chan tai read() tren stdin.
	local -a pids=()
	for ((i = 0; i < nproc; i++)); do
		"$SYSINJ" -n "$n" <"$fifo" >"$prefix-sysinj-$i.log" 2>&1 &
		pids+=($!)
	done
	echo "sysinj pids: ${pids[*]}"
	sleep 0.5

	# 2. collector, cho toi khi gan xong tracepoint.
	local -a pid_args=()
	for p in "${pids[@]}"; do pid_args+=(-pid "$p"); done
	"$COLLECT" "${pid_args[@]}" -ringbuf-mb "$ringmb" -out "$bin" 2>"$prefix-collect.log" &
	local collect_pid=$!
	wait_ready "$prefix-collect.log"
	echo "collector da gan tracepoint (READY)"

	# 3. mot perf cho moi PID, dem tat ca syscall.
	local -a perf_pids=()
	for p in "${pids[@]}"; do
		perf stat -e raw_syscalls:sys_enter -p "$p" 2>"$prefix-perf-$p.txt" &
		perf_pids+=($!)
	done
	for p in "${perf_pids[@]}"; do
		wait_perf "$p" || echo "g7: CANH BAO: perf $p chua mo perf_event fd" >&2
	done
	echo "perf da gan cho ${#perf_pids[@]} tien trinh"

	# 4. cho 2 giay.
	sleep 2

	local stress_pid=""
	if [[ $use_stress -eq 1 ]]; then
		stress-ng --cpu 24 --timeout 3600s >"$prefix-stress.log" 2>&1 &
		stress_pid=$!
		sleep 1
	fi

	# 5. mo khoa: ghi mot byte cho moi sysinj roi dong dau ghi (ai chua nhan
	#    duoc byte thi nhan EOF).
	local start_s end_s
	start_s=$(date +%s.%N)
	printf '%*s' "$nproc" '' >&9
	exec 9>&-

	# 6. cho sysinj thoat.
	for p in "${pids[@]}"; do wait "$p"; done
	end_s=$(date +%s.%N)

	if [[ -n $stress_pid ]]; then
		kill -INT "$stress_pid" 2>/dev/null
		wait "$stress_pid" 2>/dev/null
	fi

	sleep 2
	kill -INT "$collect_pid" 2>/dev/null
	wait "$collect_pid"
	for p in "${perf_pids[@]}"; do wait "$p" 2>/dev/null; done
	rm -f "$fifo"

	"$RECSTAT" -nr "$GETPPID_NR" "$bin" >"$prefix-recstat.txt" 2>&1

	echo
	echo "--- perf stat cua tung sysinj (nguyen van) ---"
	for p in "${pids[@]}"; do
		echo "### pid $p"
		cat "$prefix-perf-$p.txt"
	done

	echo "--- log collector (nguyen van) ---"
	cat "$prefix-collect.log"

	echo
	echo "--- bang theo tung PID ---"
	# Doc bang "so ban ghi theo tgid" trong output rec-stat: mot lan quet file.
	declare -A REC NR GAP
	local tgid rec nrc first gapc rest
	while read -r tgid rec nrc first gapc rest; do
		REC[$tgid]=$rec
		NR[$tgid]=$nrc
		GAP[$tgid]=$gapc
	done < <(awk '/^so ban ghi theo tgid/ {f=1; next} f && /^$/ {f=0} f && $1 ~ /^[0-9]+$/ {print}' "$prefix-recstat.txt")

	printf '%10s %12s %14s %14s %12s %14s %12s\n' \
		"pid" "N_thiet_ke" "perf_sys_enter" "ban_ghi" "ban_ghi_110" "perf-ban_ghi" "GAP_BEFORE"
	local t_n=0 t_perf=0 t_rec=0 t_nr=0 t_gap=0 t_diff=0
	for p in "${pids[@]}"; do
		local pc rc nc gc d
		pc=$(perf_count "$prefix-perf-$p.txt")
		rc=${REC[$p]:-0}
		nc=${NR[$p]:-0}
		gc=${GAP[$p]:-0}
		if [[ ${pc:-} =~ ^[0-9]+$ ]]; then
			d=$((pc - rc))
			t_perf=$((t_perf + pc))
			t_diff=$((t_diff + d))
		else
			pc=${pc:-?}
			d="?"
		fi
		printf '%10s %12s %14s %14s %12s %14s %12s\n' "$p" "$n" "$pc" "$rc" "$nc" "$d" "$gc"
		t_n=$((t_n + n))
		t_rec=$((t_rec + rc))
		t_nr=$((t_nr + nc))
		t_gap=$((t_gap + gc))
	done
	printf '%10s %12s %14s %14s %12s %14s %12s\n' \
		"TONG" "$t_n" "$t_perf" "$t_rec" "$t_nr" "$t_diff" "$t_gap"

	echo
	echo "--- doi chieu toan cuc ---"
	local g_att g_read g_drop g_miss
	g_att=$(recstat_field "$prefix-recstat.txt" "  so lan dinh ghi")
	g_read=$(recstat_field "$prefix-recstat.txt" "  so ban ghi collector doc duoc")
	g_drop=$(recstat_field "$prefix-recstat.txt" "  tong bo dem mat")
	g_miss=$(recstat_field "$prefix-recstat.txt" "  tong so seq bi thieu")
	printf '%-45s %s\n' "tong lan dinh ghi (tong seq theo CPU):" "${g_att:-?}"
	printf '%-45s %s\n' "tong ban ghi doc duoc:" "${g_read:-?}"
	printf '%-45s %s\n' "tong bo dem mat:" "${g_drop:-?}"
	printf '%-45s %s\n' "tong so seq bi thieu theo CPU:" "${g_miss:-?}"
	printf '%-45s %s\n' "tong (perf - ban ghi):" "$t_diff"

	echo
	echo "--- thoi gian va dung luong ---"
	echo "thoi gian bom syscall: $(awk -v a="$start_s" -v b="$end_s" 'BEGIN {printf "%.3f", b - a}') s"
	echo "kich thuoc $bin: $(stat -c %s "$bin") byte"
	echo "kich thuoc $bin.stats: $(stat -c %s "$bin.stats") byte"

	echo
	echo "--- rec-stat day du (nguyen van) ---"
	cat "$prefix-recstat.txt"

	echo
	check_kernel_clean
	echo
	echo "du lieu: $bin | thong ke: $bin.stats"
}

part_c() {
	local ts bin prefix cid cg rel t0 t1
	ts=$(date +%Y%m%d-%H%M%S)
	prefix="out/g7c-$ts"
	bin="$prefix.bin"

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

	"$COLLECT" -cgroup "$cg" -duration 70s -out "$bin" 2>"$prefix-collect.log" &
	local collect_pid=$!
	wait_ready "$prefix-collect.log"
	echo "collector da gan tracepoint (READY)"
	sleep 2

	# Tai nen trong cua so do: container caddy luc ranh gan nhu khong goi
	# syscall nao, nen phai tu tao viec cho no lam.
	(
		for ((i = 0; i < 100000; i++)); do
			docker exec caddy ls / >/dev/null 2>&1 || break
			echo "$i" >>"$prefix-load.log"
		done
	) >/dev/null 2>&1 &
	local load_pid=$!

	t0=$(python3 -c 'import time;print(time.monotonic_ns())')
	perf stat -a -e raw_syscalls:sys_enter -G "$rel" -- sleep 60 2>"$prefix-perf.txt"
	t1=$(python3 -c 'import time;print(time.monotonic_ns())')

	kill "$load_pid" 2>/dev/null
	pkill -f 'docker exec caddy' 2>/dev/null
	wait "$load_pid" 2>/dev/null
	wait "$collect_pid"

	echo
	echo "--- cua so do (CLOCK_MONOTONIC ns) ---"
	echo "truoc perf: $t0"
	echo "sau perf  : $t1"
	echo "do dai    : $(((t1 - t0) / 1000000)) ms"
	echo "ghi chu   : cua so nay rong hon cua so cua perf vi perf mat mot chut thoi gian"
	echo "            de gan va go bo dem; perf tu bao thoi gian cua no o duoi."
	echo "so lan 'docker exec caddy ls /' da chay: $(wc -l <"$prefix-load.log" 2>/dev/null || echo 0)"
	echo
	echo "--- perf stat (nguyen van) ---"
	cat "$prefix-perf.txt"
	echo "--- log collector (nguyen van) ---"
	cat "$prefix-collect.log"
	echo
	echo "--- thoi gian va dung luong ---"
	echo "kich thuoc $bin: $(stat -c %s "$bin") byte"
	echo "kich thuoc $bin.stats: $(stat -c %s "$bin.stats") byte"
	echo
	echo "--- rec-stat trong cua so tren (nguyen van) ---"
	"$RECSTAT" -nr "$GETPPID_NR" -from-mono "$t0" -to-mono "$t1" "$bin" | tee "$prefix-recstat.txt"
	echo
	echo "--- doi chieu ---"
	local pc rc
	pc=$(perf_count "$prefix-perf.txt")
	rc=$(recstat_field "$prefix-recstat.txt" "so ban ghi sau khi loc")
	printf '%-45s %s\n' "perf raw_syscalls:sys_enter (-G $rel):" "${pc:-?}"
	printf '%-45s %s\n' "ban ghi collector trong cua so:" "${rc:-?}"
	echo
	check_kernel_clean
	echo
	echo "du lieu: $bin | thong ke: $bin.stats"
}

# part_d: loc theo cgroup CHA trong khi tien trinh nam o cgroup CON, de kiem
# tra duong duyet to tien bang mot so luong syscall biet truoc.
part_d() {
	local n=$1
	local ts bin prefix fifo cg_cha cg_con
	ts=$(date +%Y%m%d-%H%M%S)
	prefix="out/g7d-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	cg_cha=/sys/fs/cgroup/hids-test
	cg_con=$cg_cha/con

	echo "=== G7d: loc theo cgroup CHA, tien trinh nam trong cgroup CON, N=$n ==="

	rmdir "$cg_con" "$cg_cha" 2>/dev/null
	mkdir -p "$cg_con" || die "khong tao duoc cgroup tam $cg_con"
	echo "cgroup cha=$cg_cha inode=$(stat -c %i "$cg_cha")"
	echo "cgroup con=$cg_con inode=$(stat -c %i "$cg_con")"

	mkfifo "$fifo" || die "khong tao duoc fifo $fifo"
	exec 9<>"$fifo"

	"$SYSINJ" -n "$n" <"$fifo" >"$prefix-sysinj.log" 2>&1 &
	local pid=$!
	sleep 0.5
	echo "sysinj pid=$pid"

	echo "$pid" >"$cg_con/cgroup.procs" || die "khong chuyen duoc $pid vao $cg_con"
	echo "\$ cat /proc/$pid/cgroup"
	cat "/proc/$pid/cgroup"

	"$COLLECT" -cgroup "$cg_cha" -out "$bin" 2>"$prefix-collect.log" &
	local collect_pid=$!
	wait_ready "$prefix-collect.log"
	echo "collector da gan tracepoint (READY), loc theo cgroup CHA"

	perf stat -e raw_syscalls:sys_enter -p "$pid" 2>"$prefix-perf.txt" &
	local perf_pid=$!
	wait_perf "$perf_pid" || echo "g7: CANH BAO: perf chua mo perf_event fd" >&2
	echo "perf da gan"

	sleep 2
	printf ' ' >&9
	exec 9>&-

	wait "$pid"
	sleep 2
	kill -INT "$collect_pid" 2>/dev/null
	wait "$collect_pid"
	wait "$perf_pid" 2>/dev/null
	rm -f "$fifo"

	echo "\$ rmdir $cg_con $cg_cha"
	rmdir "$cg_con" "$cg_cha" && echo "da xoa cgroup tam"

	"$RECSTAT" -nr "$GETPPID_NR" "$bin" >"$prefix-recstat.txt" 2>&1

	echo
	echo "--- perf stat (nguyen van) ---"
	cat "$prefix-perf.txt"
	echo "--- log collector (nguyen van) ---"
	cat "$prefix-collect.log"

	echo
	echo "--- bang ket qua ---"
	local pc rc nc
	pc=$(perf_count "$prefix-perf.txt")
	rc=$(recstat_field "$prefix-recstat.txt" "tong so ban ghi trong file")
	nc=$(recstat_field "$prefix-recstat.txt" "ban ghi co syscall_nr=$GETPPID_NR")
	printf '%-45s %s\n' "N theo thiet ke:" "$n"
	printf '%-45s %s\n' "perf raw_syscalls:sys_enter (-p $pid):" "${pc:-?}"
	printf '%-45s %s\n' "so ban ghi collector:" "${rc:-?}"
	printf '%-45s %s\n' "so ban ghi nr=$GETPPID_NR:" "${nc:-?}"
	printf '%-45s %s\n' "hieu (perf - ban ghi):" "$((${pc:-0} - ${rc:-0}))"

	echo
	echo "--- thoi gian va dung luong ---"
	echo "kich thuoc $bin: $(stat -c %s "$bin") byte"

	echo
	echo "--- rec-stat day du (nguyen van) ---"
	cat "$prefix-recstat.txt"
	echo
	echo "--- file theo doi dinh ky ---"
	cat "$bin.periodic"

	echo
	check_kernel_clean
	echo
	echo "du lieu: $bin | thong ke: $bin.stats"
}

main() {
	local part=${1:-}
	local n=${2:-1000000}

	check_common
	case "$part" in
	a) run_injection g7a 1 "$n" 64 0 ;;
	b) run_injection g7b 24 "$n" 64 1 ;;
	b-nho) run_injection g7b-nho 24 "$n" 1 1 ;;
	c) part_c ;;
	d) part_d "$n" ;;
	*)
		echo "cach dung: $0 <a|b|b-nho|c|d> [N]" >&2
		exit 2
		;;
	esac
}

main "$@"
