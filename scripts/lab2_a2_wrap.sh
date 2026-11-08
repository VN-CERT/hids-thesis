#!/usr/bin/env bash
# lab2_a2_wrap.sh — chay implant + tick 1s (cung cgroup) de moc nhan ±1s
# Arg: <duong-dan-implant> <tick-log>
set -euo pipefail
IMP=${1:?}
TICKLOG=${2:?}
: >"$TICKLOG"
chmod +x "$IMP" || true
"$IMP" &
IPID=$!
echo "$IPID" >"${TICKLOG}.implant_pid"
# tick de sinh syscall deu den khi implant chet hoac bi kill (ca wrapper)
while kill -0 "$IPID" 2>/dev/null; do
	echo "$(date -Is) tick" >>"$TICKLOG"
	# doc /proc cua implant — van la syscall cua wrapper
	cat "/proc/$IPID/stat" >/dev/null 2>&1 || true
	sleep 1
done
wait "$IPID" 2>/dev/null || true
exit 0
