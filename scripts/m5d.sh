#!/usr/bin/env bash
# m5d.sh — verify O1, BPF stats, ma tran M5d (T1–T4 + T*-R).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DATE=$(date +%Y%m%d)
OUTROOT="${M5D_OUT:-validation/m5d-${DATE}}"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
LOG="out/jobs/m5d.log"
mkdir -p out/jobs "$(dirname "$OUTROOT")"

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
trap start_containers EXIT

{
	echo "=== m5d $(date -Iseconds) out=$OUTROOT ==="
	stop_containers
	make build

	echo "=== buoc 2: verify O1 ==="
	M5D_VERIFY_OUT="$OUTROOT/verify-o1" bash scripts/m5d_verify_o1.sh

	echo "=== buoc 3: BPF stats idle ==="
	mkdir -p "$OUTROOT/bpf"
	sysctl -w kernel.bpf_stats_enabled=1 >/dev/null
	DECOY=/sys/fs/cgroup/hids-m5d-idle
	mkdir -p "$DECOY"
	./bin/hids-collect -cgroup "$DECOY" -duration 15s -zstd-level 0 -out "$OUTROOT/bpf/idle.bin" \
		>"$OUTROOT/bpf/idle-collect.log" 2>&1 &
	ip=$!
	sleep 1
	bash scripts/m5d_bpf_hids.sh "$OUTROOT/bpf/idle-start.json"
	sleep 14
	bash scripts/m5d_bpf_hids.sh "$OUTROOT/bpf/idle-end.json"
	wait "$ip" || true

	echo "=== buoc 3: BPF stats T3-C1 (60s) ==="
	docker rm -f pgtest 2>/dev/null || true
	docker run -d --name pgtest --cpuset-cpus 12-15 -e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
	for i in $(seq 1 60); do docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
	pid=$(docker inspect -f '{{.State.Pid}}' pgtest)
	cg=$(awk -F: '$1=="0"{print $3}' "/proc/$pid/cgroup")
	cg="/sys/fs/cgroup${cg}"
	systemd-run --scope --unit="hids-m5d-t3c1-bpf-$$" --slice=system.slice -- \
		./bin/hids-collect -cgroup "$cg" -duration 120s -out "$OUTROOT/bpf/t3c1.bin" \
		>"$OUTROOT/bpf/t3c1-collect.log" 2>&1 &
	sleep 1
	bash scripts/m5d_bpf_hids.sh "$OUTROOT/bpf/t3c1-start.json"
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -i -U postgres -d postgres >/dev/null 2>&1 || true
	taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres >/dev/null 2>&1 || true
	bash scripts/m5d_bpf_hids.sh "$OUTROOT/bpf/t3c1-end.json"
	systemctl stop "hids-m5d-t3c1-bpf-$$.scope" 2>/dev/null || true
	python3 - "$OUTROOT/bpf" <<'PY'
import json, sys
from pathlib import Path
d = Path(sys.argv[1])
def delta(a, b):
    am = {p["name"]: p for p in json.loads(a.read_text())}
    bm = {p["name"]: p for p in json.loads(b.read_text())}
    rows = []
    for name in sorted(set(am) | set(bm)):
        if not name.startswith("hids_"):
            continue
        pa, pb = am.get(name), bm.get(name)
        if not pa or not pb:
            continue
        dr = int(pb.get("run_time_ns", 0)) - int(pa.get("run_time_ns", 0))
        dc = int(pb.get("run_cnt", 0)) - int(pa.get("run_cnt", 0))
        avg = dr / dc if dc else 0
        rows.append((name, avg, dc, dr))
    out = d / "bpf-delta.tsv"
    with out.open("w") as f:
        f.write("prog\tavg_ns\tdelta_run_cnt\tdelta_run_time_ns\n")
        for name, avg, dc, dr in rows:
            f.write(f"{name}\t{avg:.1f}\t{dc}\t{dr}\n")
    for name, avg, dc, dr in rows:
        if name in ("hids_sys_enter", "hids_sys_enter_fentry"):
            print(f"bpf_load {name} avg_ns={avg:.1f} delta_cnt={dc}")
PY
	sysctl -w kernel.bpf_stats_enabled=0 >/dev/null

	echo "=== buoc 4: ma tran kich tran ==="
	M5_SKIP_GIT_CHECK=1 M5D_MODE=1 M5_OUTROOT="$OUTROOT" M5_RUNS=5 bash scripts/m5.sh

	echo "=== buoc 4: tải cố định ==="
	python3 - "$OUTROOT" <<'PY' >"$OUTROOT/diag-summary.tsv"
import sys
from pathlib import Path
root = Path(sys.argv[1])
print("load\tvariant\tmetric\tlat_avg\tp99\tIWI_delta\tCAL_delta\tRES_delta\tcgroup_usec_delta\tbpf_sys_enter_avg_ns_runs_per_s\tdir")
for load in ("T3", "T4"):
    d = root / load / "C0" / "run1" / "result.txt"
    if not d.exists():
        continue
    m = {}
    for line in d.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            m[k] = v
    metric = m.get("value", "")
    print(f"{load}\tC0\t{metric}\t\t\t\t\t\t\t\t{root}/{load}/C0")
PY
	M5_SKIP_GIT_CHECK=1 M5C_BEST_HOOK=tracepoint M5C_DIAG_SUMMARY="$OUTROOT/diag-summary.tsv" \
		M5C_FIXED_OUT="$OUTROOT" M5C_FIXED_RUNS=3 bash scripts/m5c_fixed.sh

	echo "=== m5d xong $OUTROOT ==="
} | tee -a "$LOG"
