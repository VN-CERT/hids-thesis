# Chinh sach don du lieu — xem docs/tasks/don-du-lieu.md
# shellcheck shell=bash
HIDS_MIN_FREE_GB=20

# Kiem tra git truoc benchmark: bo qua out/, validation/, reports/, syscallbpf .o; bo qua moi '??'.
hids_require_clean_git() {
	[[ ${G7_SKIP_GIT_CHECK:-}${M5_SKIP_GIT_CHECK:-} == *1* ]] && return 0
	local st path
	while read -r st path _; do
		[[ -z $st ]] && continue
		[[ $st == '??' ]] && continue
		path="${path%/}"
		if [[ $path == out/* || $path == validation/* || $path == reports/* || $path == internal/syscallbpf/* ]]; then
			continue
		fi
		echo "hids: cay git khong sach: $st $path" >&2
		return 1
	done < <(git status --porcelain 2>/dev/null | awk '{print $1, $2}')
	return 0
}

hids_require_disk_for_long_job() {
	local avail_kb
	avail_kb=$(df -Pk "${HIDS_DISK_CHECK_PATH:-/}" | awk 'NR==2 {print $4}')
	if (( avail_kb < HIDS_MIN_FREE_GB * 1024 * 1024 )); then
		echo "hids: tu choi chay job dai: dung luong trong < ${HIDS_MIN_FREE_GB} GiB (df -Pk /)" >&2
		df -h "${HIDS_DISK_CHECK_PATH:-/}"
		exit 1
	fi
}

hids_print_df_at_job_end() {
	echo "--- df -h (ket thuc job) ---"
	df -h "${HIDS_DISK_CHECK_PATH:-/}"
}

hids_drop_collect_bin() {
	local bf=$1
	[[ ${KEEP_RAW:-} == 1 ]] && return 0
	[[ -f $bf ]] && rm -f "$bf"
}

# Goi sau khi da tom tat va kiem so ban ghi; giu .stats, .periodic, result.txt.
m5_drop_collect_artifacts() {
	local dir=$1
	local bf="$dir/collect.bin"
	if [[ -f $bf ]]; then
		echo "bin_bytes=$(stat -c %s "$bf" 2>/dev/null || echo 0)" >>"$dir/result.txt"
		hids_drop_collect_bin "$bf"
	fi
}

hids_drop_out_bin() {
	local bin=$1
	[[ ${KEEP_RAW:-} == 1 ]] && return 0
	if [[ -f $bin ]]; then
		rm -f "$bin"
		echo "da xoa $bin (giu ${bin}.stats ${bin}.periodic); dat KEEP_RAW=1 de giu file .bin"
	fi
}
