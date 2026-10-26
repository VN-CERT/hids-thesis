#!/usr/bin/env bash
# c5_pipeline.sh <thu_muc_du_lieu> <thu_muc_ra>
# M6g-b: nguon ∈ {nen,bn,benign-lieu,slow}; muc.tsv; bang kiem truoc khi cham.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$ROOT/bin:$PATH"

if [[ $# -ne 2 ]]; then
  echo "cach dung: $0 <thu_muc_du_lieu> <thu_muc_ra>" >&2
  exit 2
fi

DATA="$(cd "$1" && pwd)"
OUT="$(mkdir -p "$2" && cd "$2" && pwd)"
LOG="$OUT/pipeline.log"
CSV_DIR="$OUT/csv"
FEAT_DIR="$OUT/features"
mkdir -p "$CSV_DIR" "$FEAT_DIR"

exec > >(tee -a "$LOG") 2>&1

echo "=== c5_pipeline ==="
echo "ROOT=$ROOT"
echo "DATA=$DATA"
echo "OUT=$OUT"
echo "bat_dau=$(date -Iseconds)"
echo "host=$(hostname) kernel=$(uname -r)"

need() {
  local p="$1"
  if [[ ! -e "$p" ]]; then
    echo "THIEU: $p" >&2
    exit 1
  fi
}

need "$ROOT/bin/rec-export"
need "$ROOT/scripts/c5_extract.py"
need "$ROOT/analysis/c5_score.py"
need "$ROOT/scripts/c5_plot_svg.py"

# Map path -> nguon
nguon_of() {
  local f="$1"
  case "$f" in
    */nen/*|*/lab1-benign/*) echo nen ;;
    */bn/*) echo bn ;;
    */benign-lieu/*) echo benign-lieu ;;
    */slow/*) echo slow ;;
    *)
      # thu muc goc ten nen/bn/...
      local rel="${f#"$DATA"/}"
      case "$rel" in
        nen/*|nen) echo nen ;;
        bn/*|bn) echo bn ;;
        benign-lieu/*|benign-lieu) echo benign-lieu ;;
        slow/*|slow) echo slow ;;
        *) echo "" ;;
      esac
      ;;
  esac
}

# Tim file trong nen/bn/benign-lieu/slow (+ lab1-benign neu co duoi DATA)
mapfile -t INPUTS < <(
  {
    for d in nen bn benign-lieu slow lab1-benign; do
      if [[ -d "$DATA/$d" ]]; then
        find "$DATA/$d" \( -name '*.bin' -o -name '*.csv' -o -name '*.tsv' \)
      fi
    done
  } 2>/dev/null | sort -u
)
echo "so_file_vao=${#INPUTS[@]}"
if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "khong tim thay .bin/.csv/.tsv trong $DATA/{nen,bn,benign-lieu,slow}" >&2
  exit 1
fi

declare -a CSV_LIST=()
for f in "${INPUTS[@]}"; do
  nguon="$(nguon_of "$f")"
  if [[ -z "$nguon" ]]; then
    echo "BO QUA (khong xac dinh nguon): $f" >&2
    continue
  fi
  rel="${f#"$DATA"/}"
  src_tag="$(echo "$rel" | tr '/' '_')"
  case "$f" in
    *.bin)
      out_csv="$CSV_DIR/${src_tag}.csv"
      echo "[export] nguon=$nguon $f -> $out_csv"
      /usr/bin/time -f "TIME_export real=%e sec maxrss_kb=%M" \
        "$ROOT/bin/rec-export" "$f" > "$out_csv"
      ;;
    *.csv|*.tsv)
      out_csv="$CSV_DIR/${src_tag}"
      echo "[csv] nguon=$nguon $f -> $out_csv"
      ln -sfn "$f" "$out_csv"
      ;;
  esac
  CSV_LIST+=("$out_csv|$nguon|$src_tag")
done

declare -a FEAT_PARTS=()
for item in "${CSV_LIST[@]}"; do
  csv="${item%%|*}"
  rest="${item#*|}"
  nguon="${rest%%|*}"
  src="${rest##*|}"
  feat="$FEAT_DIR/${src}.tsv"
  echo "[extract] nguon=$nguon $csv"
  /usr/bin/time -f "TIME_extract real=%e sec maxrss_kb=%M" \
    python3 "$ROOT/scripts/c5_extract.py" --tsv "$csv" --out "$feat" --source "$nguon"
  FEAT_PARTS+=("$feat")
done

FEAT_ALL="$OUT/features_all.tsv"
echo "[merge] -> $FEAT_ALL"
python3 - "$FEAT_ALL" "${FEAT_PARTS[@]}" <<'PY'
import sys
out = sys.argv[1]
parts = sys.argv[2:]
headers = []
rows_by_file = []
for p in parts:
    with open(p, encoding="utf-8") as fh:
        h = fh.readline().rstrip("\n").split("\t")
        headers.append(h)
        rows_by_file.append([line.rstrip("\n").split("\t") for line in fh if line.strip()])
union = list(headers[0])
seen = set(union)
for h in headers[1:]:
    for c in h:
        if c not in seen:
            union.append(c)
            seen.add(c)
# dam bao cot nguon o cuoi
if "nguon" in union:
    union = [c for c in union if c != "nguon"] + ["nguon"]
with open(out, "w", encoding="utf-8") as fh:
    fh.write("\t".join(union) + "\n")
    for h, rows in zip(headers, rows_by_file):
        idx = {c: i for i, c in enumerate(h)}
        for r in rows:
            out_r = []
            for c in union:
                if c in idx and idx[c] < len(r):
                    out_r.append(r[idx[c]])
                else:
                    out_r.append("nan")
            fh.write("\t".join(out_r) + "\n")
print("merged_rows", sum(len(r) for r in rows_by_file), "cols", len(union))
PY

# muc.tsv: bn -> D1 0/2/4; benign-lieu -> D1-8/D1-16/D3-4/D3-7; slow+nen -> 0
MUC="$OUT/muc.tsv"
echo "[muc] -> $MUC"
python3 - "$DATA" "$MUC" <<'PY'
import os, re, sys
data, out = sys.argv[1], sys.argv[2]
rows = []  # start, stop, muc, id

def add(lo, hi, muc, rid):
    rows.append((int(lo), int(hi), str(muc), str(rid)))

# 1) nhan-lieu: BEN-*
lieu = os.path.join(data, "lab", "nhan-lieu.tsv")
if os.path.isfile(lieu):
    with open(lieu, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        lo_k = next((k for k in ("t_bat_dau_mono_ns", "start_ns") if k in idx), None)
        hi_k = next((k for k in ("t_ket_thuc_mono_ns", "stop_ns") if k in idx), None)
        muc_k = next((k for k in ("muc", "muc_tranh_chap") if k in idx), None)
        id_k = "id" if "id" in idx else None
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if not lo_k or not hi_k:
                break
            try:
                lo, hi = int(p[idx[lo_k]]), int(p[idx[hi_k]])
            except (ValueError, IndexError):
                continue
            rid = p[idx[id_k]] if id_k and idx[id_k] < len(p) else "?"
            muc = p[idx[muc_k]] if muc_k and idx[muc_k] < len(p) else ""
            # BEN-*: D1 8/16 -> D1-8/D1-16; D3 4/7 -> D3-4/D3-7
            m = re.search(r"BEN-D(\d+)-(\d+)", rid)
            if m:
                muc = "D%s-%s" % (m.group(1), m.group(2))
            elif muc in ("8", "16") and "D1" in rid:
                muc = "D1-" + muc
            elif muc in ("4", "7") and "D3" in rid:
                muc = "D3-" + muc
            if rid.startswith("BEN") or muc.startswith("D"):
                add(lo, hi, muc, rid)

# 2) nhan-phien / suy tu ten thu muc bn|slow
phien = os.path.join(data, "lab", "nhan-phien.tsv")
if os.path.isfile(phien):
    with open(phien, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            try:
                lo = int(p[idx.get("start_ns", idx.get("t_bat_dau_mono_ns"))])
                hi = int(p[idx.get("stop_ns", idx.get("t_ket_thuc_mono_ns"))])
                muc = p[idx["muc"]]
                rid = p[idx["id"]] if "id" in idx else "?"
            except (ValueError, KeyError, IndexError, TypeError):
                continue
            add(lo, hi, muc, rid)

# 3) tu ten thu muc bn/B1-D1N2, benign-lieu/BEN-D1-8-r1, slow/* -> quet file ts
def ts_range_csv(path):
    lo = hi = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        header = fh.readline().rstrip("\n")
        sep = "\t" if "\t" in header.split("\n")[0] else ","
        cols = header.split(sep)
        if "ts_enter" not in cols:
            return None, None
        i = cols.index("ts_enter")
        for line in fh:
            p = line.rstrip("\n").split(sep)
            if len(p) <= i:
                continue
            try:
                t = int(p[i])
            except ValueError:
                continue
            if t <= 0:
                continue
            lo = t if lo is None else min(lo, t)
            hi = t if hi is None else max(hi, t)
    return lo, hi

for root, dirs, files in os.walk(data):
    for fn in files:
        if not (fn.endswith(".csv") or fn.endswith(".tsv") or fn.endswith(".bin")):
            continue
        path = os.path.join(root, fn)
        rel = os.path.relpath(path, data)
        parts = rel.split(os.sep)
        if len(parts) < 2:
            continue
        top, sess = parts[0], parts[1] if len(parts) > 1 else ""
        if top == "lab1-benign":
            top = "nen"
        if top not in ("nen", "bn", "benign-lieu", "slow"):
            continue
        # chi lay theo thu muc phien (co subdir) hoac file ngay nen
        if top == "nen":
            continue  # nen = 0 toan cuc o duoi
        if top == "bn":
            m = re.search(r"D1N(\d+)", sess)
            muc = m.group(1) if m else "0"
        elif top == "benign-lieu":
            m = re.search(r"BEN-D(\d+)-(\d+)", sess)
            muc = ("D%s-%s" % (m.group(1), m.group(2))) if m else "0"
        else:  # slow
            muc = "0"
        if path.endswith(".bin"):
            continue  # can rec-export; bo qua o day neu da co nhan
        lo, hi = ts_range_csv(path)
        if lo is None:
            continue
        # tranh trung neu da co tu nhan-phien
        add(lo, hi + 1, muc, sess)

# nen / slow mac dinh muc 0 neu chua co: gan 1 dong rong tu benign-khoi-dong
bk = os.path.join(data, "benign-khoi-dong.txt")
if os.path.isfile(bk):
    import re as _re
    text = open(bk, encoding="utf-8").read()
    m = _re.search(r"start_mono_ns\s*=\s*(\d+)", text)
    if m:
        t0 = int(m.group(1))
        add(t0, t0 + 7 * 86400 * 1_000_000_000, "0", "nen")

with open(out, "w", encoding="utf-8") as fh:
    fh.write("start_ns\tstop_ns\tmuc\n")
    for lo, hi, muc, _ in rows:
        fh.write("%d\t%d\t%s\n" % (lo, hi, muc))
print("muc_ranges", len(rows))
from collections import Counter
c = Counter(m for _, _, m, _ in rows)
print("muc_ranges_by_muc", " ".join("%s:%d" % kv for kv in sorted(c.items())))
PY

BK="$DATA/benign-khoi-dong.txt"
need "$BK"
TRAIN_UNTIL="$(python3 - "$BK" <<'PY'
import sys, re
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"start_mono_ns\s*=\s*(\d+)", text)
t0 = None
if m:
    t0 = int(m.group(1))
else:
    for line in text.splitlines():
        if line.strip().isdigit():
            t0 = int(line.strip())
            break
if t0 is None:
    raise SystemExit("benign-khoi-dong.txt thieu start_mono_ns")
print(t0 + 5 * 86400 * 1_000_000_000)
PY
)"
echo "train_until=$TRAIN_UNTIL  (het ngay 5 tu $BK)"

NHAN="$DATA/lab/nhan-tan-cong.tsv"
need "$NHAN"

# --- Bang kiem truoc khi cham ---
echo "=== BANG KIEM TRUOC KHI CHAM ==="
python3 - "$FEAT_ALL" "$MUC" "$NHAN" "$TRAIN_UNTIL" <<'PY'
import sys
from collections import Counter, defaultdict

feat, muc_path, nhan_path, cut_s = sys.argv[1:5]
cut = int(cut_s)

def read_tsv(path):
    with open(path, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        rows = []
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) < len(header):
                continue
            rows.append((idx, p))
        return header, rows

h, rows = read_tsv(feat)
# dem theo nguon (moi dong = 1 cua so, moi nhanh)
by_nguon = Counter()
by_muc = Counter()
wins = []
for idx, p in rows:
    nguon = p[idx["nguon"]] if "nguon" in idx else "?"
    by_nguon[nguon] += 1
    start, stop = int(p[idx["start_ns"]]), int(p[idx["stop_ns"]])
    wins.append((start, stop, nguon, p[idx["branch"]]))

# gan muc
muc_ranges = []
with open(muc_path, encoding="utf-8") as fh:
    mh = fh.readline().rstrip("\n").split("\t")
    mi = {x: i for i, x in enumerate(mh)}
    for line in fh:
        p = line.rstrip("\n").split("\t")
        muc_ranges.append((int(p[mi["start_ns"]]), int(p[mi["stop_ns"]]), p[mi["muc"]]))

def muc_of(start, stop):
    # uu tien muc cu the (khac "0") neu giao
    hit0 = None
    for lo, hi, m in muc_ranges:
        if start < hi and stop > lo:
            if m != "0":
                return m
            if hit0 is None:
                hit0 = m
    return hit0 if hit0 is not None else "0"

for start, stop, nguon, br in wins:
    by_muc[muc_of(start, stop)] += 1

print("cua_so_theo_nguon\t" + "\t".join("%s=%d" % kv for kv in sorted(by_nguon.items())))
print("cua_so_theo_muc\t" + "\t".join("%s=%d" % kv for kv in sorted(by_muc.items())))
print("moc_cat_ngay5_ns\t%d" % cut)

# nhan tan cong
atk = []
with open(nhan_path, encoding="utf-8") as fh:
    nh = fh.readline().rstrip("\n").split("\t")
    ni = {x: i for i, x in enumerate(nh)}
    for line in fh:
        p = line.rstrip("\n").split("\t")
        lop = p[ni["lop"]] if "lop" in ni else "?"
        if lop.upper().startswith("N"):
            continue
        atk.append((int(p[ni["t_bat_dau_mono_ns"]]), int(p[ni["t_ket_thuc_mono_ns"]]),
                    p[ni["id"]] if "id" in ni else "?"))

# dem giao theo id (moi id: so cua so unique theo start/stop/branch giao)
by_id = defaultdict(set)
for lo, hi, iid in atk:
    for start, stop, nguon, br in wins:
        if start < hi and stop > lo:
            by_id[iid].add((br, start, stop))

print("cua_so_giao_tan_cong_theo_id")
zero = []
for lo, hi, iid in atk:
    n = len(by_id.get(iid, ()))
    print("  %s\t%d" % (iid, n))
    if n == 0:
        zero.append(iid)
if zero:
    print("LOI: id tan cong khong co cua so giao: %s" % ",".join(zero), file=sys.stderr)
    sys.exit(2)
print("bang_kiem_OK")
PY

SCORE_DIR="$OUT/score"
mkdir -p "$SCORE_DIR"
echo "[score] features=$FEAT_ALL"
/usr/bin/time -f "TIME_score real=%e sec maxrss_kb=%M" \
  python3 "$ROOT/analysis/c5_score.py" \
    --features "$FEAT_ALL" \
    --nhan "$NHAN" \
    --muc "$MUC" \
    --train-until "$TRAIN_UNTIL" \
    --out "$SCORE_DIR" | tee "$OUT/score.log"

SVG="$OUT/bao_dong_gia_muc_det90.svg"
echo "[svg] -> $SVG"
python3 "$ROOT/scripts/c5_plot_svg.py" \
  --features "$FEAT_ALL" \
  --nhan "$NHAN" \
  --muc "$MUC" \
  --train-until "$TRAIN_UNTIL" \
  --out "$SVG" \
  --det 0.90

echo "=== XONG ==="
echo "ket_thuc=$(date -Iseconds)"
echo "tom_tat=$SCORE_DIR/tom_tat.tsv"
echo "svg=$SVG"
ls -la "$SCORE_DIR"/tom_tat.tsv "$SCORE_DIR"/tradeoff_*.tsv "$SVG" 2>/dev/null || true
