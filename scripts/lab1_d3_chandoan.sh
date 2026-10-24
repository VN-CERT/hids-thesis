#!/usr/bin/env bash
# Chuan doan D3 L=7/L=6 — KHONG collector. Ghi D3-chandoan.txt
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

OUT="${1:-validation/lab1-20261024/lieu/D3-chandoan.txt}"
MEM_STEPS=$(awk '/^mem_steps/{print $2}' /root/hids/out/m4-loops.txt)
[[ -n $MEM_STEPS && $MEM_STEPS -gt 0 ]] || { echo "thieu mem_steps" >&2; exit 1; }
WL=./bin/wl
mkdir -p "$(dirname "$OUT")" out
: >"$OUT"

run_one_level() {
	local L=$1
	local dir="out/lab1-d3-chand-L${L}"
	mkdir -p "$dir"
	rm -f "$dir"/*
	local fifo="$dir/fifo"
	mkfifo "$fifo"
	exec 9<>"$fifo"

	echo "=== CHAN DOAN L=$L $(date -Is) mem_steps=$MEM_STEPS ===" | tee -a "$OUT"
	# wl tren CPU 0
	taskset -c 0 "$WL" -loops "$MEM_STEPS" mem 500 <"$fifo" >"$dir/wl.log" 2>&1 &
	local wl_pid=$!
	sleep 0.5
	# cho wl toi wait_go dau
	local i w
	for ((i = 0; i < 200; i++)); do
		w=$(cat /proc/$wl_pid/wchan 2>/dev/null || true)
		[[ $w == pipe_read ]] && break
		sleep 0.05
	done
	printf '.' >&9
	sleep 0.2
	for ((i = 0; i < 200; i++)); do
		w=$(cat /proc/$wl_pid/wchan 2>/dev/null || true)
		[[ $w == pipe_read ]] && break
		sleep 0.05
	done

	# stress-ng ghim 1-7 (cung cach nhu lan chay lai)
	local stress_pid=""
	if ((L > 0)); then
		stress-ng --stream "$L" --taskset 1-7 --timeout 90 >"$dir/stress.log" 2>&1 &
		stress_pid=$!
		sleep 2
	fi

	# (a) kiem ghim
	{
		echo "--- (a) ghim stress-ng sau khoi dong (L=$L) ---"
		echo "wl_pid=$wl_pid wl_psr=$(ps -o psr= -p $wl_pid | tr -d ' ') wl_aff=$(taskset -cp $wl_pid 2>/dev/null | awk -F: '{print $2}')"
		local lot=0
		local p
		for p in $(pgrep -d ' ' stress-ng 2>/dev/null || true); do
			local comm psr aff
			comm=$(cat /proc/$p/comm 2>/dev/null || echo '?')
			psr=$(ps -o psr= -p $p 2>/dev/null | tr -d ' ' || echo '?')
			aff=$(taskset -cp $p 2>/dev/null | awk -F: '{print $2}' | tr -d ' ' || echo '?')
			echo "$p $comm psr=$psr aff=$aff"
			# lot neu psr=0 hoac aff chua 0
			if [[ $psr == 0 ]]; then
				echo "  -> LOT: psr=0"
				lot=1
			fi
			if echo "$aff" | grep -qE '(^|,)0(,|$)|^0-|^0$'; then
				echo "  -> LOT: aff chua CPU 0 ($aff)"
				lot=1
			fi
		done
		if ! pgrep stress-ng >/dev/null 2>&1; then
			echo "(khong co stress-ng — L=0?)"
		fi
		echo "LOT_STRESS_NG_CPU0=$lot"
	} | tee "$dir/a.txt" | tee -a "$OUT"

	# bat wl chay (dot thu 2)
	printf '.' >&9

	# (b) bpftrace 60s tren CPU 0
	bpftrace -e 'tracepoint:sched:sched_switch /cpu == 0/ { if (@t) { @oncpu_ns[args->prev_comm] = sum(nsecs - @t); } @t = nsecs; } interval:s:60 { exit(); }' \
		>"$dir/bpftrace.raw" 2>&1 || true

	# dung stress + wl
	[[ -n $stress_pid ]] && kill "$stress_pid" 2>/dev/null || true
	wait "$stress_pid" 2>/dev/null || true
	printf '.' >&9
	exec 9>&-
	kill "$wl_pid" 2>/dev/null || true
	wait "$wl_pid" 2>/dev/null || true
	rm -f "$fifo"
	pkill -f 'stress-ng --stream' 2>/dev/null || true

	# phan tich bpftrace
	python3 - "$dir/bpftrace.raw" "$L" "$dir/b.txt" <<'PY'
import re, sys
raw_path, L, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(raw_path, errors="replace").read()
# @oncpu_ns[comm]: total
pat = re.compile(r'@oncpu_ns\[(.*?)\]:\s*(\d+)')
items = []
for m in pat.finditer(text):
    comm = m.group(1).strip().strip('"')
    ns = int(m.group(2))
    items.append((ns, comm))
items.sort(reverse=True)
window_ns = 60 * 1_000_000_000
# wl comm co the la "wl" 
def is_wl(c):
    return c == "wl" or c.endswith("/wl") or c == "bin/wl"

wl_ns = sum(ns for ns, c in items if is_wl(c))
other_ns = sum(ns for ns, c in items if not is_wl(c))
other_pct = 100.0 * other_ns / window_ns
lines = []
lines.append(f"--- (b) top 10 comm @oncpu_ns tren CPU 0 (L={L}, cua so 60s) ---")
lines.append(f"{'rank':<5} {'comm':<20} {'oncpu_ns':>15} {'pct_cua_so':>10}")
for i, (ns, c) in enumerate(items[:10], 1):
    lines.append(f"{i:<5} {c:<20} {ns:>15} {100.0*ns/window_ns:>9.4f}%")
lines.append(f"wl_oncpu_ns={wl_ns} ({100.0*wl_ns/window_ns:.4f}% cua so)")
lines.append(f"other_than_wl_oncpu_ns={other_ns}")
lines.append(f"other_than_wl_pct_of_60s={other_pct:.6f}")
top_other = next(((ns, c) for ns, c in items if not is_wl(c)), (0, "(khong)"))
lines.append(f"top_other_comm={top_other[1]} ns={top_other[0]}")
lines.append(f"OTHER_PCT={other_pct:.6f}")
open(out_path, "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
# raw tail for audit
open(out_path.replace("b.txt", "bpftrace.tail"), "w").write("\n".join(text.strip().splitlines()[-40:]))
PY
	cat "$dir/b.txt" >>"$OUT"
	echo "" >>"$OUT"
}

# dam bao may sach
pkill -f 'stress-ng --stream' 2>/dev/null || true
pkill -f './bin/wl' 2>/dev/null || true
sleep 1

run_one_level 7
sleep 3
run_one_level 6

echo "=== XONG chuan doan $(date -Is) ===" | tee -a "$OUT"
cat "$OUT"
