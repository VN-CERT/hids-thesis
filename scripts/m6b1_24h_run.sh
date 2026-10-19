#!/usr/bin/env bash
# Chay thu 24h: unit hidsrun-24h, ghi /srv/hids-data/<hostname>/
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

HOST=$(hostname -s)
OUT="/srv/hids-data/${HOST}"
mkdir -p "$OUT" out/jobs
LOG=out/jobs/m6b1-24h.log
STATUS=out/jobs/m6b1-24h.status
HOURLY=out/jobs/m6b1-24h.hourly.tsv

echo "start=$(date -Is)" >"$STATUS"
echo "out=$OUT" >>"$STATUS"
echo "binary_commit=$(git rev-parse --short HEAD)" >>"$STATUS"
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py >>"$STATUS"

# 2 container ban nhat
mapfile -t TOP2 < <(docker stats --no-stream --format '{{.CPUPerc}}\t{{.Name}}' \
	| sed 's/%//' | sort -nr | awk 'NF>=2{print $2}' | head -2)
cg_of() {
	local name=$1 pid rel
	pid=$(docker inspect -f '{{.State.Pid}}' "$name")
	rel=$(awk -F: '$1=="0"{print $3; exit}' "/proc/$pid/cgroup")
	echo "/sys/fs/cgroup${rel}"
}
CG1=$(cg_of "${TOP2[0]}")
CG2=$(cg_of "${TOP2[1]}")
{
	echo "containers: ${TOP2[0]} ${TOP2[1]}"
	echo "cgroup1=$CG1"
	echo "cgroup2=$CG2"
} | tee "$OUT/targets.txt"

# Bao cao gio (chay song song)
(
	echo -e "wall\tbin_bytes\tproc_bytes\thost_bytes\trecs_per_s\tkernel_drops\tdisk_skipped\tfree_gb\trss_bytes\tcpu_seconds\tproc_drops" >"$HOURLY"
	for i in $(seq 1 24); do
		sleep 3600
		wall=$(date -Is)
		bin=$(find "$OUT" -name '*.bin' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
		proc=$(find "$OUT" -name 'proc-*.tsv.zst' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
		hostb=$(find "$OUT" -name 'host-*.tsv.zst' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')
		st=$(find "$OUT" -name status.tsv | head -1 || true)
		rps=0; drops=0; skip=0; free=0; rss=0; cpu=0; pd=0
		if [[ -n ${st:-} && -f $st ]]; then
			# wall records_per_sec kernel_drops_delta disk_skipped_total bin_bytes free_gb rss cpu proc_drops
			eval "$(tail -1 "$st" | awk -F'\t' '{printf "rps=%s; drops=%s; skip=%s; free=%s; rss=%s; cpu=%s; pd=%s\n", $2,$3,$4,$6,$7,$8,$9}')"
		fi
		# Ty le nen: uoc luong tu record_size*recs vs bin — lay tu status bin_bytes cot 5 neu co
		echo -e "${wall}\t${bin}\t${proc}\t${hostb}\t${rps}\t${drops}\t${skip}\t${free}\t${rss}\t${cpu}\t${pd}" >>"$HOURLY"
		echo "progress=$i/24 wall=$wall" >"$STATUS.tmp"
		cat "$STATUS.tmp" >>"$STATUS" || true
		rm -f "$STATUS.tmp"
	done
) &
echo $! > out/jobs/m6b1-24h-hourly.pid

# Collector 24h
timeout --signal=TERM 86400 ./bin/hids-collect \
	-datadir "$OUT" \
	-cgroup "$CG1" -cgroup "$CG2" \
	-duration 24h \
	-min-free-gb 50 \
	>>"$LOG" 2>&1
ec=$?
echo "exit=$ec" >>"$STATUS"
echo "end=$(date -Is)" >>"$STATUS"
exit $ec
