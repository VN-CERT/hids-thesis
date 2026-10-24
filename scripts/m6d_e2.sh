#!/usr/bin/env bash
# M6d phan B — E2 (steal) voi stress-ng --cpu-method int64 (KHAC m4.sh goc).
# Co che: dung nhu m4.sh e2 (Enter sau moi lan dat CPU limit tren vCenter,
# muc Unlimited / 36000 / 24000 / 12000 MHz, do steal VM 10s bang /proc/stat).
# Them: 3 lan/muc, -pmu on, freq_stamp, giu .bin + TSV, huong dan tieng Viet.
# Chay: sudo bash scripts/m6d_e2.sh
# Neu ngat giua chung: in nhac DAT LAI UNLIMITED va ghi trang thai do dang.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:-validation/m6d-$(date +%Y%m%d)}"
mkdir -p "$OUTROOT/E2" out out/jobs
WL=./bin/wl
COLLECT=./bin/hids-collect
EXPORT=./bin/rec-export
STEAL_PROBE=./bin/steal-probe
LOOPS_FILE=out/m4-loops.txt
WL_CPU=20
RUNS=3
STATUS=out/jobs/m6d-e2.status
LOG=out/jobs/m6d-e2.log

E2_STRESS_PID=""
E2_PROBE_PID=""
RUNNING=()
INTERRUPTED=0
CURRENT_LEVEL=""

write_status() {
	local st=$1
	{
		echo "ten=m6d-e2"
		echo "bat_dau=${START_TS:-}"
		echo "cap_nhat=$(date -Iseconds)"
		echo "trang_thai=$st"
		echo "muc_hien_tai=${CURRENT_LEVEL:-}"
		echo "outroot=$OUTROOT"
		echo "log=$LOG"
	} >"$STATUS"
}

remind_unlimited() {
	echo ""
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
	echo "DAT LAI UNLIMITED cho VM 55.195-Test-NB tren vCenter NGAY." >&2
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
	echo "trang_thai_do_dang=$OUTROOT/E2/do-dang.txt" >&2
	{
		echo "ngat_luc=$(date -Iseconds)"
		echo "muc_dang_lam=${CURRENT_LEVEL:-chua_ro}"
		echo "can_dat_lai=Unlimited"
		echo "VM=55.195-Test-NB"
	} >"$OUTROOT/E2/do-dang.txt"
}

cleanup() {
	local rc=$?
	e2_probe_stop
	e2_stress_stop
	if [[ $INTERRUPTED -eq 1 || $rc -ne 0 ]]; then
		remind_unlimited
		write_status "failed"
	fi
	if ((${#RUNNING[@]})); then
		docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
	fi
}
on_int() {
	INTERRUPTED=1
	remind_unlimited
	write_status "failed"
	exit 130
}
trap cleanup EXIT
trap on_int INT TERM

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "KHONG_READY (cho 20s)" >&2
	return 1
}
wait_wl_read() {
	local pid=$1 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		[[ $w == pipe_read ]] && return 0
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	return 1
}
read_burn_loops() { awk '/^burn_loops/{print $2}' "$LOOPS_FILE"; }

vm_cpu_jiffies() {
	awk '/^cpu / {for (i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n")}' /proc/stat
}
measure_vm_steal_pct_10s() {
	local a b
	a=$(vm_cpu_jiffies)
	sleep 10
	b=$(vm_cpu_jiffies)
	python3 - "$a" "$b" <<'PY'
import sys
def d(s):
    return [int(x) for x in s.split()]
a, b = d(sys.argv[1]), d(sys.argv[2])
if len(a) != len(b) or len(a) < 8:
    print("0.000"); sys.exit(0)
da = [b[i] - a[i] for i in range(len(a))]
total = sum(da); steal = da[7]
print("0.000" if total <= 0 else f"{100.0 * steal / total:.3f}")
PY
}

e2_stress_start() {
	# KHAC m4.sh: them --cpu-method int64
	echo "m6d E2: bat stress-ng --cpu 22 --cpu-method int64 --taskset 0-19,22-23 (KHAC m4.sh goc)" | tee -a "$LOG"
	stress-ng --cpu 22 --cpu-method int64 --taskset 0-19,22-23 --timeout 7200 >/dev/null 2>&1 &
	E2_STRESS_PID=$!
	sleep 2
}
e2_stress_stop() {
	[[ -n $E2_STRESS_PID ]] && kill "$E2_STRESS_PID" 2>/dev/null
	[[ -n $E2_STRESS_PID ]] && wait "$E2_STRESS_PID" 2>/dev/null || true
	E2_STRESS_PID=""
}
e2_probe_start() {
	local probe_csv=$1
	"$STEAL_PROBE" -interval 1s -out "$probe_csv" >/dev/null 2>"$OUTROOT/E2/steal-probe.log" &
	E2_PROBE_PID=$!
	sleep 1
}
e2_probe_stop() {
	[[ -n $E2_PROBE_PID ]] && kill -INT "$E2_PROBE_PID" 2>/dev/null
	[[ -n $E2_PROBE_PID ]] && wait "$E2_PROBE_PID" 2>/dev/null || true
	E2_PROBE_PID=""
}

e2_wait_steal_ok() {
	local label=$1 need_limit=$2 pct
	while true; do
		echo "Dang do steal VM 10 giay bang /proc/stat (stress dang chay)..." >&2
		pct=$(measure_vm_steal_pct_10s)
		echo "vm_steal_pct=${pct}% (muc $label)" >&2
		if [[ "$need_limit" == "0" ]]; then
			echo "$pct"
			return 0
		fi
		if awk -v p="$pct" 'BEGIN{exit !(p+0 >= 5.0)}'; then
			echo "$pct"
			return 0
		fi
		echo "CANH BAO: limit chua co hieu luc (can >= 5%). Kiem tra lai vCenter roi bam Enter." >&2
		read -r
	done
}

run_wl_mixed_pmu() {
	local loops=$1 rounds=$2 pmu=$3 outdir=$4
	local attempt prefix fifo wl_pid cpid bin
	for attempt in 1 2 3; do
		prefix="$outdir/wl-$(date +%H%M%S)-$attempt"
		fifo="$prefix.fifo"
		bin="$prefix.bin"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		taskset -c "$WL_CPU" "$WL" -loops "$loops" mixed "$rounds" <"$fifo" >"$prefix-wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.5
		"$COLLECT" -pid "$wl_pid" -pmu "$pmu" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		if ! wait_ready "$prefix-collect.log"; then
			echo "KHONG_READY" >>"$prefix-collect.log"
			kill "$wl_pid" "$cpid" 2>/dev/null; wait "$wl_pid" 2>/dev/null || true
			exec 9>&-; rm -f "$fifo"
			continue
		fi
		printf '.\n' >&9
		wait_wl_read "$wl_pid" || true
		printf '.\n' >&9
		wait "$wl_pid" 2>/dev/null || true
		printf '.\n' >&9
		wait "$cpid" 2>/dev/null || true
		exec 9>&-
		rm -f "$fifo"
		echo "$bin|$wl_pid|$attempt"
		return 0
	done
	return 1
}

analyze_burn() {
	local csv=$1 tid=$2 out=$3
	python3 - "$csv" "$tid" "$out" <<'PY'
import csv, statistics, sys
from collections import Counter
path, tid, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) != tid: continue
        if int(r["flags"]) & 1: continue
        rows.append(r)
cnt = Counter(int(r["syscall_nr"]) for r in rows)
burn_nr = 230 if cnt.get(230, 0) >= cnt.get(35, 0) else 35
burn = [r for r in rows if int(r["syscall_nr"]) == burn_nr]
ok = [r for r in burn if int(r["pmu_ok"]) == 1]
def med(xs):
    return statistics.median(xs) if xs else float("nan")
cpu = [int(r["cpu_ns"]) for r in burn]
rq = [int(r["rq_ns"]) for r in burn]
steal = [int(r["steal_ns"]) for r in burn]
irq = [int(r["irq_ns"]) for r in burn]
vol_us = [int(r["vol_ns"]) // 1000 for r in burn]
off = [int(r["steal_off_ns"]) for r in burn]
inst = [int(r["inst"]) for r in ok]
cyc = [int(r["cyc"]) for r in ok]
cpi = [c / i for c, i in zip(cyc, inst) if i > 0]
lines = [
    f"burn_nr={burn_nr} so_khoang={len(burn)} so_pmu={len(ok)}",
    f"cpu_ns={med(cpu):.1f}",
    f"rq_ns={med(rq):.1f}",
    f"steal_ns={med(steal):.1f}",
    f"irq_ns={med(irq):.1f}",
    f"vol_us={med(vol_us):.1f}",
    f"steal_off_ns={med(off):.1f}",
    f"inst={med(inst):.1f}" if ok else "inst=na",
    f"cyc={med(cyc):.1f}" if ok else "cyc=na",
    f"CPI={med(cpi):.4f}" if cpi else "CPI=na",
]
open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY
}

freq_pair() {
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/E2/freq-${tag}-truoc.txt" 2>&1
	FREQ_BEFORE=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/E2/freq-${tag}-truoc.txt")
}
freq_after() {
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/E2/freq-${tag}-sau.txt" 2>&1
	FREQ_AFTER=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/E2/freq-${tag}-sau.txt")
	python3 - "$FREQ_BEFORE" "$FREQ_AFTER" "$tag" <<'PY' | tee -a "$OUTROOT/E2/freq-lech.txt"
import sys
a, b, tag = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
lech = abs(b - a) / a * 100 if a else float("nan")
note = " LECH_>2%" if lech > 2 else ""
print(f"freq {tag}: truoc={a:.4f} sau={b:.4f} lech={lech:.2f}%{note}")
PY
}

calibrate() {
	local fifo wl_pid
	fifo=$(mktemp -u)
	mkfifo "$fifo" || return 1
	echo "m6d E2: hieu chuan wl tren CPU $WL_CPU..." | tee -a "$LOG"
	taskset -c "$WL_CPU" "$WL" mixed 1 <"$fifo" >"$OUTROOT/E2/cal-wl.log" 2>&1 &
	wl_pid=$!
	sleep 3
	[[ -s $LOOPS_FILE ]] || { echo "hieu chuan that bai" >&2; return 1; }
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	echo "burn_loops=$(read_burn_loops)" | tee -a "$LOG"
}

# Muc dung nhu m4.sh: Unlimited, 36000, 24000, 12000 MHz
LEVELS=(
	"Unlimited|Unlimited|0"
	"36000|36000 MHz|1"
	"24000|24000 MHz|1"
	"12000|12000 MHz|1"
)

START_TS=$(date -Iseconds)
write_status "running"
: >"$LOG"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "m6d E2: dung ${#RUNNING[@]} container..." | tee -a "$LOG"
if ((${#RUNNING[@]})); then
	docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true
fi
echo "${RUNNING[*]}" >"$OUTROOT/E2/containers-stopped.txt"

cat <<'EOF' | tee -a "$LOG"
=== M6d E2 (can nguoi o vCenter) ===
VM: 55.195-Test-NB
Muc limit (dung m4.sh): Unlimited, 36000 MHz, 24000 MHz, 12000 MHz, roi Unlimited lai.
stress-ng co-runner: --cpu 22 --cpu-method int64 --taskset 0-19,22-23
  (KHAC m4.sh goc: m4.sh KHONG co --cpu-method int64)
Moi muc: 3 lan do; moi muc do steal VM 10s bang /proc/stat truoc khi chay wl.
EOF

calibrate || exit 1
probe_csv="$OUTROOT/E2/steal-probe.csv"
e2_stress_start
e2_probe_start "$probe_csv"

for entry in "${LEVELS[@]}"; do
	IFS='|' read -r label limit_msg need_limit <<<"$entry"
	CURRENT_LEVEL=$label
	write_status "running"
	echo ""
	echo "============================================================"
	echo "Bây giờ đặt CPU limit = ${limit_msg} cho VM 55.195-Test-NB trên vCenter rồi bấm Enter"
	echo "============================================================"
	read -r

	pct=$(e2_wait_steal_ok "$label" "$need_limit")
	echo "$pct" >"$OUTROOT/E2/${label}.vm_steal_pct"
	echo "E2 ${label} vm_steal_pct_check=${pct}%" | tee -a "$OUTROOT/E2/steal.log"

	freq_pair "E2-$label" "$WL_CPU"
	loops=$(read_burn_loops)
	for run in $(seq 1 "$RUNS"); do
		dir="$OUTROOT/E2/$label/run$run"
		mkdir -p "$dir"
		result=$(run_wl_mixed_pmu "$loops" 500 on "$dir") || {
			echo "E2 $label run$run THAT BAI" | tee -a "$OUTROOT/E2/errors.txt"
			continue
		}
		bin=${result%%|*}; rest=${result#*|}; tid=${rest%%|*}; attempt=${rest##*|}
		cp "$bin" "$dir/collect.bin"
		"$EXPORT" "$bin" >"$dir/export.csv"
		analyze_burn "$dir/export.csv" "$tid" "$dir/ketqua.txt" | tee "$dir/ketqua.tee"
		{
			echo "vm_steal_pct=$pct"
			echo "GHz_wall_truoc=$FREQ_BEFORE"
			echo "so_attempt=$attempt"
			echo "cpu_method=int64"
		} >>"$dir/ketqua.txt"
		echo "E2 $label run=$run attempt=$attempt" | tee -a "$OUTROOT/E2/progress.txt"
	done
	freq_after "E2-$label" "$WL_CPU"
	{
		echo "GHz_wall_truoc=$FREQ_BEFORE"
		echo "GHz_wall_sau=$FREQ_AFTER"
		echo "vm_steal_pct=$pct"
	} >"$OUTROOT/E2/$label/freq.txt"
done

echo ""
echo "============================================================"
echo "Đặt lại Unlimited rồi bấm Enter"
echo "============================================================"
CURRENT_LEVEL="Unlimited-cuoi"
read -r

echo "Kiem steal ve ≈ 0 (can < 1%)..."
final_pct=$(measure_vm_steal_pct_10s)
echo "vm_steal_pct_sau_Unlimited=${final_pct}%" | tee -a "$OUTROOT/E2/steal.log"
echo "$final_pct" >"$OUTROOT/E2/Unlimited-cuoi.vm_steal_pct"
if awk -v p="$final_pct" 'BEGIN{exit !(p+0 < 1.0)}'; then
	echo "Steal da ve ≈ 0 (ok)."
else
	echo "CANH BAO: steal con ${final_pct}% — kiem tra Unlimited tren vCenter, bam Enter de do lai."
	read -r
	final_pct=$(measure_vm_steal_pct_10s)
	echo "vm_steal_pct_sau_Unlimited_lan2=${final_pct}%" | tee -a "$OUTROOT/E2/steal.log"
fi

e2_probe_stop
e2_stress_stop
rm -f "$OUTROOT/E2/do-dang.txt"
CURRENT_LEVEL=""
write_status "done"
echo "m6d E2 xong: $OUTROOT/E2"
trap - EXIT INT TERM
if ((${#RUNNING[@]})); then
	docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
fi
exit 0
