#!/usr/bin/env bash
# Trich features_all_v2.tsv bang c5_extract_v2 (M6i-c1). Khong cham diem.
# Dung: c5_pipeline_v2_extract.sh <DATA> <OUT> <ten_job>
# OUT se co features_v2/ va features_all_v2.tsv. Khong dung features/ cua v1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

if [[ $# -ne 3 ]]; then
  echo "cach dung: $0 <thu_muc_du_lieu> <thu_muc_ra> <ten_job>" >&2
  exit 2
fi

DATA="$(cd "$1" && pwd)"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
JOB="$3"
STATUS="$ROOT/out/jobs/${JOB}.status"
LOG="$ROOT/out/jobs/${JOB}.log"
FEAT_DIR="$OUT/features_v2"
mkdir -p "$FEAT_DIR" "$ROOT/out/jobs"

{
  echo "start=$(date -Iseconds)"
  echo "status=running"
  echo "progress=0/?"
  echo "data=$DATA"
  echo "out=$OUT"
} > "$STATUS"

exec > >(tee -a "$LOG") 2>&1
echo "=== c5_pipeline_v2_extract job=$JOB ==="
echo "ROOT=$ROOT DATA=$DATA OUT=$OUT bat_dau=$(date -Iseconds)"

need() { [[ -e "$1" ]] || { echo "THIEU: $1" >&2; exit 1; }; }
need "$ROOT/bin/rec-export"
need "$ROOT/scripts/c5_extract_v2.py"

nguon_of() {
  local f="$1"
  case "$f" in
    */nen/*|*/lab1-benign/*) echo nen ;;
    */bn/*) echo bn ;;
    */benign-lieu/*) echo benign-lieu ;;
    */slow/*) echo slow ;;
    */d2/*) echo d2 ;;
    *)
      local rel="${f#"$DATA"/}"
      case "$rel" in
        nen/*|nen) echo nen ;;
        bn/*|bn) echo bn ;;
        benign-lieu/*|benign-lieu) echo benign-lieu ;;
        slow/*|slow) echo slow ;;
        d2/*|d2) echo d2 ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

mapfile -t INPUTS < <(
  {
    for d in nen bn benign-lieu slow d2 lab1-benign; do
      if [[ -d "$DATA/$d" ]]; then
        find -L "$DATA/$d" -type f \
          \( -name '*.bin' -o -name '*.bin.zst' \) \
          ! -name '*.bin.periodic' ! -name '*.bin.stats' \
          ! -name 'payload.bin' \
          ! -name 'status.tsv' ! -name 'suc-khoe.tsv' \
          ! -path '*/gen-logs/*'
      fi
    done
  } 2>/dev/null | sort -u
)
echo "so_file_vao=${#INPUTS[@]}"
if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "khong tim thay *.bin" >&2
  echo "status=failed" >> "$STATUS"
  exit 1
fi

BK="$DATA/benign-khoi-dong.txt"
need "$BK"
read -r T_MIN T_MAX TRAIN_UNTIL < <(python3 - "$BK" <<'PY'
import sys, re
text = open(sys.argv[1], encoding="utf-8").read()

def start_mono_ns(text):
    m = re.search(r"start_mono_ns\s*=\s*(\d+)", text)
    if m:
        print("nguon_moc=start_mono_ns", file=sys.stderr)
        return int(m.group(1))
    m = re.search(r"khoi_dong_monotonic_s\s*=\s*([0-9]+(?:\.[0-9]+)?)", text)
    if not m:
        raise SystemExit("benign-khoi-dong.txt thieu start_mono_ns va khoi_dong_monotonic_s")
    s = m.group(1)
    print("nguon_moc=khoi_dong_monotonic_s", file=sys.stderr)
    if "." in s:
        whole, frac = s.split(".", 1)
        frac = (frac + "000000000")[:9]
        return int(whole) * 1_000_000_000 + int(frac)
    return int(s) * 1_000_000_000

t0 = start_mono_ns(text)
day = 86400 * 1_000_000_000
print(t0, t0 + 7 * day, t0 + 5 * day)
PY
)
echo "cua_so_7ngay t_min=$T_MIN t_max=$T_MAX train_until=$TRAIN_UNTIL"

GIU_BO="$OUT/giu_bo_v2.tsv"
echo -e "nguon\tgiu\tbo\tfile" > "$GIU_BO"
declare -a FEAT_PARTS=()
total=${#INPUTS[@]}
done_n=0

for f in "${INPUTS[@]}"; do
  nguon="$(nguon_of "$f")"
  if [[ -z "$nguon" ]]; then
    echo "BO QUA (khong xac dinh nguon): $f" >&2
    continue
  fi
  rel="${f#"$DATA"/}"
  src_tag="$(echo "$rel" | tr '/' '_')"
  feat="$FEAT_DIR/${src_tag}.tsv"
  if [[ -s "$feat" ]]; then
    echo "[co-san] nguon=$nguon $feat"
    FEAT_PARTS+=("$feat")
    done_n=$((done_n + 1))
    echo "progress=${done_n}/${total}" > "$STATUS.tmp"
    echo "start=$(grep ^start= "$STATUS" | head -1 | cut -d= -f2-)" >> "$STATUS.tmp"
    echo "status=running" >> "$STATUS.tmp"
    echo "updated=$(date -Iseconds)" >> "$STATUS.tmp"
    mv "$STATUS.tmp" "$STATUS"
    continue
  fi
  echo "[extract_v2] nguon=$nguon $f $(date -Iseconds)"
  extra=()
  if [[ "$nguon" == "nen" ]]; then
    extra=(--t-min "$T_MIN" --t-max "$T_MAX")
  fi
  cap="$(mktemp)"
  set +e
  if [[ "$f" == *.bin.zst ]]; then
    /usr/bin/time -f "TIME_extract_v2 real=%e sec maxrss_kb=%M" \
      bash -c 'set -o pipefail; zstd -dc "$1" | "$0" /dev/stdin | python3 "$2" --tsv - --out "$3" --source "$4" "${@:5}"' \
      "$ROOT/bin/rec-export" "$f" "$ROOT/scripts/c5_extract_v2.py" "$feat" "$nguon" "${extra[@]}" \
      >"$cap" 2>&1
  else
    /usr/bin/time -f "TIME_extract_v2 real=%e sec maxrss_kb=%M" \
      bash -c 'set -o pipefail; "$0" "$1" | python3 "$2" --tsv - --out "$3" --source "$4" "${@:5}"' \
      "$ROOT/bin/rec-export" "$f" "$ROOT/scripts/c5_extract_v2.py" "$feat" "$nguon" "${extra[@]}" \
      >"$cap" 2>&1
  fi
  ec=$?
  set -e
  cat "$cap"
  giu="$(sed -n 's/.*giu=\([0-9]*\).*/\1/p' "$cap" | tail -1)"
  bo="$(sed -n 's/.*bo_qua_ngoai_7ngay=\([0-9]*\).*/\1/p' "$cap" | tail -1)"
  giu="${giu:-0}"
  bo="${bo:-0}"
  echo -e "${nguon}\t${giu}\t${bo}\t${f}" >> "$GIU_BO"
  rm -f "$cap"
  if [[ $ec -ne 0 ]]; then
    echo "LOI extract_v2 $f exit=$ec" >&2
    echo "status=failed" >> "$STATUS"
    exit "$ec"
  fi
  if [[ "$nguon" != "nen" && "$bo" != "0" ]]; then
    echo "LOI: phien $nguon bi bo $bo" >&2
    echo "status=failed" >> "$STATUS"
    exit 2
  fi
  FEAT_PARTS+=("$feat")
  done_n=$((done_n + 1))
  {
    echo "start=$(grep ^start= "$STATUS" | head -1 | cut -d= -f2-)"
    echo "status=running"
    echo "progress=${done_n}/${total}"
    echo "updated=$(date -Iseconds)"
  } > "$STATUS"
done

echo "=== GIU_BO_V2 THEO NGUON ==="
awk -F'\t' 'NR>1 {g[$1]+=$2; b[$1]+=$3; n[$1]++} END {for (k in g) printf "nguon=%s file=%d giu=%d bo=%d\n", k, n[k], g[k], b[k]}' "$GIU_BO"

FEAT_ALL="$OUT/features_all_v2.tsv"
echo "[merge] -> $FEAT_ALL"
python3 - "$FEAT_ALL" "${FEAT_PARTS[@]}" <<'PY'
import sys
out = sys.argv[1]
parts = sys.argv[2:]
headers = []
bodies = []
for p in parts:
    with open(p, encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        headers.append(h)
        bodies.append(fh.read())
union = []
seen = set()
for h in headers:
    for c in h:
        if c not in seen:
            union.append(c)
            seen.add(c)
if "nguon" in union:
    union = [c for c in union if c != "nguon"] + ["nguon"]
with open(out, "w", encoding="utf-8") as fo:
    fo.write("\t".join(union) + "\n")
    for h, body in zip(headers, bodies):
        idx = {c: i for i, c in enumerate(h)}
        for line in body.splitlines():
            if not line:
                continue
            p = line.split("\t")
            row = []
            for c in union:
                if c in idx and idx[c] < len(p):
                    row.append(p[idx[c]])
                else:
                    row.append("nan" if c != "nguon" else "")
            fo.write("\t".join(row) + "\n")
print("merged_files=%d header_cols=%d" % (len(parts), len(union)))
PY

echo "XONG_EXTRACT_V2 $(date -Iseconds) features_all_v2=$FEAT_ALL"
wc -l "$FEAT_ALL" | tee -a "$LOG"
{
  echo "start=$(grep ^start= "$STATUS" | head -1 | cut -d= -f2-)"
  echo "status=done"
  echo "progress=${done_n}/${total}"
  echo "end=$(date -Iseconds)"
  echo "feat_all=$FEAT_ALL"
} > "$STATUS"
