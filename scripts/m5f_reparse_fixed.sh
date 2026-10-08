#!/usr/bin/env bash
# Tái tạo m5f_parse.tsv từ lượt T3-R/T4-R đã đo (không chạy lại benchmark).
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${M5F_OUT:-validation/m5f-20261008}"
M5F_PARSE=./analysis/m5f_parse.py

meta_field() {
	local file=$1 key=$2
	grep -oE "${key}=[0-9]+" "$file" | head -1 | cut -d= -f2
}

echo "label	kieu	n	toc_do_per_s	lat_tb_ms	p50_ms	p99_ms	max_ms	lag_tb_ms	lag_p99_ms	loi	dat_muc	hop_ly" >"$OUTROOT/m5f_parse.tsv"

for pct in 25 50; do
	for cond in C0 C1 C2; do
		for run in 1 2 3; do
			dir="$OUTROOT/T3-R${pct}/${cond}/run${run}"
			[[ -f $dir/meta.txt ]] || continue
			rate=$(meta_field "$dir/meta.txt" target_tps)
			label="T3-R${pct} ${cond} run${run}"
			shopt -s nullglob
			pg=("$dir"/pglog.*)
			shopt -u nullglob
			[[ ${#pg[@]} -gt 0 ]] || continue
			line=$(python3 "$M5F_PARSE" pgbench --target "$rate" "${pg[@]}")
			echo "$label	$line" >>"$OUTROOT/m5f_parse.tsv"
		done
	done
done

for pct in 25 50; do
	for cond in C0 C1 C2; do
		for run in 1 2 3; do
			dir="$OUTROOT/T4-R${pct}/${cond}/run${run}"
			[[ -f $dir/wrk2.txt && -f $dir/meta.txt ]] || continue
			rate_int=$(meta_field "$dir/meta.txt" target_rps)
			label="T4-R${pct} ${cond} run${run}"
			line=$(python3 "$M5F_PARSE" wrk2 --target "$rate_int" "$dir/wrk2.txt")
			echo "$label	$line" >>"$OUTROOT/m5f_parse.tsv"
		done
	done
done

echo "wrote $OUTROOT/m5f_parse.tsv"
