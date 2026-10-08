#!/usr/bin/env bash
# M5e: zstd G7, tải cố định, T4 kịch trần, summary, R020.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}" GOPATH="${GOPATH:-/root/go}" GOMODCACHE="${GOMODCACHE:-/root/go/pkg/mod}"
export PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

DATE=$(date +%Y%m%d)
OUTROOT="${M5E_OUT:-validation/m5e-${DATE}}"
M5D="${M5D_BASE:-validation/m5d-20261008}"
LOG="out/jobs/m5e.log"
CONTAINERS="${M5_CONTAINERS_RESTORE:-/root/containers-da-dung.txt}"
mkdir -p out/jobs "$OUTROOT"

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

exec > >(tee -a "$LOG") 2>&1
echo "=== m5e $(date -Iseconds) out=$OUTROOT ==="
hids_require_disk_for_long_job
make build
stop_containers

cp -f "$M5D/diag-summary.tsv" "$OUTROOT/diag-summary.tsv" 2>/dev/null || true

echo "=== buoc 1: G7 zstd mac dinh ==="
M5E_ZSTD_OUT="$OUTROOT/step1-zstd" bash scripts/m5e_step1_zstd.sh

echo "=== buoc 3: T3-R / T4-R xen ke ==="
rm -rf "$OUTROOT"/T3-R25 "$OUTROOT"/T3-R50 "$OUTROOT"/T4-R25 "$OUTROOT"/T4-R50
M5_SKIP_GIT_CHECK=1 M5C_FIXED_FORCE=1 M5E_INTERLEAVE=1 M5E_ONLY_FIXED=1 M5C_FIXED_RUNS=3 \
	M5C_DIAG_SUMMARY="$OUTROOT/diag-summary.tsv" M5C_FIXED_OUT="$OUTROOT" \
	bash scripts/m5c_fixed.sh
cp -f "$M5D/observer_cost.txt" "$OUTROOT/observer_cost.txt" 2>/dev/null || true

echo "=== buoc 4: T4 kich tran 7 luot xen ke ==="
rm -rf "$OUTROOT/T4"
M5_SKIP_GIT_CHECK=1 M5E_FORCE=1 M5E_INTERLEAVE=1 M5D_MODE=1 M5_RUNS=7 \
	M5_OUTROOT="$OUTROOT" M5_RERUN=T4 bash scripts/m5.sh

echo "=== summary ==="
python3 analysis/m5e_summary.py "$OUTROOT" "$M5D" >"$OUTROOT/summary.csv"
python3 analysis/m5e_report_tables.py "$OUTROOT" >"$OUTROOT/m5e-tables.txt"

echo "=== m5e xong $OUTROOT ==="
