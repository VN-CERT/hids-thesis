#!/usr/bin/env bash
# m6b1_pre24h.sh — muc 1-3 bat buoc truoc thu 24h (khong SKIP).
# That bai: exit != 0, in nguyen van.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
# shellcheck source=scripts/hids_data_policy.sh
source scripts/hids_data_policy.sh

OUTROOT="${M6B1_PRE24H_OUT:-validation/m6b1-pre24h-$(date +%Y%m%d)}"
mkdir -p "$OUTROOT" out/jobs
LOG="$OUTROOT/pre24h.log"
exec > >(tee -a "$LOG") 2>&1

die() { echo "m6b1_pre24h: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

wait_ready() {
	local log=$1 i
	for ((i = 0; i < 600; i++)); do
		grep -qx READY "$log" 2>/dev/null && return 0
		sleep 0.1
	done
	return 1
}

[[ $EUID -eq 0 ]] || die "can root"
hids_require_clean_git || die "cay git khong sach"
[[ -x ./bin/hids-collect && -x ./bin/rec-chain && -x ./bin/sysinj ]] || die "chay make build truoc"

echo "=== sha256 file kien truc su ==="
sha256sum bpf/sys_enter.bpf.c bpf/proc_events.bpf.c analysis/m5f_parse.py | tee "$OUTROOT/architect-sha256.txt"
echo "=== git_commit binary ==="
./bin/hids-collect -h 2>&1 | head -1 || true
strings ./bin/hids-collect | grep -E '^[0-9a-f]{7,}' | head -3 || true
# In commit tu buildinfo bang cach chay -duration 0 se can root+filter; ghi HEAD
git rev-parse --short HEAD | tee "$OUTROOT/git-head.txt"
git status --porcelain | tee "$OUTROOT/git-status.txt" || true

field_after() {
	# Lay so sau nhan co dinh, vi du "tong bo dem mat:"
	local file=$1 label=$2
	awk -v lab="$label" 'index($0, lab)==1 { print $NF; exit }' "$file"
}

echo "=== Muc 1: G7a -zstd-level 0 ==="
HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh a 1000000 2>&1 | tee "$OUTROOT/g7a-z0.txt"
g7a_rec=$(field_after "$OUTROOT/g7a-z0.txt" "tong ban ghi doc duoc:")
g7a_mat=$(field_after "$OUTROOT/g7a-z0.txt" "tong bo dem mat:")
g7a_diff=$(field_after "$OUTROOT/g7a-z0.txt" "tong (perf - ban ghi):")
g7a_rec=${g7a_rec:-}
g7a_mat=${g7a_mat:-999}
g7a_diff=${g7a_diff:-999}
{
	echo "G7a ban_ghi=$g7a_rec mat=$g7a_mat (perf-ban_ghi)=$g7a_diff"
} | tee "$OUTROOT/g7a-summary.txt"
[[ "$g7a_mat" == "0" && "$g7a_diff" == "0" && -n "$g7a_rec" ]] \
	&& pass "G7a perf=ban_ghi=$g7a_rec mat=0" \
	|| fail "G7a ban_ghi=$g7a_rec mat=$g7a_mat (perf-ban_ghi)=$g7a_diff"

echo "=== Muc 1: G7b-nho -zstd-level 0 ==="
HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh b-nho 1000000 2>&1 | tee "$OUTROOT/g7b-nho-z0.txt"
g7b_rec=$(field_after "$OUTROOT/g7b-nho-z0.txt" "tong ban ghi doc duoc:")
g7b_mat=$(field_after "$OUTROOT/g7b-nho-z0.txt" "tong bo dem mat:")
g7b_seq=$(field_after "$OUTROOT/g7b-nho-z0.txt" "tong so seq bi thieu theo CPU:")
g7b_diff=$(field_after "$OUTROOT/g7b-nho-z0.txt" "tong (perf - ban ghi):")
g7b_rec=${g7b_rec:-}
g7b_mat=${g7b_mat:-}
g7b_seq=${g7b_seq:-}
g7b_diff=${g7b_diff:-}
{
	echo "G7b-nho ban_ghi=$g7b_rec mat=$g7b_mat seq_thieu=$g7b_seq (perf-ban_ghi)=$g7b_diff"
} | tee "$OUTROOT/g7b-nho-summary.txt"
[[ -n "$g7b_mat" && "$g7b_diff" == "$g7b_mat" && "$g7b_mat" == "$g7b_seq" ]] \
	&& pass "G7b-nho (perf-ban_ghi)=mat=seq_thieu=$g7b_mat" \
	|| fail "G7b-nho ban_ghi=$g7b_rec mat=$g7b_mat seq_thieu=$g7b_seq (perf-ban_ghi)=$g7b_diff"

echo "=== Muc 1: G3 S1-S5 ==="
G3_OUTROOT="$OUTROOT/g3" bash scripts/g3.sh m5d 2>&1 | tee "$OUTROOT/g3.log" || fail "g3.sh m5d loi"
# Kiem recursion_misses va G5 max phan du
miss_bad=0
while IFS= read -r f; do
	if grep -A100 'recursion_misses' "$f" | grep -E 'hids_' | awk '{print $NF}' | grep -vqE '^0$'; then
		echo "FAIL recursion_misses khac 0 trong $f"
		miss_bad=1
	fi
done < <(find "$OUTROOT/g3" -name '*-ketqua.txt' | sort)
[[ $miss_bad -eq 0 ]] && pass "G3 recursion_misses=0" || fail "G3 recursion_misses != 0"

python3 - <<'PY' "$OUTROOT/g3" | tee "$OUTROOT/g3-g5-max.txt"
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
bad = False
for p in sorted(root.glob("S*-ketqua.txt")):
    text = p.read_text(errors="replace")
    m = None
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "G5 phan du |tat ca (tru FIRST)|" in line or "G5 phần dư |tất cả (trừ FIRST)|" in line:
            for j in range(i + 1, min(i + 8, len(lines))):
                mm = re.match(r"max\s+(\d+)", lines[j].strip())
                if mm:
                    m = int(mm.group(1))
                    break
            break
    print(f"{p.name}: g5_max_ns={m}")
    if m is None or m > 500:
        bad = True
        print(f"FAIL {p.name} max={m} (can <=500)")
    # recursion_misses tong
    for line in lines:
        if line.startswith("recursion_misses"):
            print(f"{p.name}: {line.strip()}")
sys.exit(1 if bad else 0)
PY
pass "G3 S1-S5 phan du max <= 500 ns"

echo "=== Muc 2: G9b rotate 2m zstd mac dinh, 2 container ==="
mapfile -t TOP2 < <(docker stats --no-stream --format '{{.CPUPerc}}\t{{.Name}}' 2>/dev/null \
	| sed 's/%//' | sort -nr | awk 'NF>=2{print $2}' | head -2)
[[ ${#TOP2[@]} -ge 2 ]] || die "can >= 2 container dang chay"
C1="${TOP2[0]}"
C2="${TOP2[1]}"
cg_of() {
	local name=$1 pid rel
	pid=$(docker inspect -f '{{.State.Pid}}' "$name")
	rel=$(awk -F: '$1=="0"{print $3; exit}' "/proc/$pid/cgroup")
	echo "/sys/fs/cgroup${rel}"
}
CG1=$(cg_of "$C1")
CG2=$(cg_of "$C2")
{
	echo "G9b containers: $C1 | $C2"
	echo "cgroup: $CG1"
	echo "cgroup: $CG2"
	docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' | grep -E "^($C1|$C2)\t" || true
} | tee "$OUTROOT/g9b-targets.txt"
G9B="$OUTROOT/g9b"
rm -rf "$G9B"
mkdir -p "$G9B"
./bin/hids-collect -datadir "$G9B" -cgroup "$CG1" -cgroup "$CG2" \
	-duration 7m -rotate 2m >"$G9B/run.log" 2>&1 &
G9PID=$!
wait_ready "$G9B/run.log" || { cat "$G9B/run.log"; fail "G9b khong READY"; }
wait "$G9PID" || true

echo "=== G9b: giai nen TOAN BO moi file ba luong ==="
{
	echo "so file .bin: $(find "$G9B" -name '*.bin' | wc -l)"
	echo "so file proc: $(find "$G9B" -name 'proc-*.tsv.zst' | wc -l)"
	echo "so file host: $(find "$G9B" -name 'host-*.tsv.zst' | wc -l)"
	echo "--- .bin (doc het qua rec-stat, in tong ban ghi) ---"
	find "$G9B" -name '*.bin' | sort | while read -r f; do
		sz=$(stat -c%s "$f")
		# Doc toan bo payload (giai nen zstd neu co) bang rec-stat
		out=$(./bin/rec-stat "$f" 2>&1 | tee "$f.rec-stat.txt" | awk -F: '/^tong so ban ghi trong file/{gsub(/[ \t]/,"",$2); print $2; exit}')
		echo "FILE bin $f bytes=$sz tong_ban_ghi=${out:-?} decompress_read_ok=1"
	done
	echo "--- proc (zstdcat toan bo) ---"
	find "$G9B" -name 'proc-*.tsv.zst' | sort | while read -r f; do
		sz=$(stat -c%s "$f")
		lines=$(zstdcat "$f" | wc -l)
		echo "FILE proc $f bytes=$sz lines=$lines zstdcat_ok=1"
	done
	echo "--- host (zstdcat toan bo) ---"
	find "$G9B" -name 'host-*.tsv.zst' | sort | while read -r f; do
		sz=$(stat -c%s "$f")
		lines=$(zstdcat "$f" | wc -l)
		echo "FILE host $f bytes=$sz lines=$lines zstdcat_ok=1"
	done
} | tee "$G9B/files-inventory.txt"

mapfile -t BINS < <(find "$G9B" -name '*.bin' | sort)
[[ ${#BINS[@]} -ge 2 ]] || fail "G9b can >= 2 file .bin, co ${#BINS[@]}"
./bin/rec-chain "${BINS[@]}" | tee "$G9B/rec-chain.txt"
bmiss=$(sed -n 's/.*tong seq thieu ranh gioi: \([0-9]*\).*/\1/p' "$G9B/rec-chain.txt" | tail -1)
bmiss=${bmiss:-999}
bholes=$(sed -n 's/.*tong lo hong ranh gioi: \([0-9]*\).*/\1/p' "$G9B/rec-chain.txt" | tail -1)
bholes=${bholes:-999}
last_stats=$(ls -1 "$G9B"/*.stats 2>/dev/null | sort | tail -1 || true)
tot_mat=0
[[ -n ${last_stats:-} ]] && tot_mat=$(awk -F, 'NR>1{d+=$3} END{print d+0}' "$last_stats")
echo "G9b ranh_gioi lo_hong=$bholes seq_thieu=$bmiss kernel_mat_file_cuoi=$tot_mat" | tee "$G9B/g9b-summary.txt"
# Tieu chi: khong lo hong ngoai phan da dem mat (ranh gioi)
if [[ "$bmiss" -le "$tot_mat" && "$bholes" -le "$tot_mat" ]]; then
	pass "G9b rec-chain ranh_gioi seq_thieu=$bmiss lo_hong=$bholes mat=$tot_mat"
else
	fail "G9b rec-chain seq_thieu=$bmiss lo_hong=$bholes > mat=$tot_mat"
fi

echo "=== Muc 3: host-stats 10 phut ==="
HDIR="$OUTROOT/host10m"
rm -rf "$HDIR"
mkdir -p "$HDIR"
./bin/hids-collect -datadir "$HDIR" -pid "$$" -duration 10m >"$HDIR/run.log" 2>&1 &
HPID=$!
wait_ready "$HDIR/run.log" || fail "host10m khong READY"
wait "$HPID" || true
HOST=$(find "$HDIR" -name 'host-*.tsv.zst' | head -1)
[[ -n ${HOST:-} ]] || fail "khong co host TSV"
# M6c-1 1c: dem TONG moi doan host-*.tsv.zst (lan chay 10 phut co the vat qua
# moc xoay file theo gio), tru dong tieu de cua tung doan.
lines=0
while IFS= read -r hf; do
	n=$(zstdcat "$hf" | tail -n +2 | wc -l)
	lines=$((lines + n))
done < <(find "$HDIR" -name 'host-*.tsv.zst' | sort)
echo "host lines: $lines" | tee "$HDIR/lines.txt"
[[ "$lines" -ge 580 && "$lines" -le 620 ]] && pass "host ~600 dong ($lines)" || fail "host lines=$lines"
zstdcat "$HOST" | tail -n +2 | awk -F'\t' '
  NR==1 { u=$3; n=$4; s=$5; next }
  {
    if ($3+0 < u+0 || $4+0 < n+0 || $5+0 < s+0) { bad=1 }
    u=$3; n=$4; s=$5
  }
  END { exit bad+0 }
' && pass "host bo dem tich luy khong giam" || fail "host bo dem tich luy giam"

echo "=== m6b1_pre24h xong ==="
echo "exit=0" > out/jobs/m6b1-pre24h.status
