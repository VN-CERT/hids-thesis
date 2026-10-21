#!/usr/bin/env bash
# M6c-1 phan 3c/3d: 4 lan G3 (S2+S5) doi thu tu gan probe x che do PMU.
#   (1) g3.sh      -pmu on   (2) g3.sh      -pmu off
#   (3) g3_swap.sh -pmu on   (4) g3_swap.sh -pmu off
# Giu .bin (KEEP_RAW). Container dung trong luc chay, khoi dong lai cuoi.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?outroot}"
mkdir -p "$OUTROOT"

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "dung container: ${RUNNING[*]}"
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true

run_one() {
	local name=$1 script=$2 pmu=$3
	local dir="$OUTROOT/$name"
	mkdir -p "$dir"
	echo "=== $name: script=$script pmu=$pmu start=$(date -Is) ===" | tee "$dir/run.log"
	G3_BT_EVENTS=1 G3_ONLY="S2 S5" G3_OUTROOT="$dir/g3" \
		HIDS_COLLECT_EXTRA="$pmu" bash "scripts/$script" m5d >>"$dir/run.log" 2>&1
	echo "g3_exit=$?" >>"$dir/run.log"
	# Giu .bin cua S2/S5 (KEEP_RAW): bin moi nhat trong out/ cho tung kich ban.
	for s in S2 S5; do
		local b
		b=$(ls -t out/g3-"$s"-*.bin 2>/dev/null | head -1)
		[[ -n "$b" ]] && cp "$b" "$dir/$s.bin"
	done
	tail -5 "$dir/run.log"
}

run_one norm-on g3.sh "-pmu on"
run_one norm-off g3.sh "-pmu off"
run_one swap-on g3_swap.sh "-pmu on"
run_one swap-off g3_swap.sh "-pmu off"

docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
echo "container sau: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"

echo "=== 3d: ghep moc thoi gian (m6b13_pair.py) + bang us ==="
{
	for name in norm-on norm-off swap-on swap-off; do
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
} | tee "$OUTROOT/pair3d.txt"

echo "part3 xong"
