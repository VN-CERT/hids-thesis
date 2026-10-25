#!/usr/bin/env bash
# Driver M6f-b: FALCO-all vs C0 vs HIDS-host.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

mkdir -p out/jobs
STATUS=out/jobs/m6fb.status
LOG=out/jobs/m6fb.log
DAY=$(date +%Y%m%d)
OUT="validation/m6f-b-${DAY}"
mkdir -p "$OUT"

echo "$(date -Is) start out=$OUT" | tee "$STATUS"
exec > >(tee -a "$LOG") 2>&1

bash scripts/m6fb_overhead.sh "$OUT"
ec=$?
echo "$(date -Is) exit=$ec" | tee -a "$STATUS"
docker rm -f m6fb-falco pgtest m5-nginx >/dev/null 2>&1 || true
systemctl set-property --runtime user.slice AllowedCPUs= 2>/dev/null || true
sleep 2
n=$(bpftool prog show 2>/dev/null | grep -cE 'name hids_|falco|tetragon|scap' || true)
echo "bpf_leftover_match=$n"
echo "$ec" >out/jobs/m6fb.exit
exit "$ec"
