#!/usr/bin/env bash
# lab1_watch.sh — ghi 1 dong suc-khoe.tsv moi gio (unit hids-lab1-watch).
set -euo pipefail
DATADIR="${LAB1_BENIGN_DIR:-/srv/hids-data/lab1-benign}"
TSV="$DATADIR/suc-khoe.tsv"
STATUS="$DATADIR/status.tsv"
mkdir -p "$DATADIR"

if [[ ! -f $TSV ]]; then
	printf 'wall\trecords_per_sec\tkernel_drops_delta\tproc_drops_delta\trss_bytes\tcpu_seconds_total\tpmu_pct\tfree_gb\n' >"$TSV"
fi

wall=$(date -Is)
free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')

# status.tsv cua collector: lay dong cuoi
records_per_sec=0
kernel_drops_delta=0
proc_drops_delta=0
rss_bytes=0
cpu_seconds_total=0
pmu_pct=0

if [[ -f $STATUS ]]; then
	# thu parse header + last line
	python3 - "$STATUS" <<'PY' >"$DATADIR/.watch-parse.tmp" || true
import sys
path = sys.argv[1]
lines = open(path).read().splitlines()
# bo comment
rows = [l for l in lines if l and not l.startswith("#")]
if len(rows) < 2:
    print("0\t0\t0\t0\t0\t0")
    raise SystemExit
hdr = rows[0].split("\t")
last = rows[-1].split("\t")
d = dict(zip(hdr, last))
# ten cot co the khac nhau qua phien; thu nhieu alias
def g(*names, default="0"):
    for n in names:
        if n in d and d[n] not in ("", "-"):
            return d[n]
    return default
rps = g("records_per_sec", "recs_per_sec", "rate")
kd = g("kernel_drops_delta", "kernel_drops", "drops_kernel")
pd = g("proc_drops_delta", "proc_drops", "drops_proc")
rss = g("rss_bytes", "rss")
cpu = g("cpu_seconds_total", "cpu_sec", "cpu_seconds")
pmu = g("pmu_pct", "pmu_flag_pct", "pmu_ratio")
print(f"{rps}\t{kd}\t{pd}\t{rss}\t{cpu}\t{pmu}")
PY
	IFS=$'\t' read -r records_per_sec kernel_drops_delta proc_drops_delta rss_bytes cpu_seconds_total pmu_pct \
		<"$DATADIR/.watch-parse.tmp" || true
fi

# neu pmu_pct la ti le 0-1, doi ra %
python3 -c "
v=float('${pmu_pct}' or 0)
if 0 < v <= 1.0:
    v=v*100
print(v)
" >"$DATADIR/.pmu.tmp"
pmu_pct=$(cat "$DATADIR/.pmu.tmp")

# RSS/CPU tu /proc neu collector dang chay
cpid=$(pgrep -x hids-collect | head -1 || true)
if [[ -n ${cpid:-} ]]; then
	rss_bytes=$(awk '/VmRSS/{print $2*1024}' /proc/"$cpid"/status 2>/dev/null || echo "$rss_bytes")
	# cpu_seconds_total: utime+stime / clock ticks
	hz=$(getconf CLK_TCK)
	cpu_seconds_total=$(awk -v hz="$hz" '{print ($14+$15)/hz}' /proc/"$cpid"/stat 2>/dev/null || echo "$cpu_seconds_total")
fi

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
	"$wall" "$records_per_sec" "$kernel_drops_delta" "$proc_drops_delta" \
	"$rss_bytes" "$cpu_seconds_total" "$pmu_pct" "$free_gb" >>"$TSV"
