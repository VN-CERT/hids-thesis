#!/usr/bin/env bash
# Buoc 1 dong M5d: G7 + G3 + IRQ T3-C1 60s. Dung PASS/FAIL ro rang.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ $EUID -eq 0 ]] || { echo "can root" >&2; exit 1; }
export HOME="${HOME:-/root}"
export GOPATH="${GOPATH:-/root/go}"
export GOMODCACHE="${GOMODCACHE:-/root/go/pkg/mod}"
export PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

DATE=$(date +%Y%m%d)
OUT="${M5D_CLOSE_VERIFY_OUT:-validation/m5d-${DATE}/verify-close}"
mkdir -p "$OUT" out/jobs
LOG="$OUT/verify-step1.log"
RESULT="$OUT/step1-result.txt"
COLLECT=./bin/hids-collect

die() { echo "step1: $*" | tee -a "$RESULT"; exit 1; }
pass() { echo "PASS: $*" | tee -a "$RESULT"; }
fail() { echo "FAIL: $*" | tee -a "$RESULT"; exit 1; }

: >"$RESULT"
exec > >(tee -a "$LOG") 2>&1
echo "=== m5d step1 verify $(date -Iseconds) git=$(git rev-parse --short HEAD 2>/dev/null) ==="
make build

hids_require_disk_for_long_job

# --- G7 ---
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh a 1000000 | tee "$OUT/g7a.txt"
g7a_mat=$(grep -E 'tong bo dem mat:' "$OUT/g7a.txt" | tail -1 | awk '{print $NF}')
g7a_diff=$(grep -E 'tong \(perf - ban ghi\):' "$OUT/g7a.txt" | tail -1 | awk '{print $NF}')
[[ ${g7a_mat:-x} == 0 && ${g7a_diff:-x} == 0 ]] && pass "G7a mat=0 perf-diff=0" || fail "G7a mat=$g7a_mat perf-diff=$g7a_diff"

# G7b goc: 24 tien trinh x N=1_000_000 (khong dung 24M/tien trinh).
G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh b 1000000 | tee "$OUT/g7b.txt"
g7b_mat=$(grep -E 'tong bo dem mat:' "$OUT/g7b.txt" | tail -1 | awk '{print $NF}')
g7b_diff=$(grep -E 'tong \(perf - ban ghi\):' "$OUT/g7b.txt" | tail -1 | awk '{print $NF}')
[[ ${g7b_mat:-x} == 0 && ${g7b_diff:-x} == 0 ]] && pass "G7b mat=0 perf-diff=0" || fail "G7b mat=$g7b_mat perf-diff=$g7b_diff"

G7_SKIP_GIT_CHECK=1 bash scripts/g7.sh b-nho 1000000 | tee "$OUT/g7b-nho.txt"
g7n_diff=$(grep -E 'tong \(perf - ban ghi\):' "$OUT/g7b-nho.txt" | tail -1 | awk '{print $NF}')
g7n_mat=$(grep -E 'tong bo dem mat:' "$OUT/g7b-nho.txt" | tail -1 | awk '{print $NF}')
g7n_seq=$(grep -E 'tong so seq bi thieu' "$OUT/g7b-nho.txt" | tail -1 | awk '{print $NF}')
[[ -n ${g7n_diff:-} && $g7n_diff == "$g7n_mat" && $g7n_diff == "$g7n_seq" && ${g7n_diff:-0} -gt 0 ]] \
	&& pass "G7b-nho perf-diff=$g7n_diff = mat = seq_thieu" \
	|| fail "G7b-nho perf-diff=$g7n_diff mat=$g7n_mat seq=$g7n_seq"

# --- G3 S1-S5 ---
docker start qdrant >/dev/null 2>&1 || true
G3_SKIP_GIT_CHECK=1 G3_OUTROOT="$OUT/g3" bash scripts/g3.sh m5d | tee "$OUT/g3-run.txt"
g3_fail=0
for s in S1 S2 S3 S4 S5; do
	kf="$OUT/g3/${s}-ketqua.txt"
	[[ -f $kf ]] || { fail "G3 thieu $kf"; }
	p99=$(awk '/G5 phan du \|tat ca \(tru FIRST\)/{f=1;next} f&&/^p99 /{print $2; exit}' "$kf")
	max=$(awk '/G5 phan du \|tat ca \(tru FIRST\)/{f=1;next} f&&/^max /{print $2; exit}' "$kf")
	# 0.5 us = 500 ns
	if [[ -z ${p99:-} ]] || [[ ${p99:-999999} -gt 500 ]]; then
		echo "FAIL: G3 $s p99_phan_du_ns=$p99 (can <= 500)"
		g3_fail=1
	else
		echo "PASS: G3 $s p99_phan_du_ns=$p99 max=$max"
	fi
done
[[ $g3_fail -eq 0 ]] && pass "G3 S1-S5 p99 phan du <= 500 ns" || fail "G3 co scenario vuot 0.5 us"

# --- T3-C1 60s + IRQ (doi chieu R018 ~6M IWI, ~17.4M CAL) ---
IRQ_TSV="$OUT/irq-t3c1-60s.tsv"
: >"$IRQ_TSV"
docker rm -f pgtest 2>/dev/null || true
docker run -d --name pgtest --cpuset-cpus 12-15 -e POSTGRES_PASSWORD=m5test postgres:16-alpine >/dev/null
for i in $(seq 1 90); do docker exec pgtest pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done
docker exec -u postgres pgtest pgbench -i -s 50 -U postgres -d postgres >/dev/null 2>&1 || true
pid=$(docker inspect -f '{{.State.Pid}}' pgtest)
cg=$(awk -F: '$1=="0"{print $3}' "/proc/$pid/cgroup")
cg="/sys/fs/cgroup${cg}"
unit="hids-m5d-verify-t3c1-$$"
systemd-run --scope --unit="$unit" --slice=system.slice -- \
	"$COLLECT" -cgroup "$cg" -duration 120s -out "$OUT/t3c1-collect.bin" \
	>"$OUT/t3c1-collect-scope.log" 2>"$OUT/t3c1-collect.log" &
sleep 1
for ((i = 0; i < 3000; i++)); do grep -qx READY "$OUT/t3c1-collect.log" 2>/dev/null && break; sleep 0.01; done
grep -qx READY "$OUT/t3c1-collect.log" || fail "T3-C1 collector khong READY"
bash scripts/m5d_irq_sample.sh 60 "$IRQ_TSV" &
irq_pid=$!
taskset -c 16-19 docker exec -u postgres pgtest pgbench -c 16 -j 4 -T 60 -U postgres -d postgres \
	>"$OUT/t3c1-pgbench.log" 2>&1 || true
wait "$irq_pid"
systemctl stop "${unit}.scope" 2>/dev/null || true
docker rm -f pgtest 2>/dev/null || true
tail -1 "$IRQ_TSV" | tee -a "$RESULT"
hids_drop_collect_bin "$OUT/t3c1-collect.bin"

echo "=== G7-cap (cong suat, khong thay G7b) ===" | tee -a "$RESULT"
G7_CAP_OUT="$(dirname "$OUT")/g7-cap" bash scripts/g7_cap.sh | tee "$OUT/g7-cap-run.txt"
max_zstd=$(awk -F'\t' '$1=="zstd-default" && $5==0 {print $6}' "$(dirname "$OUT")/g7-cap/summary.tsv" | sort -nr | head -1)
echo "G7-cap zstd-default max_rate_mat0=${max_zstd:-0}/s" | tee -a "$RESULT"

echo "STEP1_ALL_PASS $(date -Iseconds)" | tee -a "$RESULT"
hids_print_df_at_job_end
