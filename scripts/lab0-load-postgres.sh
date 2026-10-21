#!/usr/bin/env bash
# lab0-load-postgres.sh — tai benign co dinh cho lab0-postgres (pgbench, muc TPS co dinh).
# CHUA chay tai khi viet script nay; chi chay khi duoc giao nhiem vu tai.
#
# Cach dung: lab0-load-postgres.sh <TPS> <thoi_luong_giay> [thu_muc_log]
#   TPS            : toc do muc tieu cua pgbench (-R)
#   thoi_luong    : so giay chay pgbench (-T)
#   thu_muc_log   : mac dinh /srv/hids-data/hids-collector/pgbench-logs
#                   file log la <thu_muc_log>/pglog.<pid-pgbench>
#
# Co dinh: pgbench -c 16 -j 4, container lab0-postgres, DB postgres qua 127.0.0.1:15432.
# Chong nhieu: TRUOC moi luot pgbench, chay VACUUM; roi CHECKPOINT; qua docker exec
# (hai lenh rieng, dung thu tu nay) de khoi chay khong dinh checkpoint/autovacuum giua luot.
set -euo pipefail

CONTAINER="${LAB0_PG_CONTAINER:-lab0-postgres}"
PGPASSWORD_VAL="${LAB0_PG_PASSWORD:-hids-lab0}"

if [[ $# -lt 2 || $# -gt 3 ]]; then
	echo "cach dung: $0 <TPS> <thoi_luong_giay> [thu_muc_log]" >&2
	exit 2
fi
TPS=$1
DURATION=$2
LOG_DIR=${3:-/srv/hids-data/hids-collector/pgbench-logs}

[[ $TPS =~ ^[0-9]+$ ]] || { echo "TPS phai la so nguyen duong: $TPS" >&2; exit 2; }
[[ $DURATION =~ ^[0-9]+$ ]] || { echo "thoi_luong phai la so nguyen duong: $DURATION" >&2; exit 2; }

mkdir -p "$LOG_DIR"

echo "lab0-load-postgres: VACUUM; qua docker exec $CONTAINER"
docker exec -e PGPASSWORD="$PGPASSWORD_VAL" "$CONTAINER" \
	psql -U postgres -h 127.0.0.1 -v ON_ERROR_STOP=1 -c 'VACUUM;' postgres

echo "lab0-load-postgres: CHECKPOINT; qua docker exec $CONTAINER"
docker exec -e PGPASSWORD="$PGPASSWORD_VAL" "$CONTAINER" \
	psql -U postgres -h 127.0.0.1 -v ON_ERROR_STOP=1 -c 'CHECKPOINT;' postgres

echo "lab0-load-postgres: pgbench -R $TPS -c 16 -j 4 -T $DURATION -l --log-prefix=$LOG_DIR/pglog"
PGPASSWORD="$PGPASSWORD_VAL" pgbench -h 127.0.0.1 -p 15432 -U postgres \
	-R "$TPS" -c 16 -j 4 -T "$DURATION" -l --log-prefix="$LOG_DIR/pglog" postgres
