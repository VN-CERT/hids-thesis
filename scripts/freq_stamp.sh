#!/usr/bin/env bash
# freq_stamp.sh <cpu>: dau tan so cho mot dot do (M6c-2 phan 3).
# Kiem sha256 tools/coreclk.c (ban cua kien truc su), build bin/coreclk neu
# thieu, chay 3 lan coreclk tren <cpu> (khong perf), in date -Is, 3 gia tri
# GHz_wall va trung vi. Ma thoat 0.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
CPU="${1:?can tham so <cpu>}"
EXPECTED=88ef821eb062855b0189af1568d25e310b53f1e0c1e29e35e360282515d97706
actual=$(sha256sum tools/coreclk.c | awk '{print $1}')
if [[ $actual != "$EXPECTED" ]]; then
	echo "LOI: tools/coreclk.c sha256=$actual khac $EXPECTED" >&2
	exit 1
fi
if [[ ! -x bin/coreclk ]]; then
	gcc -O2 -o bin/coreclk tools/coreclk.c
fi
date -Is
vals=()
for i in 1 2 3; do
	g=$(taskset -c "$CPU" bin/coreclk 100000000 | awk '{for (k = 1; k <= NF; k++) if ($k ~ /^GHz_wall=/) { sub("GHz_wall=", "", $k); print $k }}')
	echo "lan $i: GHz_wall=$g"
	vals+=("$g")
done
printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR] = $1} END {print "trung vi GHz_wall=" a[int((NR + 1) / 2)]}'
exit 0
