// rec-chain kiem day seq noi tiep qua nhieu file .bin (xoay vong).
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strconv"
	"text/tabwriter"

	"hids/internal/recseq"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rec-chain: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "cach dung: rec-chain <file1.bin> <file2.bin> ...\n")
	}
	flag.Parse()
	if flag.NArg() < 1 {
		flag.Usage()
		return fmt.Errorf("can it nhat mot file .bin")
	}
	rep, err := recseq.ChainBins(flag.Args())
	if err != nil {
		return err
	}

	for _, fr := range rep.Files {
		fmt.Printf("=== %s (tong %d ban ghi) ===\n", fr.Path, fr.Total)
		if fr.StatsErr != nil {
			fmt.Printf("  khong doc duoc .stats: %v\n", fr.StatsErr)
		}
		cpus := make([]int, 0, len(fr.PerCPU))
		for cpu := range fr.PerCPU {
			cpus = append(cpus, cpu)
		}
		sort.Ints(cpus)
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
		fmt.Fprintln(w, "cpu\tban_ghi\tseq_min\tseq_max\tlo_hong\tseq_thieu\tseq_cuoi\tmat\t")
		var totHoles int64
		var totMissing, totDrops uint64
		for _, cpu := range cpus {
			a := fr.PerCPU[cpu]
			seqLast, drops := "-", "-"
			if a.HasStats {
				seqLast = strconv.FormatUint(uint64(a.SeqLast), 10)
				drops = strconv.FormatUint(a.Drops, 10)
				totDrops += a.Drops
			}
			minS, maxS := "-", "-"
			if a.Records > 0 {
				minS = strconv.FormatUint(uint64(a.Min), 10)
				maxS = strconv.FormatUint(uint64(a.Max), 10)
			}
			fmt.Fprintf(w, "%d\t%d\t%s\t%s\t%d\t%d\t%s\t%s\t\n",
				cpu, a.Records, minS, maxS, a.Holes, a.Missing, seqLast, drops)
			totHoles += a.Holes
			totMissing += a.Missing
		}
		fmt.Fprintf(w, "TONG\t\t\t\t%d\t%d\t\t%d\t\n", totHoles, totMissing, totDrops)
		w.Flush()
		fmt.Println()
	}

	if len(rep.Boundaries) > 0 {
		fmt.Println("ranh gioi file lien ke (seq theo CPU)")
		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
		fmt.Fprintln(w, "cpu\tfile_truoc\tfile_sau\tseq_max_truoc\tseq_min_sau\tlo_hong\tseq_thieu\t")
		var bHoles int64
		var bMissing uint64
		for _, g := range rep.Boundaries {
			if !g.PrevHasSeq && !g.NextHasSeq {
				continue
			}
			prevMax, nextMin := "-", "-"
			if g.PrevHasSeq {
				prevMax = strconv.FormatUint(uint64(g.PrevMax), 10)
			}
			if g.NextHasSeq {
				nextMin = strconv.FormatUint(uint64(g.NextMin), 10)
			}
			fmt.Fprintf(w, "%d\t%s\t%s\t%s\t%s\t%d\t%d\t\n",
				g.CPU, g.PrevFile, g.NextFile, prevMax, nextMin, g.Holes, g.Missing)
			bHoles += g.Holes
			bMissing += g.Missing
		}
		fmt.Fprintf(w, "TONG\t\t\t\t\t%d\t%d\t\n", bHoles, bMissing)
		w.Flush()
		fmt.Println()
		fmt.Printf("tong lo hong ranh gioi: %d | tong seq thieu ranh gioi: %d\n", bHoles, bMissing)
	}
	return nil
}
