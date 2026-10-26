#!/usr/bin/env bash
# c5_pipeline.sh <thu_muc_du_lieu> <thu_muc_ra>
# Duong ong C5: rec-export (.bin) / CSV san → c5_extract → gop → muc.tsv → c5_score → SVG.
# Duong dan tuyet doi; log tung buoc; chay lai duoc.
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

# --- 1. Tim file .bin / .csv / .tsv trong bn/, benign-lieu/, slow/ (va bn goc) ---
mapfile -t INPUTS < <(
  find "$DATA/bn" "$DATA/benign-lieu" "$DATA/slow" \
    \( -name '*.bin' -o -name '*.csv' -o -name '*.tsv' \) 2>/dev/null \
    | sort || true
)
# neu khong co thu muc con: tim truc tiep duoi DATA
if [[ ${#INPUTS[@]} -eq 0 ]]; then
  mapfile -t INPUTS < <(
    find "$DATA" -maxdepth 2 \( -name '*.bin' -o -name '*.csv' -o -name '*.tsv' \) \
      ! -path '*/lab/*' | sort || true
  )
fi
echo "so_file_vao=${#INPUTS[@]}"
if [[ ${#INPUTS[@]} -eq 0 ]]; then
  echo "khong tim thay .bin/.csv/.tsv trong $DATA/{bn,benign-lieu,slow}" >&2
  exit 1
fi

# --- 2. rec-export / copy CSV ---
declare -a CSV_LIST=()
for f in "${INPUTS[@]}"; do
  rel="${f#"$DATA"/}"
  src_tag="$(echo "$rel" | tr '/' '_')"
  base="$(basename "$f")"
  case "$f" in
    *.bin)
      out_csv="$CSV_DIR/${src_tag}.csv"
      echo "[export] $f -> $out_csv"
      /usr/bin/time -f "TIME_export real=%e sec maxrss_kb=%M" \
        "$ROOT/bin/rec-export" "$f" > "$out_csv"
      ;;
    *.csv|*.tsv)
      out_csv="$CSV_DIR/${src_tag}"
      echo "[csv] $f -> $out_csv"
      ln -sfn "$f" "$out_csv"
      ;;
  esac
  CSV_LIST+=("$out_csv|$src_tag")
done

# --- 3. c5_extract tung file, ghi features rieng ---
declare -a FEAT_PARTS=()
for item in "${CSV_LIST[@]}"; do
  csv="${item%%|*}"
  src="${item##*|}"
  feat="$FEAT_DIR/${src}.tsv"
  echo "[extract] $csv nguon=$src"
  /usr/bin/time -f "TIME_extract real=%e sec maxrss_kb=%M" \
    python3 "$ROOT/scripts/c5_extract.py" --tsv "$csv" --out "$feat" --source "$src"
  FEAT_PARTS+=("$feat")
done

# --- 4. Gop TSV (union cot; dien nan) ---
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
# union cot: giu thu tu file dau, them cot moi o cuoi
union = list(headers[0])
seen = set(union)
for h in headers[1:]:
    for c in h:
        if c not in seen:
            union.append(c)
            seen.add(c)
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

# --- 5. muc.tsv tu lab/nhan-lieu.tsv (+ nhan phien neu co) ---
MUC="$OUT/muc.tsv"
echo "[muc] -> $MUC"
python3 - "$DATA" "$MUC" <<'PY'
import os, sys
data, out = sys.argv[1], sys.argv[2]
rows = []  # (start, stop, muc, id)
lieu = os.path.join(data, "lab", "nhan-lieu.tsv")
if os.path.isfile(lieu):
    with open(lieu, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        # chap nhan ten cot linh hoat
        lo_k = next((k for k in ("t_bat_dau_mono_ns", "start_ns", "t_bat_dau") if k in idx), None)
        hi_k = next((k for k in ("t_ket_thuc_mono_ns", "stop_ns", "t_ket_thuc") if k in idx), None)
        muc_k = next((k for k in ("muc", "muc_tranh_chap") if k in idx), None)
        id_k = "id" if "id" in idx else None
        if lo_k and hi_k and muc_k:
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) <= max(idx[lo_k], idx[hi_k], idx[muc_k]):
                    continue
                try:
                    lo, hi = int(p[idx[lo_k]]), int(p[idx[hi_k]])
                except ValueError:
                    continue
                muc = p[idx[muc_k]]
                rid = p[idx[id_k]] if id_k and idx[id_k] < len(p) else "?"
                # nhan-lieu: BEN-* (va moi dong co muc)
                rows.append((lo, hi, muc, rid))
# nhan phien: lab/nhan-phien.tsv neu co (start_ns stop_ns muc id)
phien = os.path.join(data, "lab", "nhan-phien.tsv")
if os.path.isfile(phien):
    with open(phien, encoding="utf-8") as fh:
        header = fh.readline().rstrip("\n").split("\t")
        idx = {h: i for i, h in enumerate(header)}
        for line in fh:
            p = line.rstrip("\n").split("\t")
            try:
                lo = int(p[idx.get("start_ns", idx.get("t_bat_dau_mono_ns", 0))])
                hi = int(p[idx.get("stop_ns", idx.get("t_ket_thuc_mono_ns", 1))])
                muc = p[idx["muc"]]
            except (ValueError, KeyError, IndexError):
                continue
            rows.append((lo, hi, muc, "phien"))
with open(out, "w", encoding="utf-8") as fh:
    fh.write("start_ns\tstop_ns\tmuc\n")
    for lo, hi, muc, _ in rows:
        fh.write("%d\t%d\t%s\n" % (lo, hi, muc))
print("muc_ranges", len(rows))
PY

# --- 6. train-until = het ngay 5 tu benign-khoi-dong.txt ---
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
        line = line.strip()
        if line.isdigit():
            t0 = int(line)
            break
if t0 is None:
    raise SystemExit("benign-khoi-dong.txt thieu start_mono_ns")
day_ns = 86_400 * 1_000_000_000
# het ngay 5 = sau 5 ngay day du ke tu moc bat dau
print(t0 + 5 * day_ns)
PY
)"
echo "train_until=$TRAIN_UNTIL  (het ngay 5 tu $BK)"

NHAN="$DATA/lab/nhan-tan-cong.tsv"
need "$NHAN"

# --- 7. c5_score ---
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

# --- 8. SVG ---
SVG="$OUT/bao_dong_gia_muc_det90.svg"
echo "[svg] -> $SVG"
python3 "$ROOT/scripts/c5_plot_svg.py" \
  --features "$FEAT_ALL" \
  --nhan "$NHAN" \
  --muc "$MUC" \
  --train-until "$TRAIN_UNTIL" \
  --out "$SVG" \
  --det 0.90

# --- tong ket ---
echo "=== XONG ==="
echo "ket_thuc=$(date -Iseconds)"
echo "tom_tat=$SCORE_DIR/tom_tat.tsv"
echo "svg=$SVG"
ls -la "$SCORE_DIR"/tom_tat.tsv "$SCORE_DIR"/tradeoff_*.tsv "$SVG" 2>/dev/null || true
