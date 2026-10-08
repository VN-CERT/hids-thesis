#!/usr/bin/env bash
# Ghi out/jobs/m5d.status moi 60s khi unit hids-m5d active.
set -uo pipefail
ST=/root/hids/out/jobs/m5d.status
LOG=/root/hids/out/jobs/m5d.log
while true; do
	if systemctl is-active hids-m5d.service >/dev/null 2>&1; then
		st=running
	else
		st=inactive
	fi
	last=$(tail -1 "$LOG" 2>/dev/null || echo "")
	echo "updated=$(date -Iseconds)" >"$ST"
	echo "unit=$st" >>"$ST"
	echo "last_log_line=$last" >>"$ST"
	[[ $st == inactive ]] && break
	sleep 60
done
# ket thuc
code=$(systemctl show hids-m5d.service -p ExecMainStatus --value 2>/dev/null || echo "?")
echo "exit_status=$code" >>"$ST"
echo "finished=$(date -Iseconds)" >>"$ST"
