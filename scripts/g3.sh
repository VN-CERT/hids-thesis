#!/usr/bin/env bash
# g3.sh — kiem chung M3 muc H: S1-S5, G-real, G-irq, G7d.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

COLLECT=./bin/hids-collect
RECCHK=./bin/rec-check
WL=./bin/wl
G7=./scripts/g7.sh
G3WIN=./scripts/g3_window.py
OUTROOT=validation/g3-$(date +%Y%m%d)
SCHEDSTAT_SYS=/proc/sys/kernel/sched_schedstats
WL_CPU=20
GETUID_NR=102
GETPPID_NR=110

die() {
	echo "g3: $*" >&2
	exit 1
}

check_common() {
	[[ $EUID -eq 0 ]] || die "can chay bang root"
	for f in "$COLLECT" "$RECCHK" "$WL" "$G3WIN" "$G7"; do
		[[ -e $f ]] || die "khong thay $f (make build?)"
	done
	command -v taskset >/dev/null || die "khong co taskset"
	command -v stress-ng >/dev/null || die "khong co stress-ng"
	mkdir -p out "$OUTROOT"
}

schedstats_save() {
	SCHEDSTATS_OLD=$(cat "$SCHEDSTAT_SYS")
	echo "$SCHEDSTATS_OLD" >"$OUTROOT/sched_schedstats.before"
	echo 1 >"$SCHEDSTAT_SYS"
}

schedstats_restore() {
	if [[ -n ${SCHEDSTATS_OLD:-} ]]; then
		echo "$SCHEDSTATS_OLD" >"$SCHEDSTAT_SYS"
	fi
}

trap schedstats_restore EXIT

# wl cho o read() tren fifo stdin; nanosleep/io cung co the la S nhung wchan khac.
wait_wl_on_read() {
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	die "pid $pid khong cho tren read() (wchan=pipe_read) sau 120 giay"
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 3000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	die "collector khong in READY, xem $log"
}

read_schedstat() {
	local tid=$1
	[[ -r /proc/$tid/schedstat ]] || {
		echo "khong doc duoc /proc/$tid/schedstat"
		return 1
	}
	awk '{print $1, $2, $3}' "/proc/$tid/schedstat"
}

read_sched_fields() {
	local tid=$1 f
	f="/proc/$tid/sched"
	if [[ ! -r $f ]]; then
		echo "khong doc duoc $f"
		return 1
	fi
	if ! grep -q wait_sum "$f" 2>/dev/null; then
		echo "--- nguyen van /proc/$tid/sched (khong co wait_sum) ---"
		cat "$f"
		return 0
	fi
	grep -E 'wait_sum|sum_sleep_runtime|sum_block_runtime|iowait_sum' "$f" || cat "$f"
}

sched_ms_to_ns() {
	# Gia tri trong /proc/<tid>/sched la ms voi 6 chu so thap phan.
	awk -v v="$1" 'BEGIN{printf "%.0f\n", v*1000000}'
}

sched_field_ms() {
	local tid=$1 key=$2
	local line val
	line=$(grep "$key" "/proc/$tid/sched" 2>/dev/null | head -1) || return 1
	val=$(echo "$line" | awk -F: '{gsub(/ /,"",$2); print $2}')
	echo "$val"
}

run_scenario() {
	local name=$1
	shift
	local wl_mode=("$@")
	local ts prefix bin fifo wl_pid cpid stress_pid=0
	ts=$(date +%H%M%S)
	prefix="out/g3-$name-$ts"
	bin="$prefix.bin"
	fifo="$prefix.fifo"
	local ketqua="$OUTROOT/${name}-ketqua.txt"

	echo "=== $name: wl ${wl_mode[*]} (CPU $WL_CPU) ===" | tee "$ketqua"

	mkfifo "$fifo" || die "fifo $fifo"
	exec 9<>"$fifo"

	taskset -c "$WL_CPU" "$WL" "${wl_mode[@]}" <"$fifo" >"$prefix-wl.log" 2>&1 &
	wl_pid=$!
	sleep 0.5
	tid=$wl_pid
	echo "wl pid=$wl_pid tid=$tid" | tee -a "$ketqua"

	if [[ $name == S4 ]]; then
		stress-ng --cpu 1 --taskset "$WL_CPU" --timeout 600 >/dev/null 2>&1 &
		stress_pid=$!
		echo "stress-ng pid=$stress_pid" | tee -a "$ketqua"
	fi

	"$COLLECT" -pid "$wl_pid" -out "$bin" 2>"$prefix-collect.log" &
	cpid=$!
	wait_ready "$prefix-collect.log"

	printf '.' >&9
	wait_wl_on_read "$wl_pid"
	local a_stat a_sched a_wait_ms a_sleep_ms a_block_ms
	a_stat=$(read_schedstat "$tid") || a_stat="?"
	a_sched=$(read_sched_fields "$tid")
	a_wait_ms=$(sched_field_ms "$tid" wait_sum 2>/dev/null || true)
	a_sleep_ms=$(sched_field_ms "$tid" sum_sleep_runtime 2>/dev/null || true)
	a_block_ms=$(sched_field_ms "$tid" sum_block_runtime 2>/dev/null || true)
	echo "--- moc A schedstat (sum_exec_runtime run_delay pcount) ---" | tee -a "$ketqua"
	echo "$a_stat" | tee -a "$ketqua"
	echo "--- moc A /proc/$tid/sched ---" | tee -a "$ketqua"
	echo "$a_sched" | tee -a "$ketqua"

	printf '.' >&9
	wait_wl_on_read "$wl_pid"
	local b_stat b_sched b_wait_ms b_sleep_ms b_block_ms
	b_stat=$(read_schedstat "$tid") || b_stat="?"
	b_sched=$(read_sched_fields "$tid")
	b_wait_ms=$(sched_field_ms "$tid" wait_sum 2>/dev/null || true)
	b_sleep_ms=$(sched_field_ms "$tid" sum_sleep_runtime 2>/dev/null || true)
	b_block_ms=$(sched_field_ms "$tid" sum_block_runtime 2>/dev/null || true)
	echo "--- moc B schedstat ---" | tee -a "$ketqua"
	echo "$b_stat" | tee -a "$ketqua"
	echo "--- moc B /proc/$tid/sched ---" | tee -a "$ketqua"
	echo "$b_sched" | tee -a "$ketqua"

	kill -INT "$cpid" 2>/dev/null
	wait "$cpid" 2>/dev/null
	printf '.' >&9
	exec 9>&-
	wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	[[ $stress_pid -ne 0 ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null

	local t_from t_to
	t_from=$(python3 "$G3WIN" "$bin" "$tid" | head -1) || die "$name: khong tim cua so"
	t_to=$(python3 "$G3WIN" "$bin" "$tid" | tail -1) || die "$name: khong tim cua so"
	echo "cua so ts_enter: ($t_from, $t_to]" | tee -a "$ketqua"

	echo "--- rec-check ---" | tee -a "$ketqua"
	"$RECCHK" -tid "$tid" -from-mono "$t_from" -to-mono "$t_to" "$bin" | tee -a "$ketqua"

	local coll_csi coll_rq coll_vol coll_vol_ds
	coll_csi=$(awk '/^cpu\+steal\+irq /{print $2}' "$ketqua" | tail -1)
	coll_rq=$(awk '/^rq /{print $2; exit}' "$ketqua")
	coll_vol=$(awk '/^vol /{print $2; exit}' "$ketqua")
	coll_vol_ds=$(python3 - "$bin" "$tid" "$t_from" "$t_to" <<'PY'
import struct, sys
path, tid, t0, t1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
D_SLEEP = 1<<2
with open(path,'rb') as f:
    while f.readline().strip()!=b'#END': pass
    s=0
    while True:
        b=f.read(48)
        if len(b)<48: break
        ts=struct.unpack_from('<Q',b,0)[0]
        if ts<=t0 or ts>t1: continue
        if struct.unpack_from('<I',b,16)[0]!=tid: continue
        fl=struct.unpack_from('<H',b,26)[0]
        if fl&D_SLEEP:
            s+=struct.unpack_from('<I',b,44)[0]*1000
    print(s)
PY
)

	local a_exec a_delay b_exec b_delay
	a_exec=$(echo "$a_stat" | awk '{print $1}')
	a_delay=$(echo "$a_stat" | awk '{print $2}')
	b_exec=$(echo "$b_stat" | awk '{print $1}')
	b_delay=$(echo "$b_stat" | awk '{print $2}')
	local d_exec d_delay
	d_exec=$((b_exec - a_exec))
	d_delay=$((b_delay - a_delay))

	local d_wait d_sleep d_block
	if [[ -n $a_wait_ms && -n $b_wait_ms ]]; then
		d_wait=$(sched_ms_to_ns "$(awk -v a="$a_wait_ms" -v b="$b_wait_ms" 'BEGIN{print b-a}')")
	fi
	if [[ -n $a_sleep_ms && -n $b_sleep_ms ]]; then
		d_sleep=$(sched_ms_to_ns "$(awk -v a="$a_sleep_ms" -v b="$b_sleep_ms" 'BEGIN{print b-a}')")
	fi
	if [[ -n $a_block_ms && -n $b_block_ms ]]; then
		d_block=$(sched_ms_to_ns "$(awk -v a="$a_block_ms" -v b="$b_block_ms" 'BEGIN{print b-a}')")
	fi

	echo "--- bang doi chieu ---" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "thanh_phan" "collector" "tham_chieu" "nguon" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "cpu+steal+irq" "${coll_csi:-?}" "${d_exec:-?}" "Delta schedstat field1 sum_exec_runtime" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "rq" "${coll_rq:-?}" "${d_delay:-?}" "Delta schedstat field2 run_delay" | tee -a "$ketqua"
	if [[ -n ${d_wait:-} ]]; then
		printf '%-20s %-15s %-15s %s\n' "rq (wait_sum)" "${coll_rq:-?}" "${d_wait:-?}" "Delta wait_sum /proc/sched" | tee -a "$ketqua"
	fi
	printf '%-20s %-15s %-15s %s\n' "vol" "${coll_vol:-?}" "${d_sleep:-?}" "Delta sum_sleep_runtime" | tee -a "$ketqua"
	if [[ -n ${d_block:-} ]]; then
		printf '%-20s %-15s %-15s %s\n' "vol (D_SLEEP)" "${coll_vol_ds:-?}" "${d_block:-?}" "Delta sum_block_runtime" | tee -a "$ketqua"
	fi

	echo "--- log collector (cuoi) ---" | tee -a "$ketqua"
	tail -30 "$prefix-collect.log" | tee -a "$ketqua"

	cp "$bin.periodic" "$OUTROOT/${name}.bin.periodic" 2>/dev/null || true
	cp "$bin.stats" "$OUTROOT/${name}.bin.stats" 2>/dev/null || true
	echo "luu: $ketqua"
}

part_g_real() {
	local ketqua="$OUTROOT/G-real-ketqua.txt"
	local cid cg bin prefix
	cid=$(docker ps --filter 'name=qdrant' --format '{{.ID}}' | head -1)
	[[ -n $cid ]] || die "khong tim container qdrant"
	cg=$(docker inspect -f '{{.Id}}' "$cid")
	cg="/sys/fs/cgroup/system.slice/docker-${cg}.scope"
	[[ -d $cg ]] || cg=$(find /sys/fs/cgroup -name "*${cid:0:12}*" -type d 2>/dev/null | head -1)
	[[ -d $cg ]] || die "khong tim cgroup cho qdrant"

	prefix=out/g3-greal-$(date +%H%M%S)
	bin="$prefix.bin"
	echo "=== G-real: cgroup qdrant 120s ===" | tee "$ketqua"
	echo "cgroup: $cg" | tee -a "$ketqua"

	mapfile -t pids < <(cat "$cg/cgroup.procs" 2>/dev/null)
	echo "so tien trinh trong cgroup luc bat dau: ${#pids[@]}" | tee -a "$ketqua"

	declare -A a_exec a_delay
	for p in "${pids[@]}"; do
		[[ -r /proc/$p/schedstat ]] || continue
		read -r e d _ < <(read_schedstat "$p")
		a_exec[$p]=$e
		a_delay[$p]=$d
	done

	"$COLLECT" -cgroup "$cg" -duration 120s -out "$bin" 2>"$prefix-collect.log" &
	local cpid=$!
	wait_ready "$prefix-collect.log"
	wait "$cpid"

	mapfile -t pids2 < <(cat "$cg/cgroup.procs" 2>/dev/null)
	declare -A b_exec b_delay
	for p in "${pids2[@]}"; do
		[[ -r /proc/$p/schedstat ]] || continue
		read -r e d _ < <(read_schedstat "$p")
		b_exec[$p]=$e
		b_delay[$p]=$d
	done

	local total_ref_exec=0 total_ref_delay=0
	for p in "${!a_exec[@]}"; do
		[[ -n ${b_exec[$p]:-} ]] || continue
		total_ref_exec=$((total_ref_exec + b_exec[$p] - a_exec[$p]))
		total_ref_delay=$((total_ref_delay + b_delay[$p] - a_delay[$p]))
	done

	echo "--- log collector (cuoi) ---" | tee -a "$ketqua"
	tail -20 "$prefix-collect.log" | tee -a "$ketqua"

	local coll_csi coll_rq coll_vol
	coll_csi=$(python3 - "$bin" <<'PY'
import struct,sys
path=sys.argv[1]
cpu=steal=irq=rq=vol=0
with open(path,'rb') as f:
    while f.readline().strip()!=b'#END': pass
    while True:
        b=f.read(48)
        if len(b)<48: break
        cpu+=struct.unpack_from('<I',b,28)[0]
        steal+=struct.unpack_from('<I',b,32)[0]
        irq+=struct.unpack_from('<I',b,36)[0]
        rq+=struct.unpack_from('<I',b,40)[0]
        vol+=struct.unpack_from('<I',b,44)[0]*1000
print(cpu+steal+irq,rq,vol)
PY
)
	coll_rq=$(echo "$coll_csi" | awk '{print $2}')
	coll_vol=$(echo "$coll_csi" | awk '{print $3}')
	coll_csi=$(echo "$coll_csi" | awk '{print $1}')

	echo "--- bang doi chieu (tong thread song suot cua so) ---" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "thanh_phan" "collector" "tham_chieu" "nguon" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "cpu+steal+irq" "$coll_csi" "$total_ref_exec" "Tong Delta schedstat field1" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "rq" "$coll_rq" "$total_ref_delay" "Tong Delta schedstat field2" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "vol" "$coll_vol" "?" "sum_sleep_runtime: chua tong hop" | tee -a "$ketqua"

	cp "$bin.periodic" "$OUTROOT/G-real.bin.periodic" 2>/dev/null || true
	cp "$bin.stats" "$OUTROOT/G-real.bin.stats" 2>/dev/null || true
}

part_g_irq() {
	local ketqua="$OUTROOT/G-irq-ketqua.txt"
	local prefix bin
	prefix=out/g3-girq-$(date +%H%M%S)
	bin="$prefix.bin"
	echo "=== G-irq: 30 giay may ranh ===" | tee "$ketqua"

	sleep 400 &
	local spid=$!
	"$COLLECT" -pid "$spid" -duration 30s -out "$bin" 2>"$prefix-collect.log" &
	local cpid=$!
	wait_ready "$prefix-collect.log"

	local hard_bcc soft_bcc
	hard_bcc=$(mktemp)
	soft_bcc=$(mktemp)
	/usr/sbin/hardirqs-bpfcc 30 1 >"$hard_bcc" 2>&1 &
	local hb=$!
	/usr/sbin/softirqs-bpfcc 30 1 >"$soft_bcc" 2>&1 &
	local sb=$!
	wait "$cpid"
	wait "$hb" "$sb" 2>/dev/null
	kill "$spid" 2>/dev/null
	wait "$spid" 2>/dev/null

	echo "--- hardirqs-bpfcc (nguyen van) ---" | tee -a "$ketqua"
	cat "$hard_bcc" | tee -a "$ketqua"
	echo "--- softirqs-bpfcc (nguyen van) ---" | tee -a "$ketqua"
	cat "$soft_bcc" | tee -a "$ketqua"
	echo "--- log collector (cuoi) ---" | tee -a "$ketqua"
	tail -25 "$prefix-collect.log" | tee -a "$ketqua"

	local coll_hard coll_soft_raw coll_soft coll_vec
	coll_hard=$(grep '^irq cong don' "$prefix-collect.log" | tail -1 | sed -n 's/.*hard \([0-9]*\).*/\1/p')
	coll_soft=$(grep '^irq cong don' "$prefix-collect.log" | tail -1 | sed -n 's/.*soft \([0-9]*\).*/\1/p')
	coll_vec=$(grep '^irq cong don' "$prefix-collect.log" | tail -1 | sed -n 's/.*vector \([0-9]*\).*/\1/p')
	coll_soft_raw=$(grep '^soft_raw cong don' "$prefix-collect.log" | tail -1 | awk '{print $4}')

	local bcc_hard bcc_soft
	bcc_hard=$(awk '/TOTAL/ {gsub(/,/,"",$2); print $2; exit}' "$hard_bcc")
	bcc_soft=$(awk '/TOTAL/ {gsub(/,/,"",$2); print $2; exit}' "$soft_bcc")

	echo "--- bang doi chieu irq ---" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "loai" "collector" "tham_chieu" "nguon" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "hard" "${coll_hard:-?}" "${bcc_hard:-?}" "hardirqs-bpfcc TOTAL" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "soft_raw" "${coll_soft_raw:-?}" "${bcc_soft:-?}" "softirqs-bpfcc TOTAL" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "soft_excl" "${coll_soft:-?}" "—" "collector (bcc khong tach)" | tee -a "$ketqua"
	printf '%-20s %-15s %-15s %s\n' "vector" "${coll_vec:-?}" "—" "collector only" | tee -a "$ketqua"

	rm -f "$hard_bcc" "$soft_bcc"
	cp "$bin.periodic" "$OUTROOT/G-irq.bin.periodic" 2>/dev/null || true
	cp "$bin.stats" "$OUTROOT/G-irq.bin.stats" 2>/dev/null || true
}

part_g7d() {
	local ketqua="$OUTROOT/G7d-ketqua.txt"
	echo "=== G7d (binary hien tai) ===" | tee "$ketqua"
	bash "$G7" d 1000000 2>&1 | tee -a "$ketqua"
}

main() {
	check_common
	schedstats_save
	run_scenario S1 cpu 10000 300
	run_scenario S2 sleep 5000 500
	run_scenario S3 mixed 2000 3000 500
	run_scenario S4 cpu 10000 300
	run_scenario S5 io 300
	part_g_real
	part_g_irq
	part_g7d
	schedstats_restore
	trap - EXIT
	echo "=== xong g3, du lieu trong $OUTROOT ==="
}

main "$@"
