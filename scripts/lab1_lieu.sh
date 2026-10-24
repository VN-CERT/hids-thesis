#!/usr/bin/env bash
# lab1_lieu.sh — bo lieu D1/D3/D4 + E5 (LAB-1 buoc 3). D2 ghi hoan.
# Container lab0-* DUNG truoc khi chay, khoi dong lai sau.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUTROOT="${1:?can thu muc output validation/lab1-<ngay>/lieu}"
mkdir -p "$OUTROOT" out lab
DAY_DIR="$(dirname "$OUTROOT")"
NHAN="${LAB1_NHAN_LIEU:-lab/nhan-lieu.tsv}"
WL=./bin/wl
COLLECT=./bin/hids-collect
STATS=./scripts/lab1_lieu_stats.py
WL_CPU=0
FAIL=0

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

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
	# dose_id truc muc t0 t1 oracle_ten oracle_gia_tri ghi_chu [muc_tranh_chap]
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
	# cho san sang
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

# --- D1: rq, stress-ng --cpu N tren CPU 0, wl mixed ---
run_d1_one() {
	local N=$1 run=$2
	local dir="$OUTROOT/D1/N${N}/run${run}"
	mkdir -p "$dir"
	local attempt=1 bin fifo wl_pid cpid stress_pid="" bt_pid=""
	for attempt in 1 2; do
		bin="out/lab1-d1-N${N}-r${run}-a${attempt}.bin"
		fifo="out/lab1-d1-N${N}-r${run}-a${attempt}.fifo"
		rm -f "$fifo"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		# ~60s: 3000 vong * (10ms burn + 10ms sleep)
		taskset -c "$WL_CPU" "$WL" mixed 10000 10000 3000 <"$fifo" >"$dir/wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.3
		"$COLLECT" -pid "$wl_pid" -zstd-level 0 -out "$bin" 2>"$dir/collect.log" &
		cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			kill "$wl_pid" "$cpid" 2>/dev/null || true
			wait "$wl_pid" "$cpid" 2>/dev/null || true
			exec 9>&-
			rm -f "$fifo"
			echo "D1 N=$N run=$run attempt=$attempt KHONG_READY" | tee -a "$dir/ketqua.txt"
			continue
		fi
		wait_wchan "$wl_pid" eq || true
		local t0 t1
		t0=$(mono_ns)
		if ((N > 0)); then
			stress-ng --cpu "$N" --taskset "$WL_CPU" --timeout 120 >"$dir/stress.log" 2>&1 &
			stress_pid=$!
			sleep 2
		fi
		# bpftrace @rq tong
		bpftrace -e 'tracepoint:sched:sched_wakeup /args->pid == $1 && @w == 0/ { @w = nsecs; } tracepoint:sched:sched_switch { $now = nsecs; if (args->prev_pid == $1 && args->prev_state == 0) { @p = $now; } if (args->next_pid == $1) { $d = 0; if (@w != 0) { $d = $d + ($now - @w); @rq_sau_wakeup_ns = sum($now - @w); @w = 0; } if (@p != 0) { $d = $d + ($now - @p); @rq_sau_preempt_ns = sum($now - @p); @p = 0; } if ($d > 0) { @rq_tong_ns = sum($d); } } }' "$wl_pid" >"$dir/bpftrace.log" 2>&1 &
		bt_pid=$!
		sleep 1
		printf '.' >&9
		wait_wchan "$wl_pid" eq || true
		printf '.' >&9
		# cho wl chay het ~60s hoac timeout
		local waited=0
		while kill -0 "$wl_pid" 2>/dev/null && ((waited < 90)); do
			sleep 1
			waited=$((waited + 1))
		done
		t1=$(mono_ns)
		kill -INT "$bt_pid" 2>/dev/null || true
		wait "$bt_pid" 2>/dev/null || true
		kill -INT "$cpid" 2>/dev/null || true
		wait "$cpid" 2>/dev/null || true
		printf '.' >&9
		exec 9>&-
		wait "$wl_pid" 2>/dev/null || true
		[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true
		rm -f "$fifo"

		./bin/rec-export "$bin" >"$dir/export.csv"
		python3 "$STATS" summarize "$dir/export.csv" "$wl_pid" >"$dir/summary.tsv" || true
		local bt_rq
		bt_rq=$(grep '^@rq_tong_ns:' "$dir/bpftrace.log" 2>/dev/null | tail -1 | awk '{print $NF}')
		bt_rq=${bt_rq:-na}
		{
			echo "=== D1 N=$N run=$run attempt=$attempt ==="
			echo "wl_pid=$wl_pid t0=$t0 t1=$t1"
			echo "bpftrace_@rq_tong_ns=$bt_rq"
			cat "$dir/summary.tsv"
		} | tee "$dir/ketqua.txt"
		if grep -q '^rq_med' "$dir/summary.tsv" 2>/dev/null; then
			local rq_med
			rq_med=$(awk -F'\t' '/^rq_med/{print $2}' "$dir/summary.tsv")
			append_nhan "D1-N${N}-r${run}" "D1" "$N" "$t0" "$t1" "bpftrace_@rq_tong_ns" "$bt_rq" "collector_rq_med=${rq_med}"
			echo "$bin" >"$dir/ok"
			return 0
		fi
		echo "D1 N=$N run=$run attempt=$attempt: khong co rq_med, thu lai" | tee -a "$dir/ketqua.txt"
	done
	echo "D1 N=$N run=$run THAT BAI sau 2 lan" | tee -a "$OUTROOT/lieu.log"
	FAIL=1
	return 1
}

# --- D3: stream tren CPU 1-7, wl mem, -pmu on ---
run_d3_one() {
	local L=$1 run=$2
	local dir="$OUTROOT/D3/L${L}/run${run}"
	mkdir -p "$dir"
	local attempt=1
	for attempt in 1 2; do
		local bin fifo wl_pid cpid stress_pid=""
		bin="out/lab1-d3-L${L}-r${run}-a${attempt}.bin"
		fifo="out/lab1-d3-L${L}-r${run}-a${attempt}.fifo"
		rm -f "$fifo"
		mkfifo "$fifo"
		exec 9<>"$fifo"
		taskset -c "$WL_CPU" "$WL" mem 500 <"$fifo" >"$dir/wl.log" 2>&1 &
		wl_pid=$!
		sleep 0.3
		"$COLLECT" -pid "$wl_pid" -zstd-level 0 -pmu on -out "$bin" 2>"$dir/collect.log" &
		cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			kill "$wl_pid" "$cpid" 2>/dev/null || true
			wait "$wl_pid" "$cpid" 2>/dev/null || true
			exec 9>&-
			rm -f "$fifo"
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
		wait "$wl_pid" 2>/dev/null || true
		[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null && wait "$stress_pid" 2>/dev/null || true
		rm -f "$fifo"

		./bin/rec-export "$bin" >"$dir/export.csv"
		python3 "$STATS" summarize "$dir/export.csv" "$wl_pid" --pmu >"$dir/summary.tsv" || true
		{
			echo "=== D3 L=$L run=$run attempt=$attempt ==="
			echo "wl_pid=$wl_pid t0=$t0 t1=$t1"
			cat "$dir/summary.tsv"
		} | tee "$dir/ketqua.txt"
		if grep -q '^cpi_med' "$dir/summary.tsv" 2>/dev/null; then
			local cpi
			cpi=$(awk -F'\t' '/^cpi_med/{print $2}' "$dir/summary.tsv")
			append_nhan "D3-L${L}-r${run}" "D3" "$L" "$t0" "$t1" "CPI_cyc_per_inst" "$cpi" "pmu=on"
			echo ok >"$dir/ok"
			return 0
		fi
	done
	FAIL=1
	return 1
}

# --- D4 / E5: wl trong container --cpus (stdin fifo cho wait_go) ---
run_throttle_one() {
	local mode=$1 cpus_arg=$2 run=$3  # mode=D4|E5; cpus_arg=none|2|1|0.5
	local tag muc
	local -a docker_cpus=()
	if [[ $cpus_arg == none ]]; then
		tag="nolimit"
		muc="none"
	else
		tag="cpus${cpus_arg}"
		muc="$cpus_arg"
		docker_cpus=(--cpus="$cpus_arg")
	fi
	local dir="$OUTROOT/${mode}/${tag}/run${run}"
	mkdir -p "$dir"
	local attempt=1
	for attempt in 1 2; do
		local cname="lab1-wl-th-${mode}-${tag}-r${run}-a${attempt}"
		local fifo="out/lab1-${mode}-${tag}-r${run}-a${attempt}.fifo"
		docker rm -f "$cname" >/dev/null 2>&1 || true
		rm -f "$fifo"
		mkfifo "$fifo"
		# container nen: sleep infinity, roi docker exec -i wl
		docker run -d --name "$cname" --network host --cpuset-cpus=0 \
			"${docker_cpus[@]}" \
			-v /root/collector:/root/collector \
			-v /root/hids:/root/hids \
			-w /root/collector \
			ubuntu:24.04 sleep infinity \
			>"$dir/docker-run.log" 2>&1
		sleep 1
		local cg
		cg=$(docker inspect -f '{{.Id}}' "$cname")
		cg="/sys/fs/cgroup/system.slice/docker-${cg}.scope"

		# chay wl qua exec -i, stdin = fifo
		docker exec -i "$cname" ./bin/wl mixed 10000 10000 3000 \
			<"$fifo" >"$dir/wl.log" 2>&1 &
		local exec_pid=$!
		# cho wl xuat hien trong container
		local wl_pid="" i
		for ((i = 0; i < 50; i++)); do
			wl_pid=$(docker top "$cname" -eo pid,cmd 2>/dev/null | awk '/bin\/wl/{print $1; exit}')
			[[ -n $wl_pid ]] && break
			sleep 0.1
		done
		if [[ -z ${wl_pid:-} ]]; then
			echo "${mode} ${tag} run=$run: khong tim wl pid" | tee "$dir/ketqua.txt"
			kill "$exec_pid" 2>/dev/null || true
			docker rm -f "$cname" >/dev/null 2>&1 || true
			rm -f "$fifo"
			continue
		fi
		# mo fifo de ghi (wl dang cho wait_go)
		exec 9<>"$fifo"

		local thr0 thr1 nr0 nr1
		thr0=$(awk '/^throttled_usec/{print $2}' "$cg/cpu.stat" 2>/dev/null || echo 0)
		nr0=$(awk '/^nr_throttled/{print $2}' "$cg/cpu.stat" 2>/dev/null || echo 0)

		local bin="out/lab1-${mode}-${tag}-r${run}-a${attempt}.bin"
		"$COLLECT" -pid "$wl_pid" -zstd-level 0 -out "$bin" 2>"$dir/collect.log" &
		local cpid=$!
		if ! wait_ready "$dir/collect.log"; then
			kill -INT "$cpid" 2>/dev/null || true
			wait "$cpid" 2>/dev/null || true
			printf '...' >&9
			exec 9>&-
			wait "$exec_pid" 2>/dev/null || true
			docker rm -f "$cname" >/dev/null 2>&1 || true
			rm -f "$fifo"
			continue
		fi
		wait_wchan "$wl_pid" eq || true
		local t0 t1
		t0=$(mono_ns)
		printf '.' >&9
		wait_wchan "$wl_pid" eq || true
		printf '.' >&9
		local waited=0
		while kill -0 "$wl_pid" 2>/dev/null && ((waited < 90)); do
			# van dang mixed (chua ve pipe_read)
			w=$(cat "/proc/$wl_pid/wchan" 2>/dev/null || true)
			if [[ $w == pipe_read ]]; then
				break
			fi
			sleep 1
			waited=$((waited + 1))
		done
		t1=$(mono_ns)
		thr1=$(awk '/^throttled_usec/{print $2}' "$cg/cpu.stat" 2>/dev/null || echo 0)
		nr1=$(awk '/^nr_throttled/{print $2}' "$cg/cpu.stat" 2>/dev/null || echo 0)
		local d_thr=$((thr1 - thr0))
		local d_nr=$((nr1 - nr0))

		kill -INT "$cpid" 2>/dev/null || true
		wait "$cpid" 2>/dev/null || true
		printf '.' >&9
		exec 9>&-
		wait "$exec_pid" 2>/dev/null || true
		docker rm -f "$cname" >/dev/null 2>&1 || true
		rm -f "$fifo"

		./bin/rec-export "$bin" >"$dir/export.csv"
		python3 "$STATS" summarize "$dir/export.csv" "$wl_pid" >"$dir/summary.tsv" || true
		{
			echo "=== ${mode} cpus=$cpus_arg run=$run attempt=$attempt ==="
			echo "wl_pid=$wl_pid t0=$t0 t1=$t1"
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
				*) muc_num=0 ;;
			esac
			append_nhan "${mode}-${tag}-r${run}" "$mode" "$muc" "$t0" "$t1" \
				"throttled_usec_delta" "$d_thr" "nr_throttled_delta=${d_nr};rq_med=${rq_med};steal_med=${steal_med};muc_num=${muc_num}"
			printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$muc_num" "$rq_med" "$steal_med" "$d_thr" "$d_nr" "$cpus_arg" \
				>>"$OUTROOT/${mode}/runs.tsv"
			echo ok >"$dir/ok"
			return 0
		fi
	done
	FAIL=1
	return 1
}

aggregate_d1() {
	local f="$OUTROOT/D1/bang.tsv"
	printf 'muc\texpected\tother\truns\n' >"$f"
	local N
	for N in 0 1 2 3 4; do
		local rqs=() cpus=()
		local run
		for run in 1 2 3; do
			local s="$OUTROOT/D1/N${N}/run${run}/summary.tsv"
			[[ -f $s ]] || continue
			rqs+=("$(awk -F'\t' '/^rq_med/{print $2}' "$s")")
			cpus+=("$(awk -F'\t' '/^cpu_med/{print $2}' "$s")")
		done
		python3 - "$N" "${rqs[@]}" -- "${cpus[@]}" <<'PY' >>"$f"
import sys, statistics
args = sys.argv[1:]
sep = args.index("--")
N = args[0]
rqs = [float(x) for x in args[1:sep] if x and x != "nan"]
cpus = [float(x) for x in args[sep+1:] if x and x != "nan"]
rq = statistics.median(rqs) if rqs else float("nan")
cpu = statistics.median(cpus) if cpus else float("nan")
print(f"{N}\t{rq}\t{cpu}\t{len(rqs)}")
PY
	done
	python3 "$STATS" check-d1 "$f" | tee "$OUTROOT/D1/tieu-chi.txt" || FAIL=1
	cp "$f" "$OUTROOT/D1-bang.txt"
	cat "$OUTROOT/D1/tieu-chi.txt" >>"$OUTROOT/D1-bang.txt"
}

aggregate_d3() {
	local f="$OUTROOT/D3/bang.tsv"
	printf 'muc\texpected\tother\truns\n' >"$f"
	local L
	for L in 0 4 12 22; do
		local cpis=() rqs=()
		local run
		for run in 1 2 3; do
			local s="$OUTROOT/D3/L${L}/run${run}/summary.tsv"
			[[ -f $s ]] || continue
			cpis+=("$(awk -F'\t' '/^cpi_med/{print $2}' "$s")")
			rqs+=("$(awk -F'\t' '/^rq_med/{print $2}' "$s")")
		done
		python3 - "$L" "${cpis[@]}" -- "${rqs[@]}" <<'PY' >>"$f"
import sys, statistics
args = sys.argv[1:]
sep = args.index("--")
L = args[0]
cpis = [float(x) for x in args[1:sep] if x and x != "nan"]
rqs = [float(x) for x in args[sep+1:] if x and x != "nan"]
cpi = statistics.median(cpis) if cpis else float("nan")
rq = statistics.median(rqs) if rqs else float("nan")
print(f"{L}\t{cpi}\t{rq}\t{len(cpis)}")
PY
	done
	# other = rq (ky vong khong doi); expected = CPI
	python3 "$STATS" check-d3 "$f" | tee "$OUTROOT/D3/tieu-chi.txt" || FAIL=1
	cp "$f" "$OUTROOT/D3-bang.txt"
	cat "$OUTROOT/D3/tieu-chi.txt" >>"$OUTROOT/D3-bang.txt"
}

aggregate_d4() {
	local f="$OUTROOT/D4/bang.tsv"
	printf 'muc\texpected\tother\truns\tcpus\n' >"$f"
	# gom theo muc_num tu runs.tsv
	python3 - "$OUTROOT/D4/runs.tsv" "$f" <<'PY'
import collections, statistics, sys
src, dst = sys.argv[1], sys.argv[2]
by = collections.defaultdict(list)
with open(src) as f:
    for line in f:
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
	python3 "$STATS" check-d4 "$f" | tee "$OUTROOT/D4/tieu-chi.txt" || FAIL=1
	cp "$f" "$OUTROOT/D4-bang.txt"
	cat "$OUTROOT/D4/tieu-chi.txt" >>"$OUTROOT/D4-bang.txt"
}

aggregate_e5() {
	# Pearson Δrq vs Δthrottled_usec; |steal|/rq < 2%
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
# trung vi theo muc
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
# pearson
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
print(open(outdir + "/tieu-chi.txt").read())
sys.exit(0 if (ok_p and steal_ok) else 1)
PY
	local ec=$?
	cp "$OUTROOT/E5/bang.tsv" "$OUTROOT/E5-bang.txt"
	cat "$OUTROOT/E5/tieu-chi.txt" >>"$OUTROOT/E5-bang.txt"
	((ec != 0)) && FAIL=1
	return 0
}

# ========== main ==========
ensure_nhan_header
: >"$OUTROOT/lieu.log"
echo "LAB-1 lieu bat dau $(date -Is)" | tee -a "$OUTROOT/lieu.log"

# D2 hoan
append_nhan "D2-HOAN" "D2" "na" "0" "0" "na" "na" "D2 hoan: can vCenter"
echo "D2 hoan: can vCenter" | tee "$OUTROOT/D2-hoan.txt"

stop_lab0

freq_stamp_block "truoc-D1"
mkdir -p "$OUTROOT/D1"
for N in 0 1 2 3 4; do
	for run in 1 2 3; do
		run_d1_one "$N" "$run" || true
	done
done
freq_stamp_block "sau-D1"
aggregate_d1

freq_stamp_block "truoc-D3"
mkdir -p "$OUTROOT/D3"
for L in 0 4 12 22; do
	for run in 1 2 3; do
		run_d3_one "$L" "$run" || true
	done
done
freq_stamp_block "sau-D3"
aggregate_d3

# pull ubuntu image neu can
docker image inspect ubuntu:24.04 >/dev/null 2>&1 || docker pull ubuntu:24.04

freq_stamp_block "truoc-D4"
mkdir -p "$OUTROOT/D4"
: >"$OUTROOT/D4/runs.tsv"
for cpus in none 2 1 0.5; do
	for run in 1 2 3; do
		run_throttle_one D4 "$cpus" "$run" || true
	done
done
freq_stamp_block "sau-D4"
aggregate_d4

freq_stamp_block "truoc-E5"
mkdir -p "$OUTROOT/E5"
: >"$OUTROOT/E5/runs.tsv"
for cpus in none 2 1 0.5; do
	for run in 1 2 3; do
		run_throttle_one E5 "$cpus" "$run" || true
	done
done
freq_stamp_block "sau-E5"
aggregate_e5

start_lab0 || FAIL=1

echo "FAIL=$FAIL" | tee "$OUTROOT/FAIL"
echo "LAB-1 lieu xong $(date -Is) FAIL=$FAIL" | tee -a "$OUTROOT/lieu.log"
exit "$FAIL"
