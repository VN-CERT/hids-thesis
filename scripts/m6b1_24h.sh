#!/usr/bin/env bash
# m6b1_24h.sh — thu lien tuc 24h (systemd-run), bao moi gio.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

OUT="${M6B1_24H_OUT:-validation/m6b1-24h-$(date +%Y%m%d)}"
mkdir -p "$OUT" out/jobs
LOG="out/jobs/m6b1-24h.log"
STATUS="out/jobs/m6b1-24h.status"

echo "running $(date -Is)" >"$STATUS"
echo "out=$OUT" >>"$STATUS"

# Chon 2-3 cgroup container dang chay (docker cgroup v2).
mapfile -t CGS < <(docker ps -q 2>/dev/null | head -3 | while read -r id; do
	docker inspect -f '{{.State.Pid}}' "$id" 2>/dev/null | while read -r pid; do
		awk -v p="$pid" '$1==p {print $2}' /proc/"$pid"/cgroup 2>/dev/null | head -1
	done
done | sort -u)
if [[ ${#CGS[@]} -eq 0 ]]; then
	CGS=(/sys/fs/cgroup)
fi
{
	echo "containers_cgroup:"
	docker ps --format '{{.Names}}' 2>/dev/null | head -5 || true
	echo "cgroup_flags:"
	for c in "${CGS[@]}"; do echo "-cgroup $c"; done
} | tee "$OUT/targets.txt"

ARGS=(./bin/hids-collect -datadir "$OUT/data" -duration 0 -zstd-level 2 -min-free-gb 50)
for c in "${CGS[@]}"; do
	[[ -n $c ]] && ARGS+=(-cgroup "$c")
done

exec "${ARGS[@]}" >>"$LOG" 2>&1
