#!/usr/bin/env bash
# M6c-1 phan 2: G7a x4 (host/on/off/mac dinh), G3 mot lan mac dinh host,
# hostcheck datadir 70s (host va off). Container dung (m6b12_g3.sh tu lo cho G3;
# phan G7a/hostcheck do script nay dung/khoi dong).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
OUTROOT="${1:?can thu muc output}"
mkdir -p "$OUTROOT"

pmu_line() { grep -a "^# pmu" "$1" | head -2; }

echo "=== G7a -pmu host ===" | tee "$OUTROOT/g7a-host.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu host" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-host.txt" 2>&1
echo "=== G7a -pmu on ===" | tee "$OUTROOT/g7a-on.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu on" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-on.txt" 2>&1
echo "=== G7a -pmu off ===" | tee "$OUTROOT/g7a-off.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0 -pmu off" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-off.txt" 2>&1
echo "=== G7a mac dinh (khong truyen -pmu) ===" | tee "$OUTROOT/g7a-default.txt"
HIDS_COLLECT_EXTRA="-zstd-level 0" bash scripts/g7.sh a 1000000 >>"$OUTROOT/g7a-default.txt" 2>&1

# In dong pmu cua header 4 file .bin vua tao (g7.sh ghi out/g7a-*.bin).
python3 - <<'PY' | tee "$OUTROOT/g7a-pmu-headers.txt"
import glob, subprocess
for p in sorted(glob.glob("out/g7a-*.bin"), key=lambda x: __import__("os").path.getmtime(x))[-4:]:
    hdr = subprocess.run(["python3", "-c", """
import sys
with open(sys.argv[1],'rb') as f:
    for line in f:
        s=line.decode('utf8','replace').rstrip()
        if 'pmu' in s: print(s)
        if s.strip()=='#END': break
""", p], capture_output=True, text=True).stdout
    print(p)
    print(hdr)
PY

echo "=== G3 mac dinh (host), dung container ==="
bash scripts/m6b12_g3.sh stop "$OUTROOT/g3-default" || echo "g3 exit=$?"

echo "=== hostcheck datadir 70s (container thu tam) ==="
mapfile -t RUNNING < <(docker ps --format '{{.Names}}')
docker stop "${RUNNING[@]}" >/dev/null 2>&1 || true
docker rm -f hids-hostcheck >/dev/null 2>&1 || true
docker run -d --name hids-hostcheck alpine:3.20 sleep 300 >/dev/null 2>&1 || docker run -d --name hids-hostcheck postgres:16-alpine sleep 300 >/dev/null
HC_PID=$(docker inspect -f '{{.State.Pid}}' hids-hostcheck)
HC_REL=$(awk -F: '$1=="0"{print $3; exit}' "/proc/$HC_PID/cgroup")
HC_CG="/sys/fs/cgroup${HC_REL}"
echo "container thu hids-hostcheck cgroup=$HC_CG" | tee "$OUTROOT/hostcheck-cg.txt"
./bin/hids-collect -datadir "$OUTROOT/hostcheck/host" -duration 70s -cgroup "$HC_CG" >"$OUTROOT/hostcheck-host.log" 2>&1
./bin/hids-collect -datadir "$OUTROOT/hostcheck/off" -duration 70s -pmu off -cgroup "$HC_CG" >"$OUTROOT/hostcheck-off.log" 2>&1
docker rm -f hids-hostcheck >/dev/null 2>&1 || true
docker start "${RUNNING[@]}" >/dev/null 2>&1 || true

echo "--- hostcheck host: 3 dong cuoi ---" | tee "$OUTROOT/hostcheck.txt"
zstdcat "$OUTROOT"/hostcheck/host/host-*.tsv.zst 2>/dev/null | tail -3 | tee -a "$OUTROOT/hostcheck.txt"
echo "--- hostcheck off: 3 dong cuoi ---" | tee -a "$OUTROOT/hostcheck.txt"
zstdcat "$OUTROOT"/hostcheck/off/host-*.tsv.zst 2>/dev/null | tail -3 | tee -a "$OUTROOT/hostcheck.txt"

echo "part2 xong"
