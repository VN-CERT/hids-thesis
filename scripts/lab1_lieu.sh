#!/usr/bin/env bash
# lab1_lieu.sh — bo lieu D1/D3/D4 + E5 (LAB-1 buoc 3). Phu luc 1.2.
# LAB1_ONLY=d3d4e5 — chi chay lai D3/D4/E5 (giu D1).
# Container lab0-* DUNG truoc khi chay, khoi dong lai sau.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:?can thu muc output validation/lab1-<ngay>/lieu}"
mkdir -p "$OUTROOT" out lab /root/hids/out
NHAN="${LAB1_NHAN_LIEU:-lab/nhan-lieu.tsv}"
WL=./bin/wl
COLLECT=./bin/hids-collect
STATS=./scripts/lab1_lieu_stats.py
LOOPS_FILE=/root/hids/out/m4-loops.txt
WL_CPU=0
FAIL=0
ONLY="${LAB1_ONLY:-all}"  # all | d3d4e5
BURN_LOOPS=""
MEM_STEPS=""
# phu luc 1.4: muc D3 (GIU {0,2,4,7} khi other_busy L7 < 1%)
D3_LEVELS="${LAB1_D3_LEVELS:-0 2 4 7}"
COLLECT_CPUS="${LAB1_COLLECT_CPUS:-1-7}"

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

# Phu luc 1.4: day user.slice ra CPU 1-7 (runtime)
sanitize_cpu0() {
	systemctl set-property --runtime user.slice AllowedCPUs=1-7
	local eff
	eff=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)
	echo "sanitize_cpu0: user.slice cpuset.cpus.effective=$eff" | tee -a "$OUTROOT/lieu.log"
	echo "$eff" >"$OUTROOT/cpuset-effective.txt"
	[[ $eff == 1-7 ]] || { echo "FAIL: cpuset.effective=$eff (can 1-7)" >&2; exit 1; }
}

# wl tren CPU 0 phai chay trong system.slice (user.slice bi AllowedCPUs=1-7)
# Dat bien toan cuc WL_PID + WL_SCOPE_PID (KHONG dung $(...) — mat bien).
start_wl_cpu0() {
	# start_wl_cpu0 <fifo> <wl.log> <args...>
	local fifo=$1 wlog=$2
	shift 2
	local unit="lab1-wl-$(date +%s%N)" i
	WL_PID=""
	WL_SCOPE_PID=""
	systemd-run --scope --quiet --slice=system.slice \
		--working-directory="$(pwd)" --unit="$unit" \
		-- /bin/bash -c "exec taskset -c 0 ./bin/wl $*" \
		<"$fifo" >"$wlog" 2>&1 &
	WL_SCOPE_PID=$!
	for ((i = 0; i < 100; i++)); do
		WL_PID=$(pgrep -n -f './bin/wl' 2>/dev/null || true)
		[[ -n $WL_PID ]] && kill -0 "$WL_PID" 2>/dev/null && break
		WL_PID=""
		sleep 0.05
	done
}

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	echo "KHONG_READY (cho 20s)" >&2
	return 1
}

wait_wchan() {
	local pid=$1 want=$2 i w
	for ((i = 0; i < 12000; i++)); do
		w=$(cat "/proc/$pid/wchan" 2>/dev/null) || return 1
		if [[ $want == eq && $w == pipe_read ]]; then return 0; fi
		if [[ $want == ne && $w != pipe_read ]]; then return 0; fi
		kill -0 "$pid" 2>/dev/null || return 1
		sleep 0.01
	done
	return 1
}

ensure_nhan_header() {
	if [[ ! -f $NHAN ]]; then
		printf 'dose_id\ttruc\tmuc\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\toracle_ten\toracle_gia_tri\tghi_chu\tmuc_tranh_chap\n' >"$NHAN"
	fi
}

append_nhan() {
	ensure_nhan_header
	local mt=${9:-}
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$mt" >>"$NHAN"
}

freq_stamp_block() {
	local tag=$1
	scripts/freq_stamp.sh 0 | tee "$OUTROOT/freq-${tag}.txt"
}

stop_lab0() {
	echo "dung lab0-postgres lab0-nginx" | tee -a "$OUTROOT/lieu.log"
	docker stop lab0-postgres lab0-nginx >/dev/null || true
}

start_lab0() {
	echo "khoi dong lai lab0-postgres lab0-nginx" | tee -a "$OUTROOT/lieu.log"
	docker start lab0-postgres lab0-nginx >/dev/null
	local i
	for ((i = 0; i < 60; i++)); do
		curl -sf -o /dev/null http://127.0.0.1:18080/file4k.bin && \
			docker exec -e PGPASSWORD=hids-lab0 lab0-postgres \
				psql -U postgres -h 127.0.0.1 -c 'SELECT 1' postgres >/dev/null 2>&1 && return 0
		sleep 1
	done
	echo "lab0 khong san sang sau start" >&2
	return 1
}

# Hieu chuan mot lan luc may ranh (cơ chế m4.sh) — phu luc 1.2 muc 2
calibrate_loops_idle() {
	echo "=== hieu chuan wl/mem luc may ranh (CPU $WL_CPU, system.slice) ===" | tee -a "$OUTROOT/lieu.log"
	mkdir -p out /root/hids/out
	local fifo wl_pid
	fifo=$(mktemp -u out/lab1-cal-XXXX.fifo)
	mkfifo "$fifo"
	exec 9<>"$fifo"
	start_wl_cpu0 "$fifo" "$OUTROOT/cal-wl.log" mixed 1
	wl_pid=$WL_PID
	sleep 3
	kill "$wl_pid" "${WL_SCOPE_PID:-}" 2>/dev/null || true
	wait "${WL_SCOPE_PID:-}" 2>/dev/null || true
	exec 9>&-
	rm -f "$fifo"
	# mem 1 — khong can fifo wait_go neu mem tu calibrate; van dung system.slice
	systemd-run --scope --quiet --slice=system.slice --working-directory="$(pwd)" \
		--unit="lab1-cal-mem" -- taskset -c 0 ./bin/wl mem 1 \
		>"$OUTROOT/cal-mem.out" 2>"$OUTROOT/cal-mem.log" &
	local sp=$!
	sleep 25
	kill "$sp" 2>/dev/null || true
	wait "$sp" 2>/dev/null || true
	if [[ -f out/m4-loops.txt && ! -f $LOOPS_FILE ]]; then
		cp out/m4-loops.txt "$LOOPS_FILE"
	fi
	if [[ -f $LOOPS_FILE ]]; then
		cp "$LOOPS_FILE" out/m4-loops.txt
	fi
	BURN_LOOPS=$(awk '/^burn_loops/{print $2}' "$LOOPS_FILE")
	MEM_STEPS=$(awk '/^mem_steps/{print $2}' "$LOOPS_FILE")
	[[ -n $BURN_LOOPS && $BURN_LOOPS -gt 0 ]] || { echo "calibrate: thieu burn_loops" >&2; exit 1; }
	[[ -n $MEM_STEPS && $MEM_STEPS -gt 0 ]] || { echo "calibrate: thieu mem_steps" >&2; exit 1; }
	echo "calibrate: burn_loops=$BURN_LOOPS mem_steps=$MEM_STEPS (file=$LOOPS_FILE)" | tee "$OUTROOT/calibrate.txt"
}

cgroup_of_pid() {
	# cgroup v2 path
	local p=$1
	awk -F: '$1=="0"{print $3; exit}' "/proc/$p/cgroup"
}

# --- D3: stream tren CPU 1-7, wl -loops mem_steps mem 500, -pmu on ---
run_d3_one() {
	local L=$1 run=$2
	local dir="$OUTROOT/D3/L${L}/run${run}"
	mkdir -p "$dir"
	local attempt
	for attempt in 1 2 3; do
		local bin fifo wl_pid cpid stress_pid=""
		bin="out/lab1-d3-L${L}-r${run}-a${attempt}.bin"
		fifo="out/lab1-d3-L${L}-r${run}-a${attempt}.fifo"
		rm -f "$fifo" "$dir/ok"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		start_wl_cpu0 "$fifo" "$dir/wl.log" -loops "$MEM_STEPS" mem 500
		wl_pid=$WL_PID
		if [[ -z $wl_pid ]]; then
			exec 9>&-; rm -f "$fifo"
			echo "D3 L=$L run=$run attempt=$attempt: khong co wl" | tee -a "$dir/ketqua.txt"
			continue
		fi
		sleep 0.3
		taskset -c "$COLLECT_CPUS" "$COLLECT" -pid "$wl_pid" -zstd-level 0 -pmu on -out "$bin" 2>"$dir/collect.log" &
		cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			kill "$wl_pid" "$cpid" "${WL_SCOPE_PID:-}" 2>/dev/null || true
			wait "$cpid" 2>/dev/null || true
			wait "${WL_SCOPE_PID:-}" 2>/dev/null || true
			exec 9>&-
			rm -f "$fifo"
			echo "D3 L=$L run=$run attempt=$attempt KHONG_READY" | tee -a "$dir/ketqua.txt"
			continue
		fi
		wait_wchan "$wl_pid" eq || true
		local t0 t1
		t0=$(mono_ns)
		if ((L > 0)); then
			stress-ng --stream "$L" --taskset 1-7 --timeout 300 >"$dir/stress.log" 2>&1 &
			stress_pid=$!
			sleep 10
		fi
		printf '.' >&9
		wait_wchan "$wl_pid" eq || true
		printf '.' >&9
		wait_wchan "$wl_pid" ne || true
		wait_wchan "$wl_pid" eq || true
		t1=$(mono_ns)
		kill -INT "$cpid" 2>/dev/null || true
		wait "$cpid" 2>/dev/null || true
		printf '.' >&9
		exec 9>&-
		wait "${WL_SCOPE_PID:-}" 2>/dev/null || true
		[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true
		rm -f "$fifo"

		./bin/rec-export "$bin" >"$dir/export.csv"
		python3 "$STATS" summarize "$dir/export.csv" "$wl_pid" --pmu >"$dir/summary.tsv" || true
		{
			echo "=== D3 L=$L run=$run attempt=$attempt loops=$MEM_STEPS ==="
			echo "wl_pid=$wl_pid t0=$t0 t1=$t1"
			cat "$dir/summary.tsv"
		} | tee "$dir/ketqua.txt"
		if grep -q '^cpi_med' "$dir/summary.tsv" 2>/dev/null && ! grep -q '^EMPTY' "$dir/summary.tsv"; then
			local cpi
			cpi=$(awk -F'\t' '/^cpi_med/{print $2}' "$dir/summary.tsv")
			append_nhan "D3v12-L${L}-r${run}" "D3" "$L" "$t0" "$t1" "CPI_cyc_per_inst" "$cpi" "pmu=on;phuluc1.2;loops=$MEM_STEPS"
			echo ok >"$dir/ok"
			return 0
		fi
		echo "D3 L=$L run=$run attempt=$attempt: thieu cpi_med, thu lai" | tee -a "$dir/ketqua.txt"
	done
	echo "D3 L=$L run=$run THAT BAI sau 3 lan" | tee -a "$OUTROOT/lieu.log"
	FAIL=1
	return 1
}

# --- D4 / E5: systemd-run --scope + CPUQuota, wl -loops mem 500 ---
run_throttle_one() {
	local mode=$1 cpus_arg=$2 run=$3  # none|2|1|0.5
	local tag muc quota_pct
	case $cpus_arg in
		none) tag="nolimit"; muc="none"; quota_pct="" ;;
		2) tag="cpus2"; muc="2"; quota_pct="200%" ;;
		1) tag="cpus1"; muc="1"; quota_pct="100%" ;;
		0.5) tag="cpus0.5"; muc="0.5"; quota_pct="50%" ;;
		*) echo "cpus_arg sai: $cpus_arg" >&2; return 1 ;;
	esac
	local dir="$OUTROOT/${mode}/${tag}/run${run}"
	mkdir -p "$dir"
	local attempt
	for attempt in 1 2 3; do
		local fifo bin
		fifo="out/lab1-${mode}-${tag}-r${run}-a${attempt}.fifo"
		bin="out/lab1-${mode}-${tag}-r${run}-a${attempt}.bin"
		rm -f "$fifo" "$dir/ok"
		mkfifo "$fifo"
		exec 9<>"$fifo"

		local -a scope_cmd=(systemd-run --scope --quiet --slice=system.slice)
		if [[ -n $quota_pct ]]; then
			scope_cmd+=(-p "CPUQuota=$quota_pct")
		fi
		scope_cmd+=(--working-directory="$(pwd)" --unit="lab1-${mode}-${tag}-r${run}-a${attempt}")
		"${scope_cmd[@]}" -- /bin/bash -c "exec taskset -c 0 ./bin/wl -loops '$MEM_STEPS' mem 500" \
			<"$fifo" >"$dir/wl.log" 2>&1 &
		local scope_pid=$!
		sleep 0.5
		local wl_pid="" i
		for ((i = 0; i < 100; i++)); do
			wl_pid=$(pgrep -n -f './bin/wl -loops' 2>/dev/null || true)
			[[ -n $wl_pid ]] && kill -0 "$wl_pid" 2>/dev/null && break
			wl_pid=""
			sleep 0.05
		done
		if [[ -z $wl_pid ]]; then
			echo "${mode} ${tag} run=$run attempt=$attempt: khong tim wl pid" | tee "$dir/ketqua.txt"
			printf '...' >&9 2>/dev/null || true
			exec 9>&-
			kill "$scope_pid" 2>/dev/null || true
			wait "$scope_pid" 2>/dev/null || true
			rm -f "$fifo"
			continue
		fi

		local cg_rel cg_path
		cg_rel=$(cgroup_of_pid "$wl_pid")
		cg_path="/sys/fs/cgroup${cg_rel}"
		echo "wl_pid=$wl_pid cgroup=$cg_path" >"$dir/cgroup.txt"

		local thr0 thr1 nr0 nr1
		thr0=$(awk '/^throttled_usec/{print $2}' "$cg_path/cpu.stat" 2>/dev/null || echo 0)
		nr0=$(awk '/^nr_throttled/{print $2}' "$cg_path/cpu.stat" 2>/dev/null || echo 0)

		taskset -c "$COLLECT_CPUS" "$COLLECT" -pid "$wl_pid" -zstd-level 0 -out "$bin" 2>"$dir/collect.log" &
		local cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			kill -INT "$cpid" 2>/dev/null || true
			wait "$cpid" 2>/dev/null || true
			printf '...' >&9
			exec 9>&-
			wait "$scope_pid" 2>/dev/null || true
			rm -f "$fifo"
			continue
		fi
		wait_wchan "$wl_pid" eq || true
		local t0 t1
		t0=$(mono_ns)
		printf '.' >&9
		wait_wchan "$wl_pid" eq || true
		printf '.' >&9
		wait_wchan "$wl_pid" ne || true
		wait_wchan "$wl_pid" eq || true
		t1=$(mono_ns)
		thr1=$(awk '/^throttled_usec/{print $2}' "$cg_path/cpu.stat" 2>/dev/null || echo 0)
		nr1=$(awk '/^nr_throttled/{print $2}' "$cg_path/cpu.stat" 2>/dev/null || echo 0)
		local d_thr=$((thr1 - thr0))
		local d_nr=$((nr1 - nr0))

		kill -INT "$cpid" 2>/dev/null || true
		wait "$cpid" 2>/dev/null || true
		printf '.' >&9
		exec 9>&-
		wait "$scope_pid" 2>/dev/null || true
		rm -f "$fifo"

		./bin/rec-export "$bin" >"$dir/export.csv"
		python3 "$STATS" summarize "$dir/export.csv" "$wl_pid" >"$dir/summary.tsv" || true
		{
			echo "=== ${mode} cpus=$cpus_arg quota=${quota_pct:-none} run=$run attempt=$attempt ==="
			echo "wl_pid=$wl_pid t0=$t0 t1=$t1 cgroup=$cg_path"
			echo "nr_throttled_delta=$d_nr"
			echo "throttled_usec_delta=$d_thr"
			cat "$dir/summary.tsv"
		} | tee "$dir/ketqua.txt"
		if grep -q '^rq_med' "$dir/summary.tsv" 2>/dev/null; then
			local rq_med steal_med muc_num
			rq_med=$(awk -F'\t' '/^rq_med/{print $2}' "$dir/summary.tsv")
			steal_med=$(awk -F'\t' '/^steal_med/{print $2}' "$dir/summary.tsv")
			case $cpus_arg in
				none) muc_num=0 ;;
				2) muc_num=1 ;;
				1) muc_num=2 ;;
				0.5) muc_num=3 ;;
			esac
			append_nhan "${mode}v12-${tag}-r${run}" "$mode" "$muc" "$t0" "$t1" \
				"throttled_usec_delta" "$d_thr" "nr_throttled_delta=${d_nr};rq_med=${rq_med};steal_med=${steal_med};phuluc1.2"
			printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$muc_num" "$rq_med" "$steal_med" "$d_thr" "$d_nr" "$cpus_arg" \
				>>"$OUTROOT/${mode}/runs.tsv"
			echo ok >"$dir/ok"
			return 0
		fi
	done
	FAIL=1
	return 1
}

aggregate_d3() {
	local f="$OUTROOT/D3/bang.tsv"
	printf 'muc\texpected\tother\tcpi\truns\n' >"$f"
	local L
	# shellcheck disable=SC2086
	for L in $D3_LEVELS; do
		local cpus=() rqs=() cpis=()
		local run n_ok=0
		for run in 1 2 3; do
			local s="$OUTROOT/D3/L${L}/run${run}/summary.tsv"
			[[ -f $OUTROOT/D3/L${L}/run${run}/ok ]] || continue
			[[ -f $s ]] || continue
			n_ok=$((n_ok + 1))
			cpus+=("$(awk -F'\t' '/^cpu_med/{print $2}' "$s")")
			rqs+=("$(awk -F'\t' '/^rq_med/{print $2}' "$s")")
			cpis+=("$(awk -F'\t' '/^cpi_med/{print $2}' "$s")")
		done
		if ((n_ok < 3)); then
			echo "D3 L=$L: chi $n_ok/3 lan OK — bat buoc 3/3" | tee -a "$OUTROOT/lieu.log"
			FAIL=1
		fi
		python3 - "$L" "${cpus[@]}" -- "${rqs[@]}" -- "${cpis[@]}" <<'PY' >>"$f"
import sys, statistics
args = sys.argv[1:]
# L cpu... -- rq... -- cpi...
seps = [i for i,a in enumerate(args) if a=="--"]
L = args[0]
cpus = [float(x) for x in args[1:seps[0]] if x and x != "nan"]
rqs = [float(x) for x in args[seps[0]+1:seps[1]] if x and x != "nan"]
cpis = [float(x) for x in args[seps[1]+1:] if x and x != "nan"]
cpu = statistics.median(cpus) if cpus else float("nan")
rq = statistics.median(rqs) if rqs else float("nan")
cpi = statistics.median(cpis) if cpis else float("nan")
print(f"{L}\t{cpu}\t{rq}\t{cpi}\t{len(cpus)}")
PY
	done
	# Spearman tren cpu (expected); other=rq; phu luc 1.2
	# check doc cot expected/other — bo cot cpi bang file tam
	awk -F'\t' 'NR==1{print "muc\texpected\tother\truns"; next} {print $1"\t"$2"\t"$3"\t"$5}' "$f" >"$OUTROOT/D3/bang-check.tsv"
	python3 "$STATS" check-d3 "$OUTROOT/D3/bang-check.tsv" | tee "$OUTROOT/D3/tieu-chi.txt" || FAIL=1
	{
		echo "# expected=cpu_med_ns other=rq_med_ns (phu luc 1.2)"
		cat "$f"
		cat "$OUTROOT/D3/tieu-chi.txt"
	} >"$OUTROOT/D3-bang.txt"
}

aggregate_d4() {
	local f="$OUTROOT/D4/bang.tsv"
	printf 'muc\texpected\tother\truns\tcpus\n' >"$f"
	python3 - "$OUTROOT/D4/runs.tsv" "$f" <<'PY'
import collections, statistics, sys
src, dst = sys.argv[1], sys.argv[2]
by = collections.defaultdict(list)
with open(src) as fh:
    for line in fh:
        parts = line.strip().split("\t")
        if len(parts) < 6: continue
        muc_num, rq, steal, d_thr, d_nr, cpus = parts
        by[float(muc_num)].append((float(rq), float(steal), cpus))
with open(dst, "a") as out:
    for muc in sorted(by):
        rqs = [x[0] for x in by[muc]]
        steals = [x[1] for x in by[muc]]
        cpus = by[muc][0][2]
        out.write(f"{muc}\t{statistics.median(rqs)}\t{statistics.median(steals)}\t{len(rqs)}\t{cpus}\n")
PY
	# bat buoc 3/3 moi muc
	local tag
	for tag in nolimit cpus2 cpus1 cpus0.5; do
		local n=0 r
		for r in 1 2 3; do
			[[ -f $OUTROOT/D4/$tag/run$r/ok ]] && n=$((n + 1))
		done
		if ((n < 3)); then
			echo "D4 $tag: $n/3 OK" | tee -a "$OUTROOT/lieu.log"
			FAIL=1
		fi
	done
	python3 "$STATS" check-d4 "$f" | tee "$OUTROOT/D4/tieu-chi.txt" || FAIL=1
	cp "$f" "$OUTROOT/D4-bang.txt"
	cat "$OUTROOT/D4/tieu-chi.txt" >>"$OUTROOT/D4-bang.txt"
}

aggregate_e5() {
	python3 - "$OUTROOT/E5/runs.tsv" "$OUTROOT/E5" <<'PY'
import collections, statistics, math, sys
src, outdir = sys.argv[1], sys.argv[2]
rows = []
with open(src) as f:
    for line in f:
        parts = line.strip().split("\t")
        if len(parts) < 6: continue
        muc_num, rq, steal, d_thr, d_nr, cpus = parts
        rows.append((float(muc_num), float(rq), float(steal), float(d_thr), cpus))
by = collections.defaultdict(list)
for r in rows:
    by[r[0]].append(r)
pairs = []
steal_ok = True
lines = ["muc\tcpus\trq_med\tsteal_med\td_throttled_usec\tsteal_pct_of_rq"]
for muc in sorted(by):
    rs = by[muc]
    rq = statistics.median([x[1] for x in rs])
    st = statistics.median([x[2] for x in rs])
    thr = statistics.median([x[3] for x in rs])
    cpus = rs[0][4]
    pct = (abs(st) / rq * 100.0) if rq else float("inf")
    if pct >= 2.0:
        steal_ok = False
    lines.append(f"{muc}\t{cpus}\t{rq}\t{st}\t{thr}\t{pct:.4f}")
    pairs.append((thr, rq))
xs = [p[0] for p in pairs]
ys = [p[1] for p in pairs]
n = len(xs)
if n >= 2:
    mx, my = sum(xs)/n, sum(ys)/n
    num = sum((a-mx)*(b-my) for a,b in zip(xs,ys))
    denx = math.sqrt(sum((a-mx)**2 for a in xs))
    deny = math.sqrt(sum((b-my)**2 for b in ys))
    r = num/(denx*deny) if denx and deny else float("nan")
else:
    r = float("nan")
ok_p = r >= 0.8
with open(outdir + "/bang.tsv", "w") as f:
    f.write("\n".join(lines) + "\n")
with open(outdir + "/tieu-chi.txt", "w") as f:
    f.write(f"pearson_delta_rq_vs_throttled_usec\t{r}\n")
    f.write(f"tieu_chi_pearson>=0.8\t{'DAT' if ok_p else 'KHONG_DAT'}\n")
    f.write(f"tieu_chi_steal_pct<2\t{'DAT' if steal_ok else 'KHONG_DAT'}\n")
print(open(outdir + "/bang.tsv").read())
print(open(outdir + "/tieu-ci.txt").read() if False else open(outdir + "/tieu-chi.txt").read())
sys.exit(0 if (ok_p and steal_ok) else 1)
PY
	local ec=$?
	# 3/3
	local tag
	for tag in nolimit cpus2 cpus1 cpus0.5; do
		local n=0 r
		for r in 1 2 3; do
			[[ -f $OUTROOT/E5/$tag/run$r/ok ]] && n=$((n + 1))
		done
		if ((n < 3)); then
			echo "E5 $tag: $n/3 OK" | tee -a "$OUTROOT/lieu.log"
			FAIL=1
			ec=1
		fi
	done
	cp "$OUTROOT/E5/bang.tsv" "$OUTROOT/E5-bang.txt"
	cat "$OUTROOT/E5/tieu-chi.txt" >>"$OUTROOT/E5-bang.txt"
	((ec != 0)) && FAIL=1
	return 0
}

stop_if_fail() {
	local step=$1
	if ((FAIL != 0)); then
		echo "DUNG sau $step FAIL=$FAIL" | tee -a "$OUTROOT/lieu.log"
		start_lab0 || true
		echo "FAIL=$FAIL" | tee "$OUTROOT/FAIL"
		exit 1
	fi
}

# ========== main ==========
ensure_nhan_header
: >"$OUTROOT/lieu.log"
echo "LAB-1 lieu bat dau $(date -Is) ONLY=$ONLY D3_LEVELS=$D3_LEVELS" | tee -a "$OUTROOT/lieu.log"

sanitize_cpu0
stop_lab0
calibrate_loops_idle

if [[ $ONLY == all ]]; then
	append_nhan "D2-HOAN" "D2" "na" "0" "0" "na" "na" "D2 hoan: can vCenter"
	echo "D2 hoan: can vCenter" | tee "$OUTROOT/D2-hoan.txt"
	echo "ONLY=all: dung LAB1_ONLY=d3d4e5 de chay lai D3/D4/E5" | tee -a "$OUTROOT/lieu.log"
	FAIL=1
	stop_if_fail "chi-dinh-ONLY"
fi

# --- D3 ---
freq_stamp_block "truoc-D3-v14"
rm -rf "$OUTROOT/D3"
mkdir -p "$OUTROOT/D3"
# shellcheck disable=SC2086
for L in $D3_LEVELS; do
	for run in 1 2 3; do
		run_d3_one "$L" "$run" || true
	done
done
freq_stamp_block "sau-D3-v14"
aggregate_d3
stop_if_fail "D3"

# --- D4 ---
freq_stamp_block "truoc-D4-v12"
rm -rf "$OUTROOT/D4"
mkdir -p "$OUTROOT/D4"
: >"$OUTROOT/D4/runs.tsv"
for cpus in none 2 1 0.5; do
	for run in 1 2 3; do
		run_throttle_one D4 "$cpus" "$run" || true
	done
done
freq_stamp_block "sau-D4-v12"
aggregate_d4
stop_if_fail "D4"

# --- E5 ---
freq_stamp_block "truoc-E5-v12"
rm -rf "$OUTROOT/E5"
mkdir -p "$OUTROOT/E5"
: >"$OUTROOT/E5/runs.tsv"
for cpus in none 2 1 0.5; do
	for run in 1 2 3; do
		run_throttle_one E5 "$cpus" "$run" || true
	done
done
freq_stamp_block "sau-E5-v12"
aggregate_e5
stop_if_fail "E5"

start_lab0 || FAIL=1

echo "FAIL=$FAIL" | tee "$OUTROOT/FAIL"
echo "LAB-1 lieu (phu luc 1.2) xong $(date -Is) FAIL=$FAIL" | tee -a "$OUTROOT/lieu.log"
exit "$FAIL"
