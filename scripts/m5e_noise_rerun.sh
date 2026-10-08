#!/usr/bin/env bash
# Chay lai cac luot noise=1 (T3-R, T4-R, T4), xen ke C0,C1,C2 trong tung load.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" GOMODCACHE="${GOMODCACHE:-/root/go/pkg/mod}"
export PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

OUTROOT="${M5E_OUT:-validation/m5e-$(date +%Y%m%d)}"
WINDOWS="${M5E_NOISE_WINDOWS:-$OUTROOT/noise-push-windows.tsv}"
MAP="$OUTROOT/noise-run-map.tsv"
LIST="$OUTROOT/noise-reruns.list"
LOG="out/jobs/m5e-noise-rerun.log"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"

stop_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker stop "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}
start_containers() {
	[[ -f $CONTAINERS ]] || return 0
	while read -r n; do
		[[ -z $n || $n == \#* ]] && continue
		docker start "$n" >/dev/null 2>&1 || true
	done <"$CONTAINERS"
}
trap 'start_containers; hids_print_df_at_job_end' EXIT

mkdir -p out/jobs
exec >>"$LOG" 2>&1
echo "=== m5e_noise_rerun $(date -Iseconds) out=$OUTROOT ==="

python3 analysis/m5e_noise.py "$OUTROOT" "$WINDOWS"
[[ -s $LIST ]] || { echo "khong co luot noise; xong"; exit 0; }

make build
stop_containers

export M5_SKIP_GIT_CHECK=1 M5C_FIXED_FORCE=1 M5E_ONLY_FIXED=1
export M5C_DIAG_SUMMARY="$OUTROOT/diag-summary.tsv" M5C_FIXED_OUT="$OUTROOT"

# shellcheck disable=SC1091
source scripts/m5c_fixed.sh

setup_pg
setup_nginx

# Xen ke C0,C1,C2 theo thu tu trong list (load,run gom nhom).
while IFS=$'\t' read -r load cond run _start _end _nw; do
	[[ -z ${load:-} || $load == load ]] && continue
	dir="$OUTROOT/$load/$cond/$run"
	rm -f "$dir/result.txt"
	echo "RERUN_NOISE $load $cond $run $(date -Iseconds)"
	case $load in
	T3-R25) t3_fixed_run 25 "$cond" "${run#run}" ;;
	T3-R50) t3_fixed_run 50 "$cond" "${run#run}" ;;
	T4-R25) t4_fixed_run 25 "$cond" "${run#run}" ;;
	T4-R50) t4_fixed_run 50 "$cond" "${run#run}" ;;
	T4) echo "SKIP_T4_SAT $load $cond $run (buoc 4 m5e.sh)" ;;
	esac
	sleep 5
done < <(sort -t$'\t' -k1,1 -k3,3 "$LIST")

echo "=== noise rerun xong $(date -Iseconds) ==="
cat "$OUTROOT/noise-reruns.done" 2>/dev/null || true
grep -h '^RERUN_NOISE' "$LOG" | tail -50 >"$OUTROOT/noise-reruns.done"
