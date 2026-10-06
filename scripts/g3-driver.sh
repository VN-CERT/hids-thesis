#!/usr/bin/env bash
set -uo pipefail
cd /root/hids
make build >>/dev/null 2>&1 || true
STATUS=out/jobs/g3-driver.status
LOG=out/jobs/g3-driver.log
mkdir -p out/jobs
echo "status=running" >"$STATUS"
echo "started=$(date -Is)" >>"$STATUS"
echo "progress=0/1 g3.sh" >>"$STATUS"
if bash scripts/g3.sh >>"$LOG" 2>&1; then
  ec=0
else
  ec=$?
fi
if [[ $ec -eq 0 ]]; then
  echo "status=done" >"$STATUS"
else
  echo "status=failed" >"$STATUS"
fi
echo "exit=$ec" >>"$STATUS"
echo "finished=$(date -Is)" >>"$STATUS"
