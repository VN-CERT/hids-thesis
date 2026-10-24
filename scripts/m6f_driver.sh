#!/usr/bin/env bash
# Driver M6f: chay overhead, ghi status/log cho systemd-run.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

mkdir -p out/jobs
STATUS=out/jobs/m6f.status
LOG=out/jobs/m6f.log
DAY=$(date +%Y%m%d)
OUT="validation/m6f-${DAY}"
mkdir -p "$OUT"

echo "$(date -Is) start out=$OUT" | tee "$STATUS"
exec > >(tee -a "$LOG") 2>&1

bash scripts/m6f_overhead.sh "$OUT"
ec=$?
echo "$(date -Is) exit=$ec" | tee -a "$STATUS"
# dam bao ve sinh (overhead trap cung lam)
docker rm -f m6f-falco m6f-tetra pgtest m5-nginx >/dev/null 2>&1 || true
systemctl set-property --runtime user.slice AllowedCPUs= 2>/dev/null || true
# kernel sach: khong con prog hids_/falco/tetragon
sleep 2
n=$(bpftool prog show 2>/dev/null | rg -c 'name hids_|falco|tetragon|scap' || true)
echo "bpf_leftover_match=$n"
echo "$ec" >out/jobs/m6f.exit
exit "$ec"
