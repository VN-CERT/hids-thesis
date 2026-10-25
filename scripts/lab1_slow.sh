#!/usr/bin/env bash
# lab1_slow.sh — phu luc 1.7: chu ky cham tren nen 7 ngay (khong lieu).
# Thu tu: B1-60s 30p, N1-60s 30p, B1-300s 120p, N1-300s 120p. Nhãn lab/nhan-tan-cong.tsv.
# Chay trong unit hids-lab1-slow. Tieu chi ≥ 20 chu ky.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }

DAY="${LAB1_DAY:-$(date +%Y%m%d)}"
VAL="validation/lab1-${DAY}"
SLOW_DIR="$VAL/slow"
NHAN_TC="lab/nhan-tan-cong.tsv"
LOG="$VAL/slow.log"
mkdir -p "$SLOW_DIR" lab
: >>"$LOG"

log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

mono_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }

ensure_nhan_tc() {
	if [[ ! -f $NHAN_TC ]]; then
		printf 'run_id\tlop\tid\tatt_ck\tcong_cu\tnhip_tham_so\tmuc_tranh_chap\tsong_sinh_cua\tt_bat_dau_mono_ns\tt_ket_thuc_mono_ns\tt_bat_dau_wall\tt_ket_thuc_wall\toracle_ket_qua\tghi_chu\n' \
			>"$NHAN_TC"
	fi
}

append_nhan_tc() {
	ensure_nhan_tc
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$NHAN_TC"
}

# Dam bao ≥20 chu ky: chay duration; neu thieu (jitter max) thi keo them.
run_slow_one() {
	local kind=$1      # B1|N1
	local period=$2    # 60|300
	local dur_s=$3     # 1800|7200
	local tag="${kind}-${period}s"
	local sess="$SLOW_DIR/$tag"
	if [[ -f $sess/xac-nhan.txt ]] && grep -q 'ok_cycles_ge20=1' "$sess/xac-nhan.txt"; then
		log "TAI DUNG $tag"
		return 0
	fi
	rm -rf "$sess"
	mkdir -p "$sess"
	log "bat dau $tag period=${period}s duration=${dur_s}s (nen 7 ngay, khong lieu)"

	local name song lop id
	case $kind in
	B1)
		name=xcfgd-beacon
		song=
		lop=B
		id=B1
		;;
	N1)
		name=nginx-healthcheck
		song=B1
		lop=N
		id=N1
		;;
	*)
		log "kind sai: $kind"
		exit 1
		;;
	esac

	local t0 tw0 t1 tw1 cycles=0
	t0=$(mono_ns)
	tw0=$(date -Is)

	python3 scripts/lab1_http_client.py \
		--name "$name" --period-s "$period" --duration-s "$dur_s" \
		--log "$sess/client.log" >>"$sess/client.stderr" 2>&1 || true

	cycles=$(awk 'NR>1{c++} END{print c+0}' "$sess/client.log" 2>/dev/null || echo 0)

	# Neu jitter max → <20: keo them den du 20 (cap 2× duration)
	local extra=0
	while ((cycles < 20 && extra < dur_s)); do
		log "$tag cycles=$cycles < 20 — keo them 1 chu ky"
		python3 scripts/lab1_http_client.py \
			--name "$name" --period-s "$period" --duration-s "$((period * 2))" \
			--log "$sess/client-extra.log" >>"$sess/client.stderr" 2>&1 || true
		if [[ -f $sess/client-extra.log ]]; then
			tail -n +2 "$sess/client-extra.log" >>"$sess/client.log"
		fi
		cycles=$(awk 'NR>1{c++} END{print c+0}' "$sess/client.log" 2>/dev/null || echo 0)
		extra=$((extra + period * 2))
	done

	t1=$(mono_ns)
	tw1=$(date -Is)
	local ok=0
	((cycles >= 20)) && ok=1
	{
		echo "kind=$kind period=$period dur_s=$dur_s tag=$tag"
		echo "t0_mono=$t0 t1_mono=$t1"
		echo "wall $tw0 -> $tw1"
		echo "cycles=$cycles ok_cycles_ge20=$ok"
		echo "phuluc=1.7 nen=7ngay khong_lieu"
	} | tee "$sess/xac-nhan.txt" | tee -a "$LOG"

	append_nhan_tc \
		"${tag}-${DAY}" "$lop" "$id" "LAB1" "local" \
		"period=${period}" "nen0" "$song" \
		"$t0" "$t1" "$tw0" "$tw1" \
		"client_cycles=${cycles};log=${sess}/client.log" \
		"phuluc1.7;slow;sess=$sess"

	if ((ok != 1)); then
		echo "$tag cycles=$cycles < 20" >"$VAL/slow-loi.txt"
		log "LOI $tag cycles=$cycles < 20"
		exit 1
	fi
	log "$tag DAT cycles=$cycles"
}

log "LAB-1 slow bat dau $(date -Is) DAY=$DAY"
# Cho collector nen on dinh vai giay
sleep 10
# Dam bao container Up
docker start lab0-postgres lab0-nginx >/dev/null 2>&1 || true

run_slow_one B1 60 1800
run_slow_one N1 60 1800
run_slow_one B1 300 7200
run_slow_one N1 300 7200

echo "slow xong $(date -Is)" | tee "$VAL/slow-xong.txt"
log "LAB-1 slow XONG"
exit 0
