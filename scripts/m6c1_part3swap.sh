#!/usr/bin/env bash
# M6c-1 phan 3c chay lai: chi 2 luot swap (sau khi sua g3_swap) + ghep 3d cho swap.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?outroot}"
mkdir -p "$OUTROOT"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true

run_one() {
	local name=$1 pmu=$2
	local dir="$OUTROOT/$name"
	rm -rf "$dir/g3"
	mkdir -p "$dir"
	echo "=== $name: script=g3_swap.sh pmu=$pmu start=$(date -Is) ===" | tee "$dir/run.log"
	G3_BT_EVENTS=1 G3_ONLY="S2 S5" G3_OUTROOT="$dir/g3" \
		HIDS_COLLECT_EXTRA="$pmu" bash scripts/g3_swap.sh m5d >>"$dir/run.log" 2>&1
	echo "g3_exit=$?" >>"$dir/run.log"
	for s in S2 S5; do
		local b
		b=$(ls -t out/g3-"$s"-*.bin 2>/dev/null | head -1)
		[[ -n "$b" ]] && cp "$b" "$dir/$s.bin"
	done
}

run_one swap-on "-pmu on"
run_one swap-off "-pmu off"

docker start "${RUNNING[@]}" >/dev/null 2>&1 || true

{
	for name in swap-on swap-off; do
		for s in S2 S5; do
			dir="$OUTROOT/$name"
			bt="$dir/g3/$s.bpftrace.log"
			bin="$dir/$s.bin"
			kq="$dir/g3/$s-ketqua.txt"
			[[ -f "$bt" && -f "$bin" && -f "$kq" ]] || { echo "$name $s: thieu file"; continue; }
			tid=$(grep -a -m1 "wl pid=" "$kq" | sed -E 's/.*wl pid=([0-9]+).*/\1/')
			read -r WFROM WTO <<<"$(python3 scripts/g3_window.py "$bin" "$tid" | tr '\n' ' ')"
			echo "--- $name $s tid=$tid window=($WFROM,$WTO] ---"
			python3 scripts/m6b13_pair.py --btlog "$bt" --bin "$bin" --tid "$tid" \
				--from "$WFROM" --to "$WTO"
			python3 scripts/m6c1_pair_table.py --btlog "$bt" --bin "$bin" --tid "$tid" \
				--from "$WFROM" --to "$WTO" --label "$name $s"
		done
	done
} | tee "$OUTROOT/pair3d-swap.txt"

echo "part3swap xong"
