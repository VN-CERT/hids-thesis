#!/usr/bin/env bash
# m5d_bpf_hids.sh — ghi JSON bpftool prog show -j (chi hids_*).
set -euo pipefail
out=$1
bpftool prog show -j 2>/dev/null | python3 -c '
import json,sys
progs=json.load(sys.stdin)
out=[p for p in progs if p.get("name","").startswith("hids_")]
json.dump(out,sys.stdout)
' >"$out"
