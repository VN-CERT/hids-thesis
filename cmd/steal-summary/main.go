// steal-summary tong hop file CSV do steal-probe ghi ra.
// Cong cu chi in gia tri do duoc canh gia tri tham chieu /proc/stat, khong ket luan dat hay khong.
package main

import (
	"flag"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"
	"time"

	"hids/internal/hostinfo"
	"hids/internal/stealcsv"
)

const clockLayout = "15:04:05"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "steal-summary: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	from := flag.String("from", "", "chi tinh tu gio nay (HH:MM:SS, gio may)")
	to := flag.String("to", "", "chi tinh den gio nay (HH:MM:SS, gio may)")
	bucket := flag.Duration("bucket", 0, "gop theo khoi thoi gian, vi du 20s; de trong thi in bang theo tung CPU")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "cach dung: steal-summary [tuy chon] <file.csv>\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		return fmt.Errorf("can dung mot file CSV")
	}
	path := flag.Arg(0)

	fromSec, err := parseClock(*from)
	if err != nil {
		return fmt.Errorf("-from: %w", err)
	}
	toSec, err := parseClock(*to)
	if err != nil {
		return fmt.Errorf("-to: %w", err)
	}
	if fromSec >= 0 && toSec >= 0 && toSec < fromSec {
		return fmt.Errorf("-to (%s) som hon -from (%s)", *to, *from)
	}
	if *bucket < 0 {
		return fmt.Errorf("-bucket khong duoc am")
	}

	recs, meta, err := stealcsv.Read(path)
	if err != nil {
		return err
	}

	recs = filterByClock(recs, fromSec, toSec)
	if len(recs) == 0 {
		return fmt.Errorf("khong co dong nao trong khoang da chon")
	}
	sort.SliceStable(recs, func(i, j int) bool { return recs[i].MonoNs < recs[j].MonoNs })

	userHZ, userHZSrc, err := resolveUserHZ(meta)
	if err != nil {
		return err
	}

	printContext(path, meta, recs, userHZ, userHZSrc)

	if *bucket > 0 {
		return printBuckets(recs, *bucket, userHZ)
	}
	return printPerCPU(recs, userHZ)
}

func parseClock(s string) (int, error) {
	if s == "" {
		return -1, nil
	}
	t, err := time.Parse(clockLayout, s)
	if err != nil {
		return -1, fmt.Errorf("can dinh dang HH:MM:SS: %w", err)
	}
	return t.Hour()*3600 + t.Minute()*60 + t.Second(), nil
}

func clockSeconds(t time.Time) int {
	return t.Hour()*3600 + t.Minute()*60 + t.Second()
}

func filterByClock(recs []stealcsv.Record, fromSec, toSec int) []stealcsv.Record {
	if fromSec < 0 && toSec < 0 {
		return recs
	}
	out := recs[:0:0]
	for _, r := range recs {
		sec := clockSeconds(r.Wall)
		if fromSec >= 0 && sec < fromSec {
			continue
		}
		if toSec >= 0 && sec > toSec {
			continue
		}
		out = append(out, r)
	}
	return out
}

func resolveUserHZ(meta stealcsv.Meta) (uint64, string, error) {
	if raw := meta.Get("user_hz"); raw != "" {
		field := strings.Fields(raw)[0]
		hz, err := strconv.ParseUint(field, 10, 64)
		if err == nil && hz > 0 {
			return hz, "header CSV: " + raw, nil
		}
	}
	hz, src, err := hostinfo.UserHZ()
	if err != nil {
		return 0, "", err
	}
	return hz, "may dang chay: " + src, nil
}

func printContext(path string, meta stealcsv.Meta, recs []stealcsv.Record, userHZ uint64, userHZSrc string) {
	first, last := recs[0], recs[len(recs)-1]
	cpus := map[int]struct{}{}
	for _, r := range recs {
		cpus[r.CPU] = struct{}{}
	}

	fmt.Printf("file: %s\n", path)
	for _, line := range meta.Lines {
		fmt.Printf("# %s\n", line)
	}
	fmt.Printf("khoang: %s .. %s (%.3f s theo dong ho may)\n",
		first.Wall.Format(stealcsv.WallLayout), last.Wall.Format(stealcsv.WallLayout),
		last.Wall.Sub(first.Wall).Seconds())
	fmt.Printf("so dong: %d, so CPU: %d\n", len(recs), len(cpus))
	fmt.Printf("USER_HZ dung de doi tick sang ms: %d (%s)\n", userHZ, userHZSrc)
	fmt.Printf("tham chieu: cot procstat_steal_ticks lay tu /proc/stat luc do\n\n")
}

type series struct {
	first, last stealcsv.Record
	n           int
}

func groupByCPU(recs []stealcsv.Record) (map[int]*series, []int) {
	byCPU := map[int]*series{}
	for _, r := range recs {
		s, ok := byCPU[r.CPU]
		if !ok {
			byCPU[r.CPU] = &series{first: r, last: r, n: 1}
			continue
		}
		s.last = r
		s.n++
	}

	cpus := make([]int, 0, len(byCPU))
	for cpu := range byCPU {
		cpus = append(cpus, cpu)
	}
	sort.Ints(cpus)
	return byCPU, cpus
}

func printPerCPU(recs []stealcsv.Record, userHZ uint64) error {
	byCPU, cpus := groupByCPU(recs)

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "cpu\tmau\tdvmw_ms\tdrq_ms\tdprocstat_ms\tdvmw/dprocstat\tdrq/dprocstat\t")

	var sumVmw, sumRq, sumProc float64
	var haveVmw, haveRq bool

	for _, cpu := range cpus {
		s := byCPU[cpu]
		if s.n < 2 {
			fmt.Fprintf(w, "%d\t%d\t-\t-\t-\t-\t-\t\n", cpu, s.n)
			continue
		}

		procMs := ticksToMs(s.last.ProcstatTicks-s.first.ProcstatTicks, userHZ)
		sumProc += procMs

		vmwCell, rqCell := "-", "-"
		vmwRatio, rqRatio := "-", "-"

		if s.first.HasVmw && s.last.HasVmw {
			vmwMs := float64(s.last.VmwNs-s.first.VmwNs) / 1e6
			sumVmw += vmwMs
			haveVmw = true
			vmwCell = fmt.Sprintf("%.3f", vmwMs)
			vmwRatio = ratio(vmwMs, procMs)
		}
		if s.first.HasRq && s.last.HasRq {
			rqMs := float64(s.last.RqStealNs-s.first.RqStealNs) / 1e6
			sumRq += rqMs
			haveRq = true
			rqCell = fmt.Sprintf("%.3f", rqMs)
			rqRatio = ratio(rqMs, procMs)
		}

		fmt.Fprintf(w, "%d\t%d\t%s\t%s\t%.3f\t%s\t%s\t\n", cpu, s.n, vmwCell, rqCell, procMs, vmwRatio, rqRatio)
	}

	totalVmw, totalRq := "-", "-"
	totalVmwRatio, totalRqRatio := "-", "-"
	if haveVmw {
		totalVmw = fmt.Sprintf("%.3f", sumVmw)
		totalVmwRatio = ratio(sumVmw, sumProc)
	}
	if haveRq {
		totalRq = fmt.Sprintf("%.3f", sumRq)
		totalRqRatio = ratio(sumRq, sumProc)
	}
	fmt.Fprintf(w, "TONG\t%d\t%s\t%s\t%.3f\t%s\t%s\t\n", len(recs), totalVmw, totalRq, sumProc, totalVmwRatio, totalRqRatio)

	return w.Flush()
}

type bucketAgg struct {
	vmwNs    uint64
	rqNs     uint64
	procTick uint64
	hasVmw   bool
	hasRq    bool
}

func printBuckets(recs []stealcsv.Record, bucket time.Duration, userHZ uint64) error {
	bucketSec := int(bucket / time.Second)
	if bucketSec <= 0 {
		return fmt.Errorf("-bucket phai tu 1s tro len")
	}

	prev := map[int]stealcsv.Record{}
	agg := map[int]*bucketAgg{}

	for _, r := range recs {
		p, ok := prev[r.CPU]
		prev[r.CPU] = r
		if !ok {
			continue
		}

		key := clockSeconds(r.Wall) / bucketSec * bucketSec
		a := agg[key]
		if a == nil {
			a = &bucketAgg{}
			agg[key] = a
		}
		if r.HasVmw && p.HasVmw && r.VmwNs >= p.VmwNs {
			a.vmwNs += r.VmwNs - p.VmwNs
			a.hasVmw = true
		}
		if r.HasRq && p.HasRq && r.RqStealNs >= p.RqStealNs {
			a.rqNs += r.RqStealNs - p.RqStealNs
			a.hasRq = true
		}
		if r.ProcstatTicks >= p.ProcstatTicks {
			a.procTick += r.ProcstatTicks - p.ProcstatTicks
		}
	}

	keys := make([]int, 0, len(agg))
	for k := range agg {
		keys = append(keys, k)
	}
	sort.Ints(keys)

	fmt.Printf("khoi %s, tong tren tat ca CPU, chenh lech giua hai lan chup lien tiep\n\n", bucket)

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "bat_dau\tvmw_ms\trq_ms\tprocstat_ms\t")

	var sumVmw, sumRq, sumProc float64
	var haveVmw, haveRq bool
	for _, k := range keys {
		a := agg[k]
		procMs := ticksToMs(a.procTick, userHZ)
		sumProc += procMs

		vmwCell, rqCell := "-", "-"
		if a.hasVmw {
			vmwMs := float64(a.vmwNs) / 1e6
			sumVmw += vmwMs
			haveVmw = true
			vmwCell = fmt.Sprintf("%.3f", vmwMs)
		}
		if a.hasRq {
			rqMs := float64(a.rqNs) / 1e6
			sumRq += rqMs
			haveRq = true
			rqCell = fmt.Sprintf("%.3f", rqMs)
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%.3f\t\n", formatClock(k), vmwCell, rqCell, procMs)
	}

	totalVmw, totalRq := "-", "-"
	if haveVmw {
		totalVmw = fmt.Sprintf("%.3f", sumVmw)
	}
	if haveRq {
		totalRq = fmt.Sprintf("%.3f", sumRq)
	}
	fmt.Fprintf(w, "TONG\t%s\t%s\t%.3f\t\n", totalVmw, totalRq, sumProc)

	return w.Flush()
}

func ticksToMs(ticks, userHZ uint64) float64 {
	return float64(ticks) * 1000 / float64(userHZ)
}

func ratio(a, b float64) string {
	if b == 0 {
		return "-"
	}
	return fmt.Sprintf("%.3f", a/b)
}

func formatClock(sec int) string {
	return fmt.Sprintf("%02d:%02d:%02d", sec/3600, (sec%3600)/60, sec%60)
}
