#!/usr/bin/env bash
# Buoc 2 dong M5d: chi phi BPF (nguyen van doan kiến trúc sư).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DATE=$(date +%Y%m%d)
OUTROOT="${M5D_CLOSE_OUT:-validation/m5d-${DATE}}"
COLLECT=./bin/hids-collect
mkdir -p "$OUTROOT"

run_bpf_measure() {
	local tag=$1
	local out="$OUTROOT/bpf-${tag}.txt"
	{
		echo "=== bpf measure $tag $(date -Iseconds) ==="
		sysctl -w kernel.bpf_stats_enabled=1
		bpftool prog show -j > /tmp/bpf_a.json
		sleep 30
		bpftool prog show -j > /tmp/bpf_b.json
		python3 -c "
import json
a={p['id']:p for p in json.load(open('/tmp/bpf_a.json'))}
b={p['id']:p for p in json.load(open('/tmp/bpf_b.json'))}
print('ten\tlan_moi_giay\tns_moi_lan')
for i,p in sorted(b.items()):
    n=p.get('name','')
    if not n.startswith('hids_'): continue
    q=a.get(i,{}); dc=p.get('run_cnt',0)-q.get('run_cnt',0); dt=p.get('run_time_ns',0)-q.get('run_time_ns',0)
    print(f'{n}\t{dc/30:.0f}\t{(dt/dc if dc else 0):.1f}')
"
		sysctl -w kernel.bpf_stats_enabled=0
	} >"$out" 2>&1
	echo "luu $out"
}

# --- ranh: collector tren decoy ---
DECOY=/sys/fs/cgroup/hids-m5d-bpf-ranh
mkdir -p "$DECOY"
unit_ranh="hids-m5d-bpf-ranh-$$"
systemd-run --scope --unit="$unit_ranh" --slice=system.slice -- \
	"$COLLECT" -cgroup "$DECOY" -duration 120s -out "$OUTROOT/bpf-ranh-collect.bin" \
	>"$OUTROOT/bpf-ranh-collect.log" 2>&1 &
sleep 1
for ((i = 0; i < 3000; i++)); do grep -qx READY "$OUTROOT/bpf-ranh-collect.log" 2>/dev/null && break; sleep 0.01; done
grep -qx READY "$OUTROOT/bpf-ranh-collect.log" || { echo "collector ranh khong READY" >&2; exit 1; }
run_bpf_measure ranh
systemctl stop "${unit_ranh}.scope" 2>/dev/null || true

# --- tai: T3-C1, do sau 10s pgbench ---
docker rm -f pgtest 2>/dev/null || true
docker run -d --name pgtest --cpuset-cpus 12-15 -e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
for i in $(seq 1 90); do docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 || true
pid=$(docker inspect -f '{{.State.Pid}}' pgtest)
cg=$(awk -F: '$1=="0"{print $3}' "/proc/$pid/cgroup")
cg="/sys/fs/cgroup${cg}"
unit_tai="hids-m5d-bpf-tai-$$"
systemd-run --scope --unit="$unit_tai" --slice=system.slice -- \
	"$COLLECT" -cgroup "$cg" -duration 120s -out "$OUTROOT/bpf-tai-collect.bin" \
	>"$OUTROOT/bpf-tai-collect.log" 2>&1 &
sleep 1
for ((i = 0; i < 3000; i++)); do grep -qx READY "$OUTROOT/bpf-tai-collect.log" 2>/dev/null && break; sleep 0.01; done
grep -qx READY "$OUTROOT/bpf-tai-collect.log" || { echo "collector tai khong READY" >&2; exit 1; }
taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres >/dev/null 2>&1 &
pb_pid=$!
sleep 10
run_bpf_measure tai
wait "$pb_pid" 2>/dev/null || true
systemctl stop "${unit_tai}.scope" 2>/dev/null || true
docker rm -f pgtest 2>/dev/null || true

echo "step2 bpf xong"
