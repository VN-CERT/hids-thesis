#!/usr/bin/env bash
# M6f: so overhead C0 / Falco / Tetragon (def + sysenter) / HIDS-host / HIDS-all
# tren T1 / T3 / T4 (10 luot xen ke). Khong sua BPF / analysis / file kien truc su.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" PATH="/usr/local/go/bin:/root/go/bin:/usr/local/bin:${PATH}"
source scripts/hids_data_policy.sh

OUTROOT="${1:?can thu muc output}"
RUNS="${M6F_RUNS:-10}"
REST="${M6F_REST:-5}"
mkdir -p "$OUTROOT"
LOG="$OUTROOT/overhead.log"
exec >>"$LOG" 2>&1
COLLECT=./bin/hids-collect
SYSINJ=./bin/sysinj
PARSE=./analysis/m5f_parse.py
STATUS="out/jobs/m6f-overhead.status"
TP_YAML="$PWD/scripts/m6f-tetragon-sysenter.yaml"
FALCO_IMG="falcosecurity/falco:latest"
TETRA_IMG="quay.io/cilium/tetragon:v1.7.0"
CONDS=(C0 FALCO TETRA-def TETRA-sysenter HIDS-host HIDS-all)

say() { echo "[$(date -Is)] $*"; echo "$(date -Is) $*" >"$STATUS"; }

mapfile -t RUNNING_CONTAINERS < <(docker ps --format '{{.Names}}')
USER_SLICE_SET=0
cleanup() {
	docker rm -f pgtest m5-nginx m6f-falco m6f-tetra >/dev/null 2>&1 || true
	# go BPF con sot (HIDS scope / container)
	pkill -INT -f './bin/hids-collect' 2>/dev/null || true
	sleep 1
	if ((${#RUNNING_CONTAINERS[@]})); then
		docker start "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
	fi
	if [[ $USER_SLICE_SET -eq 1 ]]; then
		systemctl set-property --runtime user.slice AllowedCPUs= || true
		USER_SLICE_SET=0
	fi
}
trap cleanup EXIT

cgroup_path_of_pid() { echo "/sys/fs/cgroup$(awk -F: '$1=="0" {print $3}' "/proc/$1/cgroup")"; }
docker_cgroup() { cgroup_path_of_pid "$(docker inspect -f '{{.State.Pid}}' "$1")"; }
scope_main_pid() {
	local u=$1 cg pid
	[[ $u != *.scope ]] && u="${u}.scope"
	cg=$(systemctl show "$u" -p ControlGroup --value 2>/dev/null) || return 1
	pid=$(head -1 "/sys/fs/cgroup${cg}/cgroup.procs" 2>/dev/null)
	[[ -n $pid ]] && echo "$pid"
}
scope_usage_usec() { awk '/^usage_usec/{print $2}' "$1/cpu.stat" 2>/dev/null || echo 0; }
bpf_prog_count() { bpftool prog show 2>/dev/null | wc -l; }

wait_ready_file() {
	local log=$1 i
	for ((i = 0; i < 2000; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.01
	done
	return 1
}
wait_grep_log() {
	local log=$1 pat=$2 max=${3:-90} i
	for ((i = 0; i < max; i++)); do
		grep -qE "$pat" "$log" 2>/dev/null && return 0
		sleep 1
	done
	return 1
}
wait_pid_gone() {
	local pid=$1 i
	for ((i = 0; i < 600; i++)); do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.1
	done
	say "LOI: pid $pid khong ket thuc"; return 1
}

CELL_FAIL=0
TOOL_KIND=""   # none|falco|tetra|hids
TOOL_CG=""
TOOL_USEC0=0
COLL_PID=""
BPF_BEFORE=0

require_bpf_attached() {
	local after tag=$1
	after=$(bpf_prog_count)
	echo "bpf_before=$BPF_BEFORE bpf_after=$after" >>"$dir/tool-meta.txt"
	if [[ $after -le $BPF_BEFORE ]]; then
		say "DUNG: $tag khong gan BPF (prog $BPF_BEFORE -> $after)"
		echo "BPF_ATTACH_FAIL before=$BPF_BEFORE after=$after" >>"$dir/tool-meta.txt"
		stop_tool
		exit 2
	fi
}

# --- tool lifecycle ---
start_falco() {
	local dir=$1
	mkdir -p "$dir/falco-metrics"
	rm -f "$dir/falco-metrics"/* "$dir/falco.log"
	BPF_BEFORE=$(bpf_prog_count)
	# Lenh goc (tai lieu Falco Fully Privileged / Modern eBPF) + cau hinh M6f:
	# docker pull falcosecurity/falco:latest
	# docker run --rm -it --privileged \
	#   -v /sys/kernel/tracing:/sys/kernel/tracing:ro \
	#   -v /var/run/docker.sock:/host/var/run/docker.sock \
	#   -v /proc:/host/proc:ro \
	#   -v /etc:/host/etc:ro \
	#   falcosecurity/falco:latest
	docker rm -f m6f-falco >/dev/null 2>&1 || true
	docker run -d --name m6f-falco --privileged \
		-v /sys/kernel/tracing:/sys/kernel/tracing:ro \
		-v /var/run/docker.sock:/host/var/run/docker.sock \
		-v /proc:/host/proc:ro \
		-v /etc:/host/etc:ro \
		-v "$dir/falco-metrics:/metrics" \
		"$FALCO_IMG" \
		falco \
		-o engine.kind=modern_ebpf \
		-o stdout_output.enabled=false \
		-o syslog_output.enabled=false \
		-o file_output.enabled=true \
		-o file_output.filename=/dev/null \
		-o metrics.enabled=true \
		-o metrics.interval=5s \
		-o metrics.output_rule=false \
		-o metrics.output_file=/metrics/falco_metrics.jsonl \
		-o metrics.kernel_event_counters_enabled=true \
		-o log_syslog=false \
		>"$dir/falco-docker.out" 2>&1 || {
		say "DUNG: docker run falco that bai"
		cat "$dir/falco-docker.out" || true
		exit 2
	}
	TOOL_KIND=falco
	# doi log container
	local i
	for ((i = 0; i < 90; i++)); do
		docker logs m6f-falco >"$dir/falco.log" 2>&1 || true
		grep -q "Opening 'syscall' source with modern BPF probe" "$dir/falco.log" 2>/dev/null && break
		sleep 1
	done
	if ! grep -q "Opening 'syscall' source with modern BPF probe" "$dir/falco.log" 2>/dev/null; then
		say "DUNG: Falco khong san sang"
		docker logs m6f-falco >"$dir/falco.log" 2>&1 || true
		stop_tool
		exit 2
	fi
	sleep 1
	require_bpf_attached "FALCO"
	TOOL_CG=$(docker_cgroup m6f-falco)
	TOOL_USEC0=$(scope_usage_usec "$TOOL_CG")
}

start_tetra() {
	local dir=$1 mode=$2 # def|sysenter
	rm -f "$dir/tetra.log" "$dir/tetra-metrics.txt"
	BPF_BEFORE=$(bpf_prog_count)
	docker rm -f m6f-tetra >/dev/null 2>&1 || true
	# Lenh goc (tai lieu Tetragon Deploy as a container / Stable v1.7.0):
	# docker run --name tetragon --rm -d \
	#   --pid=host --cgroupns=host --privileged \
	#   -v /sys/kernel/btf/vmlinux:/var/lib/tetragon/btf \
	#   quay.io/cilium/tetragon:v1.7.0
	local args=(
		-d --name m6f-tetra
		--pid=host --cgroupns=host --privileged
		-v /sys/kernel/btf/vmlinux:/var/lib/tetragon/btf
		-p 127.0.0.1:2112:2112
	)
	local cmd=(/usr/bin/tetragon --export-filename /dev/null --metrics-server :2112)
	if [[ $mode == sysenter ]]; then
		args+=(-v "$TP_YAML:/etc/tetragon/m6f-sysenter.yaml:ro")
		cmd+=(--tracing-policy /etc/tetragon/m6f-sysenter.yaml)
	fi
	docker run "${args[@]}" "$TETRA_IMG" "${cmd[@]}" >"$dir/tetra-docker.out" 2>&1 || {
		say "DUNG: docker run tetragon that bai ($mode)"
		cat "$dir/tetra-docker.out" || true
		exit 2
	}
	TOOL_KIND=tetra
	local i
	for ((i = 0; i < 90; i++)); do
		docker logs m6f-tetra >"$dir/tetra.log" 2>&1 || true
		grep -q 'Listening for events' "$dir/tetra.log" 2>/dev/null && break
		sleep 1
	done
	if ! grep -q 'Listening for events' "$dir/tetra.log" 2>/dev/null; then
		say "DUNG: Tetragon khong san sang ($mode)"
		docker logs m6f-tetra >"$dir/tetra.log" 2>&1 || true
		stop_tool
		exit 2
	fi
	if [[ $mode == sysenter ]]; then
		if ! grep -q 'raw_syscalls/sys_enter\|m6f-raw-sysenter\|generic_tracepoint' "$dir/tetra.log" 2>/dev/null; then
			# van cho metrics co attach
			sleep 1
		fi
	fi
	sleep 1
	require_bpf_attached "TETRA-$mode"
	TOOL_CG=$(docker_cgroup m6f-tetra)
	TOOL_USEC0=$(scope_usage_usec "$TOOL_CG")
}

start_hids() {
	local dir=$1 mode=$2 cg_or_pid=$3 # host|all ; cgroup path or "pid:N"
	mkdir -p "$dir"
	rm -f "$dir/collect.log" "$dir/collect.bin"
	BPF_BEFORE=$(bpf_prog_count)
	local unit="hids-m6f-$mode-$(date +%s%N)"
	local args=(-pmu host -duration 180s -out "$dir/collect.bin")
	if [[ $mode == all ]]; then
		args+=(-cgroup /sys/fs/cgroup)
	elif [[ $cg_or_pid == pid:* ]]; then
		args+=(-pid "${cg_or_pid#pid:}")
	else
		args+=(-cgroup "$cg_or_pid")
	fi
	systemd-run --scope --unit="$unit" --slice=system.slice -- \
		"$COLLECT" "${args[@]}" 2>"$dir/collect.log" &
	sleep 0.5
	COLL_PID=$(scope_main_pid "$unit") || COLL_PID=""
	TOOL_KIND=hids
	if ! wait_ready_file "$dir/collect.log"; then
		echo "KHONG_READY" >>"$dir/collect.log"
		say "DUNG: HIDS-$mode khong READY"
		stop_tool
		exit 2
	fi
	require_bpf_attached "HIDS-$mode"
	if [[ -n $COLL_PID ]]; then
		TOOL_CG=$(cgroup_path_of_pid "$COLL_PID")
		TOOL_USEC0=$(scope_usage_usec "$TOOL_CG")
	else
		TOOL_CG=""
		TOOL_USEC0=0
	fi
}

stop_tool() {
	local dir="${1:-}"
	local usec1=0 cpu_usec=0
	case $TOOL_KIND in
	falco)
		[[ -n $TOOL_CG ]] && usec1=$(scope_usage_usec "$TOOL_CG")
		cpu_usec=$((usec1 - TOOL_USEC0))
		docker logs m6f-falco >"${dir}/falco.log" 2>&1 || true
		docker rm -f m6f-falco >/dev/null 2>&1 || true
		if [[ -n $dir ]]; then
			python3 - "$dir" "$cpu_usec" <<'PY'
import json, pathlib, re, sys
d = pathlib.Path(sys.argv[1])
cpu = sys.argv[2]
drops = "?"
metrics = d / "falco-metrics" / "falco_metrics.jsonl"
if metrics.exists():
    last = None
    for line in metrics.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            last = json.loads(line)
        except Exception:
            continue
    if last:
        of = last.get("output_fields") or last.get("sample") or {}
        if isinstance(of, dict) and "scap.n_drops" in of:
            drops = of["scap.n_drops"]
log = (d / "falco.log").read_text(errors="replace") if (d / "falco.log").exists() else ""
m = re.search(r"event drop detected:\s*(\d+)\s*occurrences", log)
drop_log = m.group(1) if m else "?"
(d / "tool-stats.txt").write_text(
    f"tool=FALCO cpu_usec={cpu} scap_n_drops={drops} event_drop_occurrences={drop_log}\n"
)
print(f"tool=FALCO cpu_usec={cpu} scap_n_drops={drops} event_drop_occurrences={drop_log}")
PY
		fi
		;;
	tetra)
		[[ -n $TOOL_CG ]] && usec1=$(scope_usage_usec "$TOOL_CG")
		cpu_usec=$((usec1 - TOOL_USEC0))
		if [[ -n $dir ]]; then
			curl -sS --max-time 3 http://127.0.0.1:2112/metrics >"$dir/tetra-metrics.txt" 2>/dev/null || true
			docker logs m6f-tetra >"$dir/tetra.log" 2>&1 || true
		fi
		docker rm -f m6f-tetra >/dev/null 2>&1 || true
		if [[ -n $dir ]]; then
			python3 - "$dir" "$cpu_usec" <<'PY'
import pathlib, re, sys
d = pathlib.Path(sys.argv[1])
cpu = sys.argv[2]
txt = (d / "tetra-metrics.txt").read_text(errors="replace") if (d / "tetra-metrics.txt").exists() else ""
def g(name):
    m = re.search(rf"^{re.escape(name)}(?:\{{[^}}]*\}})?\s+([0-9.eE+-]+)$", txt, re.M)
    return m.group(1) if m else "?"
lost = g("tetragon_observer_ringbuf_events_lost_total")
qlost = g("tetragon_observer_ringbuf_queue_events_lost_total")
ovf = g("tetragon_notify_overflowed_events_total")
# tong missed prog
miss = 0.0
n = 0
for m in re.finditer(r"^tetragon_missed_prog_probes_total(?:\{[^}]*\})?\s+([0-9.eE+-]+)$", txt, re.M):
    miss += float(m.group(1)); n += 1
miss_s = f"{miss:.0f}" if n else "?"
(d / "tool-stats.txt").write_text(
    f"tool=TETRA cpu_usec={cpu} ringbuf_lost={lost} queue_lost={qlost} notify_overflow={ovf} missed_prog_sum={miss_s}\n"
)
print(f"tool=TETRA cpu_usec={cpu} ringbuf_lost={lost} queue_lost={qlost} notify_overflow={ovf} missed_prog_sum={miss_s}")
PY
		fi
		;;
	hids)
		[[ -n $TOOL_CG ]] && usec1=$(scope_usage_usec "$TOOL_CG")
		cpu_usec=$((usec1 - TOOL_USEC0))
		[[ -n $COLL_PID ]] && kill -INT "$COLL_PID" 2>/dev/null || true
		[[ -n $COLL_PID ]] && wait_pid_gone "$COLL_PID"
		COLL_PID=""
		if [[ -n $dir ]]; then
			python3 - "$dir" "$cpu_usec" <<'PY'
import re, subprocess, sys, pathlib
d = pathlib.Path(sys.argv[1])
cpu = sys.argv[2]
log = (d / "collect.log").read_text(errors="replace") if (d / "collect.log").exists() else ""
m = re.search(r"ban ghi doc duoc: (\d+) \| so lan dinh ghi: (\d+) \| mat: (\d+)", log)
recs = int(m.group(1)) if m else 0
drops = m.group(3) if m else "?"
rps = 0.0
binp = d / "collect.bin"
if binp.exists() and recs:
    out = subprocess.run(["./bin/rec-stat", str(binp)], capture_output=True, text=True).stdout
    mm = re.search(r"ts_enter nho nhat / lon nhat: (\d+) / (\d+)", out)
    if mm:
        span = (int(mm.group(2)) - int(mm.group(1))) / 1e9
        if span > 0:
            rps = recs / span
(d / "tool-stats.txt").write_text(
    f"tool=HIDS cpu_usec={cpu} ban_ghi={recs} ban_ghi_giay={rps:.1f} mat={drops}\n"
)
print(f"tool=HIDS cpu_usec={cpu} ban_ghi={recs} ban_ghi_giay={rps:.1f} mat={drops}")
PY
		fi
		;;
	esac
	TOOL_KIND=""
	TOOL_CG=""
	TOOL_USEC0=0
	# doi BPF ha xuong (toi da ~15s)
	local i
	for ((i = 0; i < 30; i++)); do
		[[ $(bpf_prog_count) -le $((BPF_BEFORE + 2)) ]] && break
		sleep 0.5
	done
}

start_tool_for() {
	local cond=$1 dir=$2 load_cg=$3 # load_cg: cgroup path or pid:N or empty
	case $cond in
	C0) TOOL_KIND=none; echo "tool=C0" >"$dir/tool-stats.txt" ;;
	FALCO) start_falco "$dir" ;;
	TETRA-def) start_tetra "$dir" def ;;
	TETRA-sysenter) start_tetra "$dir" sysenter ;;
	HIDS-host)
		if [[ -z $load_cg ]]; then
			say "DUNG: HIDS-host thieu cgroup/pid tai"
			exit 2
		fi
		start_hids "$dir" host "$load_cg"
		;;
	HIDS-all) start_hids "$dir" all /sys/fs/cgroup ;;
	*) say "DUNG: cond la $cond"; exit 2 ;;
	esac
}

# ---------- setup ----------
setup_pg() {
	docker rm -f pgtest >/dev/null 2>&1 || true
	docker run -d --name pgtest --cpuset-cpus 12-15 \
		-e POSTGRES_PASSWORD=m5test postgres:16-alpine \
		-c checkpoint_timeout=30min -c max_wal_size=8GB -c autovacuum=off >/dev/null
	local i ready=0
	for i in $(seq 1 90); do
		docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && ready=1 && break
		sleep 1
	done
	[[ $ready -eq 1 ]] || { say "LOI: pgtest khong ready"; exit 1; }
	for i in $(seq 1 5); do
		docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 && return 0
		sleep 3
	done
	say "LOI: pgbench -i that bai"; exit 1
}
setup_nginx() {
	docker rm -f m5-nginx >/dev/null 2>&1 || true
	local tmpd
	tmpd=$(mktemp -d)
	dd if=/dev/urandom of="$tmpd/f.bin" bs=4096 count=1 2>/dev/null
	chmod 755 "$tmpd" "$tmpd/f.bin"
	docker run -d --name m5-nginx --cpuset-cpus 12-15 \
		-v "$tmpd:/usr/share/nginx/html:ro" -p 18080:80 nginx:alpine >/dev/null
	sleep 2
}
pg_prep() { docker exec pgtest psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'VACUUM;' -c 'CHECKPOINT;' >/dev/null 2>&1 || true; }

freq_block() {
	local when=$1 load=$2
	local fdir="$OUTROOT/freq/${load}-${when}"
	mkdir -p "$fdir"
	say "freq_stamp $load $when"
	bash scripts/freq_stamp.sh 12 | tee "$fdir/cpu12.txt" || true
}

# ---------- T1 ----------
t1_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T1/$cond/run$run"
	mkdir -p "$dir"
	local spid t0 t1 fifo="$dir/in.fifo"
	rm -f "$fifo"; mkfifo "$fifo"
	exec 8<>"$fifo"
	taskset -c 12 "$SYSINJ" -n 10000000 <"$fifo" >"$dir/sysinj.log" 2>&1 &
	spid=$!
	sleep 0.3
	case $cond in
	C0) start_tool_for C0 "$dir" "" ;;
	HIDS-host) start_tool_for HIDS-host "$dir" "pid:$spid" ;;
	HIDS-all) start_tool_for HIDS-all "$dir" "" ;;
	*) start_tool_for "$cond" "$dir" "" ;;
	esac
	t0=$(date +%s%N)
	printf '.' >&8
	wait "$spid" 2>/dev/null || true
	t1=$(date +%s%N)
	exec 8>&-
	rm -f "$fifo"
	[[ $TOOL_KIND != none && -n $TOOL_KIND ]] && stop_tool "$dir" || true
	python3 -c "ns = ($t1 - $t0) / 10000000; print(f'{ns:.2f}')" >"$dir/value.txt"
	echo "T1 $cond run$run: $(cat "$dir/value.txt") ns/syscall"
	return 0
}

# ---------- T4 ----------
t4_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T4/$cond/run$run"
	mkdir -p "$dir"
	local cg
	cg=$(docker_cgroup m5-nginx)
	case $cond in
	C0) start_tool_for C0 "$dir" "" ;;
	HIDS-host) start_tool_for HIDS-host "$dir" "$cg" ;;
	HIDS-all) start_tool_for HIDS-all "$dir" "" ;;
	*) start_tool_for "$cond" "$dir" "" ;;
	esac
	taskset -c 16-19 wrk -t4 -c64 -d60s --latency "http://127.0.0.1:18080/f.bin" >"$dir/wrk.txt" 2>&1 || true
	[[ $TOOL_KIND != none && -n $TOOL_KIND ]] && stop_tool "$dir" || true
	grep -oE "Requests/sec:\s*[0-9.]+" "$dir/wrk.txt" | awk '{print $2}' >"$dir/value.txt" || true
	echo "T4 $cond run$run: $(cat "$dir/value.txt" 2>/dev/null) req/s"
	return 0
}

# ---------- T3 ----------
t3_sat_run() {
	local cond=$1 run=$2
	local dir="$OUTROOT/T3/$cond/run$run"
	mkdir -p "$dir"
	local cg
	cg=$(docker_cgroup pgtest)
	pg_prep
	case $cond in
	C0) start_tool_for C0 "$dir" "" ;;
	HIDS-host) start_tool_for HIDS-host "$dir" "$cg" ;;
	HIDS-all) start_tool_for HIDS-all "$dir" "" ;;
	*) start_tool_for "$cond" "$dir" "" ;;
	esac
	rm -f "$dir"/pglog.*
	taskset -c 16-19 docker exec -u postgres pgtest sh -c \
		"rm -f /tmp/pglog.*; pgbench -c 16 -j 4 -T 60 -l --log-prefix=/tmp/pglog -U postgres -d postgres" \
		>"$dir/pgbench.log" 2>&1 || true
	docker exec pgtest sh -c 'cat /tmp/pglog.* 2>/dev/null' >"$dir/pglog.1" 2>/dev/null || true
	[[ $TOOL_KIND != none && -n $TOOL_KIND ]] && stop_tool "$dir" || true
	python3 "$PARSE" pgbench "$dir/pglog.1" >"$dir/parse.txt" 2>&1 || true
	awk -F'\t' '{print $3}' "$dir/parse.txt" >"$dir/value.txt"
	echo "T3 $cond run$run: $(cat "$dir/value.txt" 2>/dev/null) tps"
	return 0
}

# ================= main =================
say "m6f overhead bat dau, RUNS=$RUNS, out=$OUTROOT"
{
	echo "=== sha256 5 file kien truc su ==="
	sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py analysis/m6c_stats.py tools/coreclk.c
	echo "=== git ==="
	git rev-parse --short HEAD
	echo "=== images ==="
	docker images --digests 'falcosecurity/falco' --format '{{.Repository}}:{{.Tag}} {{.Digest}}'
	docker images --digests 'quay.io/cilium/tetragon' --format '{{.Repository}}:{{.Tag}} {{.Digest}}'
	echo "=== falco version ==="
	docker run --rm "$FALCO_IMG" falco --version 2>&1 | head -20
	echo "=== tetra version ==="
	docker run --rm --entrypoint tetra "$TETRA_IMG" version 2>&1 | head -5
} | tee "$OUTROOT/versions.txt"

command -v wrk >/dev/null || { say "DUNG: khong co wrk goc"; exit 1; }
test -x "$COLLECT" || { say "DUNG: thieu $COLLECT"; exit 1; }
test -x "$SYSINJ" || { say "DUNG: thieu $SYSINJ"; exit 1; }
test -f "$TP_YAML" || { say "DUNG: thieu $TP_YAML"; exit 1; }

say "set user.slice AllowedCPUs=0-11,21-23"
systemctl set-property --runtime user.slice AllowedCPUs=0-11,21-23
USER_SLICE_SET=1

if ((${#RUNNING_CONTAINERS[@]})); then
	say "dung ${#RUNNING_CONTAINERS[@]} container san co"
	docker stop "${RUNNING_CONTAINERS[@]}" >/dev/null 2>&1 || true
fi

setup_pg
setup_nginx

# ----- T1 -----
freq_block truoc T1
say "T1"
for ((run = 1; run <= RUNS; run++)); do
	for cond in "${CONDS[@]}"; do
		t1_run "$cond" "$run" || { say "LOI T1 $cond $run"; exit 1; }
		sleep "$REST"
	done
	say "T1 tien do $run/$RUNS"
done
freq_block sau T1

# ----- T4 -----
freq_block truoc T4
say "T4 kich tran (wrk goc)"
for ((run = 1; run <= RUNS; run++)); do
	for cond in "${CONDS[@]}"; do
		t4_sat_run "$cond" "$run" || { say "LOI T4 $cond $run"; exit 1; }
		sleep "$REST"
	done
	say "T4 tien do $run/$RUNS"
done
freq_block sau T4

# ----- T3 -----
freq_block truoc T3
say "T3 kich tran"
for ((run = 1; run <= RUNS; run++)); do
	for cond in "${CONDS[@]}"; do
		t3_sat_run "$cond" "$run" || { say "LOI T3 $cond $run"; exit 1; }
		sleep "$REST"
	done
	say "T3 tien do $run/$RUNS"
done
freq_block sau T3

say "tong hop TSV"
python3 - "$OUTROOT" <<'PY'
import csv, glob, pathlib, re, sys
root = pathlib.Path(sys.argv[1])

def w(name, rows):
    with open(root / name, "w", newline="") as f:
        wtr = csv.writer(f, delimiter="\t")
        wtr.writerow(["load", "cond", "run", "value"])
        wtr.writerows(rows)

for load in ("T1", "T3", "T4"):
    rows = []
    for vf in sorted(glob.glob(str(root / load / "*" / "run*" / "value.txt"))):
        p = pathlib.Path(vf)
        txt = p.read_text().strip()
        if txt:
            rows.append([load, p.parent.parent.name, p.parent.name.replace("run", ""), txt])
    w(f"{load}.tsv", rows)

# tool CPU + drop bang phu
rows = []
for load in ("T1", "T3", "T4"):
    for sf in sorted(glob.glob(str(root / load / "*" / "run*" / "tool-stats.txt"))):
        p = pathlib.Path(sf)
        cond = p.parent.parent.name
        run = p.parent.name.replace("run", "")
        txt = p.read_text().strip()
        m = re.search(r"cpu_usec=(\d+)", txt)
        if m and cond != "C0":
            rows.append([load, cond, run, m.group(1)])
w("tool-cpu.tsv", rows)

rows = []
for load in ("T1", "T3", "T4"):
    for sf in sorted(glob.glob(str(root / load / "*" / "run*" / "tool-stats.txt"))):
        p = pathlib.Path(sf)
        cond = p.parent.parent.name
        run = p.parent.name.replace("run", "")
        txt = p.read_text().strip()
        # chon chi so drop chinh theo cong cu
        drop = None
        if "scap_n_drops=" in txt:
            drop = re.search(r"scap_n_drops=(\S+)", txt).group(1)
        elif "ringbuf_lost=" in txt:
            # tong lost ringbuf + queue
            a = re.search(r"ringbuf_lost=(\S+)", txt).group(1)
            b = re.search(r"queue_lost=(\S+)", txt).group(1)
            try:
                drop = str(float(a) + float(b))
            except Exception:
                drop = f"{a}+{b}"
        elif "mat=" in txt:
            drop = re.search(r"mat=(\S+)", txt).group(1)
        if drop is not None and cond != "C0":
            rows.append([load, cond, run, drop])
w("tool-drop.tsv", rows)
print("tsv xong")
PY

for f in "$OUTROOT"/T1.tsv "$OUTROOT"/T3.tsv "$OUTROOT"/T4.tsv; do
	[[ -f $f ]] || continue
	echo "===== $f ====="
	python3 analysis/m6c_stats.py "$f" | tee "$OUTROOT/$(basename "$f" .tsv).stats.txt"
done

# bang CPU/drop tong hop
{
	echo "===== tool-cpu (usage_usec) ====="
	[[ -f $OUTROOT/tool-cpu.tsv ]] && column -t "$OUTROOT/tool-cpu.tsv" | head -200
	echo "===== tool-drop ====="
	[[ -f $OUTROOT/tool-drop.tsv ]] && column -t "$OUTROOT/tool-drop.tsv" | head -200
	echo "===== tool-stats mau ====="
	find "$OUTROOT" -name tool-stats.txt | sort | while read -r p; do
		echo "-- $p"; cat "$p"
	done
} | tee "$OUTROOT/tool-summary.txt"

say "m6f overhead XONG"
echo "done" >"$STATUS"
