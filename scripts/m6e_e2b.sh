#!/usr/bin/env bash
# M6e-E2b — ban sao scripts/m6d_e2.sh, khac dung ba diem:
#  (1) wl: taskset -c 20 ./bin/wl -loops <burn_loops> cpu 10000 1500 (dot lien tuc, marker getppid)
#  (2) collector: taskset -c 21 -pmu on
#  (3) oracle /proc/stat cpu20 + cpu truoc/sau moi luot; so tong steal_ns+steal_off_ns
# Khong sua scripts/m6d_e2.sh.
# Chay: sudo bash scripts/m6e_e2b.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:-validation/m6e-$(date +%Y%m%d)}"
mkdir -p "$OUTROOT/E2b" out out/jobs
WL=./bin/wl
COLLECT=./bin/hids-collect
EXPORT=./bin/rec-export
STEAL_PROBE=./bin/steal-probe
LOOPS_FILE=out/m4-loops.txt
WL_CPU=20
COLLECT_CPU=21
RUNS=3
ROUNDS=1500
X_US=10000
GETPPID_NR=110
STATUS=out/jobs/m6e-e2b.status
LOG=out/jobs/m6e-e2b.log

E2_STRESS_PID=""
E2_PROBE_PID=""
RUNNING=()
INTERRUPTED=0
CURRENT_LEVEL=""

write_status() {
	local st=$1
	{
		echo "ten=m6e-e2b"
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
	echo "trang_thai_do_dang=$OUTROOT/E2b/do-dang.txt" >&2
	{
		echo "ngat_luc=$(date -Iseconds)"
		echo "muc_dang_lam=${CURRENT_LEVEL:-chua_ro}"
		echo "can_dat_lai=Unlimited"
		echo "VM=55.195-Test-NB"
	} >"$OUTROOT/E2b/do-dang.txt"
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

# Dong cpu / cpuN: cot steal = truong thu 8 (index 7) sau nhan.
read_stat_line() {
	local name=$1
	awk -v n="$name" '($1 == n) {for (i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n"); exit}' /proc/stat
}
steal_jiffies_from_line() {
	# stdin: cac cot so cua dong cpu
	awk '{print $8+0}'
}
jiffies_to_ns() {
	# USER_HZ=100 → 1 jiffy = 10 ms = 1e7 ns
	local j=$1
	echo $((j * 10000000))
}

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
	echo "m6e E2b: bat stress-ng --cpu 22 --cpu-method int64 --taskset 0-19,22-23" | tee -a "$LOG"
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
	"$STEAL_PROBE" -interval 1s -out "$probe_csv" >/dev/null 2>"$OUTROOT/E2b/steal-probe.log" &
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

# (1)+(2): wl cpu 10000 1500 tren CPU 20; collector taskset -c 21 -pmu on
run_wl_cpu_pmu() {
	local loops=$1 pmu=$2 outdir=$3
	local attempt prefix fifo wl_pid cpid bin
	local st20_a st_vm_a st20_b st_vm_b
	for attempt in 1 2 3; do
		prefix="$outdir/wl-$(date +%H%M%S)-$attempt"
		fifo="$prefix.fifo"
		bin="$prefix.bin"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		# Oracle truoc wl (sau khi gan fifo, truoc go)
		st20_a=$(read_stat_line "cpu${WL_CPU}" | steal_jiffies_from_line)
		st_vm_a=$(read_stat_line "cpu" | steal_jiffies_from_line)
		echo "oracle_truoc cpu${WL_CPU}_steal_jiffies=$st20_a cpu_steal_jiffies=$st_vm_a" >"$prefix.oracle-truoc.txt"

		taskset -c "$WL_CPU" "$WL" -loops "$loops" cpu "$X_US" "$ROUNDS" <"$fifo" >"$prefix-wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.5
		taskset -c "$COLLECT_CPU" "$COLLECT" -pid "$wl_pid" -pmu "$pmu" -duration 90s -out "$bin" 2>"$prefix-collect.log" &
		cpid=$!
		if ! wait_ready "$prefix-collect.log"; then
			echo "KHONG_READY" >>"$prefix-collect.log"
			kill "$wl_pid" "$cpid" 2>/dev/null; wait "$wl_pid" 2>/dev/null || true
			exec 9>&-; rm -f "$fifo"
			continue
		fi
		# Doc lai oracle ngay truoc khi go (sau READY) — chinh xac hon cho cua so wl
		st20_a=$(read_stat_line "cpu${WL_CPU}" | steal_jiffies_from_line)
		st_vm_a=$(read_stat_line "cpu" | steal_jiffies_from_line)
		echo "oracle_truoc cpu${WL_CPU}_steal_jiffies=$st20_a cpu_steal_jiffies=$st_vm_a" >"$prefix.oracle-truoc.txt"

		printf '.\n' >&9
		wait_wl_read "$wl_pid" || true
		printf '.\n' >&9
		wait "$wl_pid" 2>/dev/null || true
		# Oracle sau wl (truoc khi cho collector ket thuc)
		st20_b=$(read_stat_line "cpu${WL_CPU}" | steal_jiffies_from_line)
		st_vm_b=$(read_stat_line "cpu" | steal_jiffies_from_line)
		{
			echo "oracle_sau cpu${WL_CPU}_steal_jiffies=$st20_b cpu_steal_jiffies=$st_vm_b"
			echo "steal_delta_jiffies_cpu${WL_CPU}=$((st20_b - st20_a))"
			echo "steal_delta_jiffies_vm=$((st_vm_b - st_vm_a))"
			echo "steal_delta_ns_cpu${WL_CPU}=$(jiffies_to_ns $((st20_b - st20_a)))"
			echo "steal_delta_ns_vm=$(jiffies_to_ns $((st_vm_b - st_vm_a)))"
		} >"$prefix.oracle-sau.txt"
		printf '.\n' >&9
		wait "$cpid" 2>/dev/null || true
		exec 9>&-
		rm -f "$fifo"
		# Ghi oracle tong hop
		{
			cat "$prefix.oracle-truoc.txt"
			cat "$prefix.oracle-sau.txt"
		} >"$prefix.oracle.txt"
		echo "$bin|$wl_pid|$attempt|$prefix"
		return 0
	done
	return 1
}

# Phan tich marker getppid (S1) + oracle
analyze_e2b() {
	local csv=$1 tid=$2 out=$3 oracle=$4
	python3 - "$csv" "$tid" "$out" "$oracle" "$GETPPID_NR" <<'PY'
import csv, statistics, sys
path, tid, out, oracle_path, marker_nr = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], int(sys.argv[5])
rows_all = []
with open(path) as f:
    for r in csv.DictReader(f):
        if int(r["tid"]) != tid:
            continue
        rows_all.append(r)
rows_all.sort(key=lambda r: int(r["ts_enter"]))
# Tong steal moi ban ghi wl
sum_steal = 0
sum_off = 0
for r in rows_all:
    sum_steal += int(r["steal_ns"])
    sum_off += int(r["steal_off_ns"])
sum_hids = sum_steal + sum_off

# Khoang dot = marker getppid (khong FIRST)
markers = []
for i, r in enumerate(rows_all):
    if int(r["flags"]) & 1:
        continue
    if int(r["syscall_nr"]) != marker_nr:
        continue
    if i == 0:
        continue
    dt = int(r["ts_enter"]) - int(rows_all[i - 1]["ts_enter"])
    cpu = int(r["cpu_ns"]); steal = int(r["steal_ns"]); irq = int(r["irq_ns"])
    rq = int(r["rq_ns"]); vol = int(r["vol_ns"]); off = int(r["steal_off_ns"])
    tong = cpu + steal + irq + rq + vol
    phan = dt - tong
    pmu = int(r["pmu_ok"]) == 1
    inst = int(r["inst"]); cyc = int(r["cyc"])
    markers.append(dict(dt=dt, cpu=cpu, steal=steal, irq=irq, rq=rq, vol=vol, off=off,
                        tong=tong, phan=phan, pmu=pmu, inst=inst, cyc=cyc))

def med(xs):
    return statistics.median(xs) if xs else float("nan")

dts = [m["dt"] for m in markers]
cpus = [m["cpu"] for m in markers]
steals = [m["steal"] for m in markers]
rqs = [m["rq"] for m in markers]
offs = [m["off"] for m in markers]
phans = [m["phan"] for m in markers]
ok = [m for m in markers if m["pmu"] and m["inst"] > 0]
cpi = [m["cyc"] / m["inst"] for m in ok]
ghz = [m["cyc"] / m["cpu"] for m in ok if m["cpu"] > 0]

oracle = {}
if oracle_path:
    for line in open(oracle_path):
        line = line.strip()
        if "=" in line:
            k, v = line.split("=", 1)
            oracle[k.strip()] = v.strip()

ns20 = int(oracle.get("steal_delta_ns_cpu20", oracle.get("steal_delta_ns_cpu20", "0") or "0"))
# key may be steal_delta_ns_cpu20 from script
for k, v in list(oracle.items()):
    if k.startswith("steal_delta_ns_cpu") and "vm" not in k:
        ns20 = int(v)
ns_vm = int(oracle.get("steal_delta_ns_vm", "0") or "0")

def ratio(a, b):
    if b == 0:
        return "na" if a == 0 else "inf"
    return f"{a / b:.6f}"

lines = [
    f"marker_nr={marker_nr} so_khoang={len(markers)} so_pmu={len(ok)} so_ban_ghi_wl={len(rows_all)}",
    f"dt_ns={med(dts):.1f}",
    f"cpu_ns={med(cpus):.1f}",
    f"steal_ns={med(steals):.1f}",
    f"rq_ns={med(rqs):.1f}",
    f"steal_off_ns={med(offs):.1f}",
    f"phan_du_ns={med(phans):.1f}",
    f"phan_du_max_ns={max(phans) if phans else float('nan'):.1f}",
    f"CPI={med(cpi):.4f}" if cpi else "CPI=na",
    f"GHz={med(ghz):.4f}" if ghz else "GHz=na",
    f"sum_steal_ns={sum_steal}",
    f"sum_steal_off_ns={sum_off}",
    f"sum_hids_steal_plus_off_ns={sum_hids}",
    f"oracle_steal_delta_ns_cpu20={ns20}",
    f"oracle_steal_delta_ns_vm={ns_vm}",
    f"ti_le_hids_tren_cpu20={ratio(sum_hids, ns20)}",
    f"ti_le_hids_tren_vm={ratio(sum_hids, ns_vm)}",
]
# oracle raw
for k in sorted(oracle):
    lines.append(f"oracle_{k}={oracle[k]}" if not k.startswith("oracle_") else f"{k}={oracle[k]}")

open(out, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
# Dong doi chieu oracle (in rieng)
print(f"ORACLE cpu20_steal_delta_ns={ns20} vm_steal_delta_ns={ns_vm} "
      f"hids_sum_steal+off_ns={sum_hids} ti_le_hids/cpu20={ratio(sum_hids, ns20)} "
      f"ti_le_hids/vm={ratio(sum_hids, ns_vm)}")
PY
}

freq_pair() {
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/E2b/freq-${tag}-truoc.txt" 2>&1
	FREQ_BEFORE=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/E2b/freq-${tag}-truoc.txt")
}
freq_after() {
	local tag=$1 cpu=$2
	bash scripts/freq_stamp.sh "$cpu" >"$OUTROOT/E2b/freq-${tag}-sau.txt" 2>&1
	FREQ_AFTER=$(awk -F= '/trung vi GHz_wall/{print $2}' "$OUTROOT/E2b/freq-${tag}-sau.txt")
	python3 - "$FREQ_BEFORE" "$FREQ_AFTER" "$tag" <<'PY' | tee -a "$OUTROOT/E2b/freq-lech.txt"
import sys
a, b, tag = float(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
lech = abs(b - a) / a * 100 if a else float("nan")
note = " LECH_>2%" if lech > 2 else ""
print(f"freq {tag}: truoc={a:.4f} sau={b:.4f} lech={lech:.2f}%{note}")
PY
}

calibrate() {
	local fifo wl_pid
	if [[ -s $LOOPS_FILE ]] && [[ -n $(read_burn_loops) ]]; then
		echo "m6e E2b: dung burn_loops co san=$(read_burn_loops)" | tee -a "$LOG"
		return 0
	fi
	fifo=$(mktemp -u)
	mkfifo "$fifo" || return 1
	echo "m6e E2b: hieu chuan wl tren CPU $WL_CPU..." | tee -a "$LOG"
	taskset -c "$WL_CPU" "$WL" mixed 1 <"$fifo" >"$OUTROOT/E2b/cal-wl.log" 2>&1 &
	wl_pid=$!
	sleep 3
	[[ -s $LOOPS_FILE ]] || { echo "hieu chuan that bai" >&2; return 1; }
	kill "$wl_pid" 2>/dev/null; wait "$wl_pid" 2>/dev/null
	rm -f "$fifo"
	echo "burn_loops=$(read_burn_loops)" | tee -a "$LOG"
}

LEVELS=(
	"Unlimited|Unlimited|0"
	"36000|36000 MHz|1"
	"24000|24000 MHz|1"
	"12000|12000 MHz|1"
)

START_TS=$(date -Iseconds)
write_status "running"
: >"$LOG"
: >"$OUTROOT/E2b/bang.tsv"
echo -e "muc\trun\tmed_dt_ns\tmed_cpu_ns\tmed_steal_ns\tmed_rq_ns\tmed_steal_off_ns\tCPI\tGHz\tmed_phan_du_ns\toracle_cpu20_ns\toracle_vm_ns\thids_sum_ns\tti_le_hids_cpu20" >"$OUTROOT/E2b/bang.tsv"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "m6e E2b: dung ${#RUNNING[@]} container..." | tee -a "$LOG"
if ((${#RUNNING[@]})); then
	docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true
fi
echo "${RUNNING[*]}" >"$OUTROOT/E2b/containers-stopped.txt"

cat <<EOF | tee -a "$LOG"
=== M6e E2b (can nguoi o vCenter) ===
VM: 55.195-Test-NB
Muc: Unlimited, 36000, 24000, 12000 MHz
wl: taskset -c $WL_CPU $WL -loops <burn_loops> cpu $X_US $ROUNDS  (dot lien tuc, marker getppid)
collector: taskset -c $COLLECT_CPU -pmu on
stress-ng: --cpu 22 --cpu-method int64 --taskset 0-19,22-23
freq_stamp: CPU $WL_CPU truoc/sau moi muc
EOF

calibrate || exit 1
probe_csv="$OUTROOT/E2b/steal-probe.csv"
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
	echo "$pct" >"$OUTROOT/E2b/${label}.vm_steal_pct"
	echo "E2b ${label} vm_steal_pct_check=${pct}%" | tee -a "$OUTROOT/E2b/steal.log"

	freq_pair "E2b-$label" "$WL_CPU"
	loops=$(read_burn_loops)
	for run in $(seq 1 "$RUNS"); do
		dir="$OUTROOT/E2b/$label/run$run"
		mkdir -p "$dir"
		result=$(run_wl_cpu_pmu "$loops" on "$dir") || {
			echo "E2b $label run$run THAT BAI" | tee -a "$OUTROOT/E2b/errors.txt"
			continue
		}
		bin=${result%%|*}; rest=${result#*|}; tid=${rest%%|*}; rest2=${rest#*|}; attempt=${rest2%%|*}; prefix=${rest2#*|}
		cp "$bin" "$dir/collect.bin"
		cp "$prefix.oracle.txt" "$dir/oracle.txt" 2>/dev/null || true
		"$EXPORT" "$bin" >"$dir/export.csv"
		analyze_e2b "$dir/export.csv" "$tid" "$dir/ketqua.txt" "$dir/oracle.txt" | tee "$dir/ketqua.tee"
		{
			echo "vm_steal_pct=$pct"
			echo "GHz_wall_truoc=$FREQ_BEFORE"
			echo "so_attempt=$attempt"
			echo "cpu_method=int64"
			echo "wl=taskset -c $WL_CPU $WL -loops $loops cpu $X_US $ROUNDS"
			echo "collect=taskset -c $COLLECT_CPU"
		} >>"$dir/ketqua.txt"
		# Dong bang
		python3 - "$dir/ketqua.txt" "$label" "$run" >>"$OUTROOT/E2b/bang.tsv" <<'PY'
import sys
kq={}
for line in open(sys.argv[1]):
    if "=" in line:
        k,v=line.strip().split("=",1); kq[k]=v
lv, run = sys.argv[2], sys.argv[3]
print("\t".join([
    lv, run,
    kq.get("dt_ns","na"), kq.get("cpu_ns","na"), kq.get("steal_ns","na"),
    kq.get("rq_ns","na"), kq.get("steal_off_ns","na"),
    kq.get("CPI","na"), kq.get("GHz","na"), kq.get("phan_du_ns","na"),
    kq.get("oracle_steal_delta_ns_cpu20","na"),
    kq.get("oracle_steal_delta_ns_vm","na"),
    kq.get("sum_hids_steal_plus_off_ns","na"),
    kq.get("ti_le_hids_tren_cpu20","na"),
]))
PY
		echo "E2b $label run=$run attempt=$attempt" | tee -a "$OUTROOT/E2b/progress.txt"
	done
	freq_after "E2b-$label" "$WL_CPU"
	{
		echo "GHz_wall_truoc=$FREQ_BEFORE"
		echo "GHz_wall_sau=$FREQ_AFTER"
		echo "vm_steal_pct=$pct"
	} >"$OUTROOT/E2b/$label/freq.txt"
done

echo ""
echo "============================================================"
echo "Đặt lại Unlimited rồi bấm Enter"
echo "============================================================"
CURRENT_LEVEL="Unlimited-cuoi"
read -r

echo "Kiem steal ve ≈ 0 (can < 1%)..."
final_pct=$(measure_vm_steal_pct_10s)
echo "vm_steal_pct_sau_Unlimited=${final_pct}%" | tee -a "$OUTROOT/E2b/steal.log"
echo "$final_pct" >"$OUTROOT/E2b/Unlimited-cuoi.vm_steal_pct"
if awk -v p="$final_pct" 'BEGIN{exit !(p+0 < 1.0)}'; then
	echo "Steal da ve ≈ 0 (ok)."
else
	echo "CANH BAO: steal con ${final_pct}% — kiem tra Unlimited tren vCenter, bam Enter de do lai."
	read -r
	final_pct=$(measure_vm_steal_pct_10s)
	echo "vm_steal_pct_sau_Unlimited_lan2=${final_pct}%" | tee -a "$OUTROOT/E2b/steal.log"
fi

e2_probe_stop
e2_stress_stop
rm -f "$OUTROOT/E2b/do-dang.txt"
CURRENT_LEVEL=""
write_status "done"
echo "m6e E2b xong: $OUTROOT/E2b"
echo "bang: $OUTROOT/E2b/bang.tsv"
trap - EXIT INT TERM
if ((${#RUNNING[@]})); then
	docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
fi
exit 0
