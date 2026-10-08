#!/usr/bin/env bash
# m5d_irq_sample.sh — delta IWI/CAL/RES trong /proc/interrupts trong N giay.
set -euo pipefail
sec=${1:-10}
out=${2:-}
irq_line_totals() {
	awk -v want="$1" '
		/^ *[A-Z0-9]+:/ {
			split($1, a, ":");
			if (a[1] != want) next;
			s = 0;
			for (i = 2; i <= NF; i++) s += $i;
			t += s;
		}
		END { print t+0 }
	' /proc/interrupts
}
iwi0=$(irq_line_totals IWI); cal0=$(irq_line_totals CAL); res0=$(irq_line_totals RES)
sleep "$sec"
iwi1=$(irq_line_totals IWI); cal1=$(irq_line_totals CAL); res1=$(irq_line_totals RES)
di=$((iwi1 - iwi0)); dc=$((cal1 - cal0)); dr=$((res1 - res0))
line="ts=$(date -Iseconds) duration_s=$sec IWI_delta=$di CAL_delta=$dc RES_delta=$dr IWI_per_s=$((di / sec)) CAL_per_s=$((dc / sec))"
if [[ -n $out ]]; then echo "$line" >>"$out"; else echo "$line"; fi
