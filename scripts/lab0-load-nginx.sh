#!/usr/bin/env bash
# lab0-load-nginx.sh — tai benign co dinh cho lab0-nginx (wrk2, muc RPS co dinh).
# CHUA chay tai khi viet script nay; chi chay khi duoc giao nhiem vu tai.
#
# Cach dung: lab0-load-nginx.sh <RPS> <thoi_luong_giay>
#   RPS         : toc do muc tieu cua wrk2 (-R)
#   thoi_luong  : so giay chay wrk2 (-d<giay>s)
#
# Co dinh: taskset -c 0-3 wrk2 -t4 -c64 --latency, dich http://127.0.0.1:18080/file4k.bin
# (file 4 KiB do lab0-nginx phuc vu, da kiem chung 4096 byte o LAB-0/LAB-0b).
set -euo pipefail

FILE_4KIB="${LAB0_NGINX_FILE:-file4k.bin}"
URL="http://127.0.0.1:18080/${FILE_4KIB}"

if [[ $# -ne 2 ]]; then
	echo "cach dung: $0 <RPS> <thoi_luong_giay>" >&2
	exit 2
fi
RPS=$1
DURATION=$2

[[ $RPS =~ ^[0-9]+$ ]] || { echo "RPS phai la so nguyen duong: $RPS" >&2; exit 2; }
[[ $DURATION =~ ^[0-9]+$ ]] || { echo "thoi_luong phai la so nguyen duong: $DURATION" >&2; exit 2; }

echo "lab0-load-nginx: taskset -c 0-3 wrk2 -t4 -c64 -R $RPS -d${DURATION}s --latency $URL"
taskset -c 0-3 wrk2 -t4 -c64 -R "$RPS" -d"${DURATION}s" --latency "$URL"
