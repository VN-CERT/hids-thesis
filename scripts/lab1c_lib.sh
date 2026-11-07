#!/usr/bin/env bash
# lab1c_lib.sh — cơ chế vào cgroup + helper LAB-1c (Phụ lục 1.9 / 1.9c)
# shellcheck disable=SC2034
set -euo pipefail

REPO="${LAB1C_REPO:-/root/collector}"
DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
VAL="${LAB1C_VAL:-$REPO/validation/lab1c-$DAY}"

lab1c_cgroup_nginx() {
	local id
	id=$(docker inspect -f '{{.Id}}' lab0-nginx)
	echo "/sys/fs/cgroup/system.slice/docker-${id}.scope"
}

lab1c_cgroup_postgres() {
	local id
	id=$(docker inspect -f '{{.Id}}' lab0-postgres)
	echo "/sys/fs/cgroup/system.slice/docker-${id}.scope"
}

# chay_trong_cgroup <cgroup_path> <lệnh...>
# Shell tự ghi $$ vào cgroup.procs rồi exec; con cháu kế thừa.
chay_trong_cgroup() {
	local cg=$1
	shift
	[[ -d $cg ]] || { echo "chay_trong_cgroup: thieu cgroup $cg" >&2; return 1; }
	[[ -w $cg/cgroup.procs ]] || { echo "chay_trong_cgroup: khong ghi duoc $cg/cgroup.procs" >&2; return 1; }
	# shellcheck disable=SC2016
	sh -c 'echo $$ > "$0/cgroup.procs" || exit 91; exec "$@"' "$cg" "$@"
}

# chay_trong_cgroup_bg <cgroup_path> <pidfile> <lệnh...>
# Chạy nền; ghi PID THẬT (đã vào cgroup) vào pidfile. Trả về 0 khi pidfile có.
chay_trong_cgroup_bg() {
	local cg=$1
	local pidfile=$2
	shift 2
	[[ -d $cg ]] || { echo "chay_trong_cgroup_bg: thieu cgroup $cg" >&2; return 1; }
	rm -f "$pidfile"
	# shellcheck disable=SC2016
	sh -c 'echo $$ > "$0/cgroup.procs" || exit 91; echo $$ > "$1"; shift; exec "$@"' \
		"$cg" "$pidfile" "$@" &
	local wrap=$!
	local i
	for i in $(seq 1 50); do
		if [[ -s $pidfile ]]; then
			return 0
		fi
		if ! kill -0 "$wrap" 2>/dev/null; then
			echo "chay_trong_cgroup_bg: wrapper chet som" >&2
			return 1
		fi
		sleep 0.05
	done
	echo "chay_trong_cgroup_bg: timeout cho pidfile" >&2
	return 1
}

# Dự phòng: systemd-run --scope; trả về đường dẫn scope qua stdout cuối dòng SCOPE=...
chay_trong_scope() {
	local unit=$1
	shift
	systemd-run --scope --unit="$unit" --collect "$@"
}

lab1c_ensure_nhan() {
	mkdir -p "$REPO/lab"
	if [[ ! -f $REPO/lab/nhan-tan-cong-lab1c.tsv ]]; then
		printf 'run_id\tlop\tid\tatt_ck\tcong_cu\tnhip_tham_so\tmuc_tranh_chap\tsong_sinh_cua\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tt_bat_dau_wall\tt_ket_thuc_wall\toracle_ket_qua\tghi_chu\n' \
			>"$REPO/lab/nhan-tan-cong-lab1c.tsv"
	fi
	if [[ ! -f $REPO/lab/nhan-tid-lab1c.tsv ]]; then
		printf 'run_id\tid\tlop\ttid\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tcomm\tpid\tghi_chu\n' \
			>"$REPO/lab/nhan-tid-lab1c.tsv"
	fi
}

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

lab1c_sanitize_cpu0() {
	systemctl set-property --runtime user.slice AllowedCPUs=1-7
	local eff
	eff=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)
	echo "$eff"
	[[ $eff == 1-7 ]]
}
