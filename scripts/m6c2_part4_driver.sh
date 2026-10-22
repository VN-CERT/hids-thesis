#!/usr/bin/env bash
set -uo pipefail
cd /root/hids || exit 1
OUT=validation/m6c2-20261022/e4p
mkdir -p "$OUT"
mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true
bash scripts/m6c2_e4p.sh "$OUT"
ec=$?
docker start "${RUNNING[@]}" >/dev/null 2>&1 || true
echo "e4p_driver_exit=$ec"
