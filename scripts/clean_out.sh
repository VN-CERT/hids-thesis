#!/usr/bin/env bash
# Xoa file .bin trong out/ cu hon 2 ngay; khong xoa validation/ hay out/jobs/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
deleted=0
while IFS= read -r -d '' f; do
	echo "clean-out: xoa $f"
	rm -f "$f"
	deleted=$((deleted + 1))
done < <(find out -type f -name '*.bin' -mtime +2 ! -path 'out/jobs/*' -print0 2>/dev/null)
echo "clean-out: da xoa $deleted file .bin (mtime > 2 ngay, ngoai out/jobs/)"
