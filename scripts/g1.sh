#!/usr/bin/env bash
# g1.sh: chay steal-probe 600 giay (interval 1s) va tu giay thu 60 chay song song
# /root/dk2.sh de tao tai. Ket thuc thi in san lenh tong hop cho file vua ghi.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

PROBE=./bin/steal-probe
DK2=/root/dk2.sh
TOTAL_SEC=600
INTERVAL=1s

if [[ $EUID -ne 0 ]]; then
	echo "g1.sh: can chay bang root" >&2
	exit 1
fi
if [[ ! -x $PROBE ]]; then
	echo "g1.sh: khong thay $PROBE, chay 'make build' truoc" >&2
	exit 1
fi
if [[ ! -f $DK2 ]]; then
	echo "g1.sh: khong thay $DK2" >&2
	exit 1
fi

mkdir -p out
OUT="out/g1-$(date +%Y%m%d-%H%M%S).csv"

sleep_until() {
	local target=$1 now diff
	now=$(date +%s)
	diff=$((target - now))
	if ((diff > 0)); then
		sleep "$diff"
	fi
}

echo "g1: ghi vao $OUT, chay $TOTAL_SEC giay, interval $INTERVAL"
START=$(date +%s)
"$PROBE" -interval "$INTERVAL" -duration "${TOTAL_SEC}s" -out "$OUT" &
PROBE_PID=$!

DK2_PID=""
for ((m = 1; m <= TOTAL_SEC / 60; m++)); do
	sleep_until $((START + m * 60))
	if ((m == 1)); then
		echo "g1: giay thu 60, chay song song: bash $DK2"
		bash "$DK2" &
		DK2_PID=$!
	fi
	echo "g1: phut thu $m/$((TOTAL_SEC / 60))"
done

wait "$PROBE_PID"
PROBE_STATUS=$?
if [[ -n $DK2_PID ]]; then
	wait "$DK2_PID"
fi

echo "g1: steal-probe ket thuc voi ma $PROBE_STATUS, du lieu o $OUT"
echo
echo "Lenh tong hop:"
echo "  ./bin/steal-summary $OUT"
echo "  ./bin/steal-summary -bucket 20s $OUT"
