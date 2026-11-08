#!/usr/bin/env bash
# lab2_lib.sh — helper LAB-2 pha 1 (dung lai cgroup cua lab1c)
# shellcheck disable=SC2034
set -euo pipefail

REPO="${LAB2_REPO:-/root/collector}"
DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
VAL="${LAB2_VAL:-$REPO/validation/lab2-$DAY}"

# shellcheck source=scripts/lab1c_lib.sh
source "$REPO/scripts/lab1c_lib.sh"

lab2_cgroup_nginx() { lab1c_cgroup_nginx; }
lab2_cgroup_postgres() { lab1c_cgroup_postgres; }

lab2_ensure_nhan() {
	mkdir -p "$REPO/lab"
	if [[ ! -f $REPO/lab/nhan-tan-cong-lab2.tsv ]]; then
		printf 'run_id\tlop\tid\tatt_ck\tcong_cu\tnhip_tham_so\tmuc_tranh_chap\tsong_sinh_cua\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tt_bat_dau_wall\tt_ket_thuc_wall\toracle_ket_qua\tghi_chu\n' \
			>"$REPO/lab/nhan-tan-cong-lab2.tsv"
	fi
	if [[ ! -f $REPO/lab/nhan-tid-lab2.tsv ]]; then
		printf 'run_id\tid\tlop\ttid\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tcomm\tpid\tghi_chu\n' \
			>"$REPO/lab/nhan-tid-lab2.tsv"
	fi
}

lab2_sanitize_cpu0() { lab1c_sanitize_cpu0; }

# tid implant + con chau dang song
lab2_descendants() {
	local root=$1
	local q=("$root") out=()
	local p c
	while ((${#q[@]})); do
		p=${q[0]}
		q=("${q[@]:1}")
		out+=("$p")
		for c in $(pgrep -P "$p" 2>/dev/null || true); do
			q+=("$c")
		done
	done
	printf '%s\n' "${out[@]}"
}
