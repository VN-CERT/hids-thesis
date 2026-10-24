#!/usr/bin/env bash
# M6d phan A: dung 12 container -> m6d_eseries.sh -> khoi dong lai (ke ca loi).
set -uo pipefail
cd /root/hids || exit 1
OUT="validation/m6d-$(date +%Y%m%d)"
mkdir -p "$OUT" out/jobs
STATUS=out/jobs/m6d-a.status
LOG=out/jobs/m6d-a.log
START_TS=$(date -Iseconds)

write_status() {
	local st=$1 exitc=${2:-}
	{
		echo "ten=m6d-a"
		echo "bat_dau=$START_TS"
		echo "cap_nhat=$(date -Iseconds)"
		echo "trang_thai=$st"
		echo "outroot=$OUT"
		echo "log=$LOG"
		[[ -n $exitc ]] && echo "exit=$exitc"
	} >"$STATUS"
}

write_status "running"
: >"$LOG"
exec > >(tee -a "$LOG") 2>&1

mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
echo "m6d-a: dung ${#RUNNING[@]} container luc $(date -Iseconds)"
echo "${RUNNING[*]}" >"$OUT/containers-stopped.txt"
if ((${#RUNNING[@]})); then
	docker stop "${RUNNING[@]}" || true
fi

ec=0
bash scripts/m6d_eseries.sh "$OUT" || ec=$?

echo "m6d-a: khoi dong lai container luc $(date -Iseconds)"
if ((${#RUNNING[@]})); then
	docker start "${RUNNING[@]}" || echo "LOI khoi dong lai container"
fi
echo "m6d_a_driver_exit=$ec"
if [[ $ec -eq 0 ]]; then
	write_status "done" "$ec"
else
	write_status "failed" "$ec"
fi
exit "$ec"
