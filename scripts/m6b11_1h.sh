#!/usr/bin/env bash
# m6b11_1h.sh <outdir> — chay 1 gio dung cau hinh 24h (hscd_redis + qdrant),
# tom tat CPU/RSS/records_per_sec/mat tu status.tsv.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

OUT="${1:?outdir}"
mkdir -p "$OUT"

cg_of() {
	local name=$1 pid rel
	pid=$(docker inspect -f '{{.State.Pid}}' "$name")
	rel=$(awk -F: '$1=="0"{print $3; exit}' "/proc/$pid/cgroup")
	echo "/sys/fs/cgroup${rel}"
}
CG_REDIS=$(cg_of hscd_redis)
CG_QDRANT=$(cg_of qdrant)
{
	echo "start=$(date -Is)"
	echo "hscd_redis cgroup: $CG_REDIS"
	echo "qdrant cgroup: $CG_QDRANT"
	git rev-parse --short HEAD
	sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py
} | tee "$OUT/run-meta.txt"

./bin/hids-collect -datadir "$OUT/data" -cgroup "$CG_REDIS" -cgroup "$CG_QDRANT" \
	-duration 1h -min-free-gb 50 >"$OUT/collect.log" 2>&1
echo "collector_exit=$? end=$(date -Is)" | tee -a "$OUT/run-meta.txt"

ST="$OUT/data/status.tsv"
{
	echo "--- status.tsv (nguyen van) ---"
	cat "$ST"
	echo "--- tom tat ---"
	python3 - "$ST" <<'PY'
import datetime, sys
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1])][1:]
rows = [r for r in rows if len(r) >= 9]
def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
t0, t1 = ts(rows[0][0]), ts(rows[-1][0])
c0, c1 = float(rows[0][7]), float(rows[-1][7])
rps = [float(r[1]) for r in rows]
print(f"so_dong_status={len(rows)}")
print(f"cpu_seconds_dau={c0:.3f} cuoi={c1:.3f} delta={c1-c0:.3f}")
print(f"cpu_%_mot_loi={(c1-c0)/(t1-t0)*100:.2f}% (delta_cpu / {t1-t0:.0f}s giua dong dau va cuoi)")
print(f"rss_bytes_cuoi={rows[-1][6]}")
print(f"records_per_sec_min={min(rps):.2f} records_per_sec_max={max(rps):.2f} so_dong_am={sum(1 for v in rps if v < 0)}")
print(f"tong_kernel_drops_delta={sum(int(r[2]) for r in rows)} tong_proc_drops_delta={sum(int(r[8]) for r in rows)}")
PY
} | tee "$OUT/run1h-summary.txt"
