#!/usr/bin/env bash
# Goi tu systemd: doc /etc/hids/collect.env, lap -cgroup tu HIDS_CGROUPS (phay).
set -euo pipefail
: "${HIDS_DATADIR:?can HIDS_DATADIR trong collect.env}"
: "${HIDS_CGROUPS:?can HIDS_CGROUPS trong collect.env}"
BIN="${HIDS_COLLECT_BIN:-/usr/local/bin/hids-collect}"
args=(
  -datadir "$HIDS_DATADIR"
  -duration 0
  -rotate "${HIDS_ROTATE:-1h}"
  -min-free-gb "${HIDS_MIN_FREE_GB:-50}"
  -zstd-level "${HIDS_ZSTD_LEVEL:-2}"
)
IFS=',' read -r -a cgs <<<"$HIDS_CGROUPS"
for cg in "${cgs[@]}"; do
	cg="${cg#"${cg%%[![:space:]]*}"}"
	cg="${cg%"${cg##*[![:space:]]}"}"
	[[ -n $cg ]] && args+=(-cgroup "$cg")
done
if [[ -n ${HIDS_EXTRA:-} ]]; then
	# shellcheck disable=SC2206
	extra=( $HIDS_EXTRA )
	args+=("${extra[@]}")
fi
exec "$BIN" "${args[@]}"
