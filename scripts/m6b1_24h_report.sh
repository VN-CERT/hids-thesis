#!/usr/bin/env bash
# Ghi mot dong bao cao gio vao out/jobs/m6b1-24h.hourly.tsv
set -euo pipefail
OUT="${1:-validation/m6b1-24h-$(date +%Y%m%d)}"
DATA="$OUT/data"
HOURLY="out/jobs/m6b1-24h.hourly.tsv"
[[ -d $DATA ]] || exit 0
wall=$(date -Is)
bin=$(find "$DATA" -name '*.bin' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
proc=$(find "$DATA" -name 'proc-*.tsv.zst' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
host=$(find "$DATA" -name 'host-*.tsv.zst' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
status=$(find "$DATA" -name 'status.tsv' | head -1)
rps=0
drops=0
rss=0
if [[ -n $status ]]; then
	rps=$(tail -1 "$status" | awk -F'\t' '{print $2}' 2>/dev/null || echo 0)
	drops=$(tail -1 "$status" | awk -F'\t' '{print $3}' 2>/dev/null || echo 0)
	rss=$(tail -1 "$status" | awk -F'\t' '{print $8}' 2>/dev/null || echo 0)
fi
if [[ ! -f $HOURLY ]]; then
	echo -e "wall\tbin_bytes\tproc_bytes\thost_bytes\trecs_per_s\tkernel_drops\trss_kb" >"$HOURLY"
fi
echo -e "$wall\t$bin\t$proc\t$host\t$rps\t$drops\t$rss" >>"$HOURLY"
