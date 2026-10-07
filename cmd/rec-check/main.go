// rec-check: G5 phan du va tong thanh phan theo tid trong mot cua so ts_enter.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"math"
	"os"
	"sort"
	"text/tabwriter"

	"hids/internal/recfmt"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rec-check: %v\n", err)
		os.Exit(1)
	}
}

type residualStats struct {
	label string
	n     int
	p50   int64
	p99   int64
	p999  int64
	max   int64
	over1 int
	over10 int
}

func run() error {
	tid := flag.Uint("tid", 0, "chi tinh cho mot tid (bat buoc neu loc cua so)")
	fromMono := flag.Uint64("from-mono", 0, "ts_enter > gia tri nay (ns)")
	toMono := flag.Uint64("to-mono", 0, "ts_enter <= gia tri nay (ns)")
	flag.Parse()
	if flag.NArg() != 1 {
		return fmt.Errorf("cach dung: rec-check [-tid T] [-from-mono A] [-to-mono B] <file.bin>")
	}

	f, err := os.Open(flag.Arg(0))
	if err != nil {
		return err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 4*1024*1024)
	header, err := recfmt.ReadHeader(br)
	if err != nil {
		return err
	}
	recordSize, err := recfmt.RecordSizeFromHeader(header)
	if err != nil {
		return err
	}
	payload, err := recfmt.RecordPayloadReader(header, br)
	if err != nil {
		return err
	}

	var recs []recfmt.Record
	_, _, err = recfmt.ForEach(payload, recordSize, func(r recfmt.Record) error {
		if *tid != 0 && r.TID != uint32(*tid) {
			return nil
		}
		if *fromMono != 0 && r.TsEnter <= *fromMono {
			return nil
		}
		if *toMono != 0 && r.TsEnter > *toMono {
			return nil
		}
		recs = append(recs, r)
		return nil
	})
	if err != nil {
		return err
	}

	var cpu, steal, irq, rq, volNs, stealOff uint64
	flagCounts := map[string]int64{
		"FIRST": 0, "GAP_BEFORE": 0, "D_SLEEP": 0, "MIGRATED": 0,
		"OVERFLOW": 0, "STEAL_FALLBACK": 0, "CLAMPED": 0,
	}
	for _, r := range recs {
		cpu += uint64(r.CPUNs)
		steal += uint64(r.StealNs)
		irq += uint64(r.IrqNs)
		rq += uint64(r.RqNs)
		volNs += uint64(r.VolUs) * 1000
		stealOff += uint64(r.StealOffNs)
		if r.Flags&recfmt.FlagFirst != 0 {
			flagCounts["FIRST"]++
		}
		if r.Flags&recfmt.FlagGapBefore != 0 {
			flagCounts["GAP_BEFORE"]++
		}
		if r.Flags&recfmt.FlagDSleep != 0 {
			flagCounts["D_SLEEP"]++
		}
		if r.Flags&recfmt.FlagMigrated != 0 {
			flagCounts["MIGRATED"]++
		}
		if r.Flags&recfmt.FlagOverflow != 0 {
			flagCounts["OVERFLOW"]++
		}
		if r.Flags&recfmt.FlagStealFallback != 0 {
			flagCounts["STEAL_FALLBACK"]++
		}
		if r.Flags&recfmt.FlagClamped != 0 {
			flagCounts["CLAMPED"]++
		}
	}

	fmt.Printf("so ban ghi trong cua so: %d\n", len(recs))
	if *tid != 0 {
		fmt.Printf("tid: %d\n", *tid)
	}
	if *fromMono != 0 || *toMono != 0 {
		fmt.Printf("cua so ts_enter: (%d, %d]\n", *fromMono, *toMono)
	}

	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(tw, "co\tso_ban_ghi\n")
	for _, name := range []string{"FIRST", "GAP_BEFORE", "D_SLEEP", "MIGRATED", "OVERFLOW", "STEAL_FALLBACK", "CLAMPED"} {
		fmt.Fprintf(tw, "%s\t%d\n", name, flagCounts[name])
	}
	tw.Flush()

	fmt.Println("--- tong thanh phan (ns) ---")
	fmt.Printf("cpu %d\nsteal %d\nirq %d\nrq %d\nvol %d\nsteal_off %d\n", cpu, steal, irq, rq, volNs, stealOff)
	fmt.Printf("cpu+steal+irq %d\n", cpu+steal+irq)

	printResidualGroup("tat ca (tru FIRST)", recs, false, false)
	printResidualGroup("khong GAP_BEFORE", recs, true, false)
	printResidualGroup("co GAP_BEFORE", recs, false, true)

	return nil
}

func printResidualGroup(label string, recs []recfmt.Record, skipGap bool, onlyGap bool) {
	byTID := map[uint32][]recfmt.Record{}
	for _, r := range recs {
		byTID[r.TID] = append(byTID[r.TID], r)
	}
	var abs []int64
	for _, list := range byTID {
		sort.Slice(list, func(i, j int) bool { return list[i].TsEnter < list[j].TsEnter })
		for i := 1; i < len(list); i++ {
			cur, prev := list[i], list[i-1]
			if cur.Flags&recfmt.FlagFirst != 0 {
				continue
			}
			gap := cur.Flags&recfmt.FlagGapBefore != 0
			if skipGap && gap {
				continue
			}
			if onlyGap && !gap {
				continue
			}
			dt := cur.TsEnter - prev.TsEnter
			sum := uint64(cur.CPUNs) + uint64(cur.StealNs) + uint64(cur.IrqNs) +
				uint64(cur.RqNs) + uint64(cur.VolUs)*1000
			var res int64
			if dt >= sum {
				res = int64(dt - sum)
			} else {
				res = -int64(sum - dt)
			}
			if res < 0 {
				res = -res
			}
			abs = append(abs, res)
		}
	}
	st := computeResidual(label, abs)
	fmt.Printf("--- G5 phan du |%s| (ns) ---\n", st.label)
	fmt.Printf("so khoang: %d\n", st.n)
	if st.n == 0 {
		return
	}
	fmt.Printf("p50 %d\np99 %d\np99.9 %d\nmax %d\n", st.p50, st.p99, st.p999, st.max)
	fmt.Printf("so khoang |phan du| > 1000 ns: %d\n", st.over1)
	fmt.Printf("so khoang |phan du| > 10000 ns: %d\n", st.over10)
}

func computeResidual(label string, abs []int64) residualStats {
	st := residualStats{label: label, n: len(abs)}
	if len(abs) == 0 {
		return st
	}
	sort.Slice(abs, func(i, j int) bool { return abs[i] < abs[j] })
	st.p50 = pct(abs, 50)
	st.p99 = pct(abs, 99)
	st.p999 = pct(abs, 99.9)
	st.max = abs[len(abs)-1]
	for _, v := range abs {
		if v > 1000 {
			st.over1++
		}
		if v > 10000 {
			st.over10++
		}
	}
	return st
}

func pct(sorted []int64, p float64) int64 {
	if len(sorted) == 0 {
		return 0
	}
	rank := int(math.Ceil(p/100.0*float64(len(sorted)))) - 1
	if rank < 0 {
		rank = 0
	}
	if rank >= len(sorted) {
		rank = len(sorted) - 1
	}
	return sorted[rank]
}
