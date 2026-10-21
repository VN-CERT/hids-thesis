#!/usr/bin/env bash
# M6c-1 5b: coreclk + perf stat o L=0 va L=22 (stress-ng --stream 22 worker
# tren 0-19,21-23 nhu E4), ghim CPU 20, 3 lan moi muc, khong collector.
# Truoc/sau moi lan: dong "cpu " cua /proc/stat (steal = cot 8, phai ~ 0).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?outdir}"
mkdir -p "$OUTROOT"
exec > >(tee -a "$OUTROOT/coreclk.log") 2>&1

sha256sum tools/coreclk.c
ls -l bin/coreclk

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true

run_level() {
	local L=$1 i
	local spid=""
	if ((L > 0)); then
		stress-ng --stream "$L" --taskset 0-19,21-23 --timeout 300 >/dev/null 2>&1 &
		spid=$!
		sleep 10
	fi
	for i in 1 2 3; do
		echo "--- L=$L lan=$i ---"
		echo "proc_stat_truoc: $(grep '^cpu ' /proc/stat)"
		perf stat -e cycles:u,instructions:u taskset -c 20 bin/coreclk 100000000
		echo "proc_stat_sau: $(grep '^cpu ' /proc/stat)"
	done
	[[ -n "$spid" ]] && { kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null; }
	sleep 2
}

run_level 0
run_level 22

docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
echo "coreclk xong $(date -Is)"
