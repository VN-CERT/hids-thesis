#!/usr/bin/env bash
# Chuan doan (b) L=7 SAU phu luc 1.4 — wl chay trong system.slice de duoc CPU 0.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || exit 1

OUT="${1:-validation/lab1-20261024/lieu/D3-chandoan-sau-1.4.txt}"
MEM_STEPS=$(awk '/^mem_steps/{print $2}' /root/hids/out/m4-loops.txt)
dir=out/lab1-d3-chand-L7-after14
mkdir -p "$dir" "$(dirname "$OUT")"
: >"$OUT"

systemctl set-property --runtime user.slice AllowedCPUs=1-7
EFF=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)
echo "cpuset.cpus.effective=$EFF" | tee -a "$OUT"
[[ $EFF == 1-7 ]] || { echo "FAIL: effective != 1-7" | tee -a "$OUT"; exit 1; }

docker stop lab0-postgres lab0-nginx >/dev/null 2>&1 || true
pkill -f 'stress-ng --stream' 2>/dev/null || true
sleep 1

{
	echo "=== CHAN DOAN SAU 1.4 L=7 $(date -Is) mem_steps=$MEM_STEPS ==="
	echo "--- ps CPU 0 (truoc do) ---"
	ps -eo pid,psr,cgroup,comm | awk '$2==0'
} | tee -a "$OUT"

fifo=$dir/fifo
rm -f "$fifo" "$dir"/*
mkfifo "$fifo"
exec 9<>"$fifo"

# wl trong system.slice — khong bi AllowedCPUs cua user.slice
systemd-run --scope --quiet --slice=system.slice \
	--working-directory="$(pwd)" \
	--unit=lab1-chand-wl \
	-- /bin/bash -c "exec taskset -c 0 ./bin/wl -loops '$MEM_STEPS' mem 500" \
	<"$fifo" >"$dir/wl.log" 2>&1 &
scope_pid=$!
sleep 0.8
wl_pid=$(pgrep -n -f './bin/wl -loops' || true)
if [[ -z ${wl_pid:-} ]]; then
	echo "FAIL: khong co wl" | tee -a "$OUT"
	exit 1
fi
echo "wl_pid=$wl_pid scope_pid=$scope_pid wl_psr=$(ps -o psr= -p "$wl_pid" | tr -d ' ')" | tee -a "$OUT"

for i in $(seq 1 200); do
	[[ $(cat /proc/$wl_pid/wchan 2>/dev/null) == pipe_read ]] && break
	sleep 0.05
done
printf '.' >&9
sleep 0.2
for i in $(seq 1 200); do
	[[ $(cat /proc/$wl_pid/wchan 2>/dev/null) == pipe_read ]] && break
	sleep 0.05
done

stress-ng --stream 7 --taskset 1-7 --timeout 90 >"$dir/stress.log" 2>&1 &
stress_pid=$!
sleep 2
{
	echo "--- (a) ghim stress-ng ---"
	for p in $(pgrep stress-ng); do
		echo "$p $(cat /proc/$p/comm) psr=$(ps -o psr= -p $p | tr -d ' ') aff=$(taskset -cp $p 2>/dev/null | awk -F: '{print $2}')"
	done
} | tee -a "$OUT"

printf '.' >&9
# bpftrace cung system.slice de gan
systemd-run --scope --quiet --slice=system.slice --unit=lab1-chand-bt \
	-- bpftrace -e 'tracepoint:sched:sched_switch /cpu == 0/ { if (@t) { @oncpu_ns[args->prev_comm] = sum(nsecs - @t); } @t = nsecs; } interval:s:60 { exit(); }' \
	>"$dir/bpftrace.raw" 2>&1 || true

kill "$stress_pid" 2>/dev/null || true
wait "$stress_pid" 2>/dev/null || true
printf '.' >&9
exec 9>&-
wait "$scope_pid" 2>/dev/null || true
kill "$wl_pid" 2>/dev/null || true
rm -f "$fifo"
pkill -f 'stress-ng --stream' 2>/dev/null || true

python3 - "$dir/bpftrace.raw" "$OUT" <<'PY'
import re, sys
raw, outp = sys.argv[1], sys.argv[2]
text = open(raw, errors="replace").read()
items = [(int(m.group(2)), m.group(1).strip().strip('"')) for m in re.finditer(r'@oncpu_ns\[(.*?)\]:\s*(\d+)', text)]
items.sort(reverse=True)
window = 60e9
def is_wl(c): return c == "wl" or c.endswith("/wl")
def is_idle(c): return c.startswith("swapper")
def is_kthread(c):
    prefixes = ("kworker", "ksoftirq", "rcu", "migration", "cpuhp", "idle_inject",
                "scsi_", "watchdog", "kcompact", "psimon", "pool_work", "mm_")
    return any(c.startswith(p) for p in prefixes) or c in ("systemd", "kthreadd")
wl = sum(n for n,c in items if is_wl(c))
idle = sum(n for n,c in items if is_idle(c))
other = [(n,c) for n,c in items if not is_wl(c) and not is_idle(c)]
ob = sum(n for n,_ in other)
ob_pct = 100.0 * ob / window
user = [(n,c) for n,c in other if not is_kthread(c)]
user_pct = 100.0 * sum(n for n,_ in user) / window
lines = ["--- (b) top 15 @oncpu_ns CPU 0 ---",
         f"{'rank':<5} {'comm':<22} {'oncpu_ns':>15} {'pct':>9}"]
for i,(n,c) in enumerate(items[:15],1):
    lines.append(f"{i:<5} {c:<22} {n:>15} {100*n/window:>8.4f}%")
lines += [
    f"wl_pct={100*wl/window:.6f}",
    f"idle_pct={100*idle/window:.6f}",
    f"OTHER_BUSY_PCT={ob_pct:.6f}",
    f"user_space_pct={user_pct:.6f}",
    f"user_space_comms={[c for _,c in user]}",
]
open(outp, "a").write("\n".join(lines) + "\n")
print("\n".join(lines))
# quyet dinh
if ob_pct < 1.0:
    dec = "GIU_0247"
elif ob_pct < 2.0 and len(user) == 0:
    dec = "DOI_0246_can_L6"  # can them L=6 < 1%
elif len(user) > 0 or ob_pct >= 2.0:
    dec = "DUNG"
else:
    dec = "DUNG"
print(f"DECISION={dec}")
open(outp, "a").write(f"DECISION={dec}\n")
open("/tmp/lab1-14-dec.txt", "w").write(dec + f"\nOTHER_BUSY_PCT={ob_pct:.6f}\n")
PY
echo "=== XONG $(date -Is) ===" | tee -a "$OUT"
