// rec-stat thong ke file .bin do hids-collect ghi ra.
// Cong cu chi in so lieu, khong ket luan dat hay khong.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"slices"
	"sort"
	"strconv"
	"strings"
	"text/tabwriter"

	"hids/internal/recfmt"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rec-stat: %v\n", err)
		os.Exit(1)
	}
}

type tgidInfo struct {
	tgid   int
	source string // "/proc" hoac "tid" (tien trinh da thoat, coi tid la tgid)
}

// procCount gom so lieu cua mot tien trinh hoac mot thread.
type procCount struct {
	records int64
	nr      int64
	first   int64
	gap     int64
}

func run() error {
	tgidFilter := flag.Int("tgid", 0, "chi tinh cho mot tien trinh (tgid)")
	nrFilter := flag.Int("nr", -1, "dem rieng mot syscall_nr")
	fromMono := flag.Uint64("from-mono", 0, "chi tinh cac ban ghi co ts_enter >= gia tri nay (ns, CLOCK_MONOTONIC)")
	toMono := flag.Uint64("to-mono", 0, "chi tinh cac ban ghi co ts_enter <= gia tri nay (ns, CLOCK_MONOTONIC)")
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "cach dung: rec-stat [tuy chon] <file.bin>\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() != 1 {
		flag.Usage()
		return fmt.Errorf("can dung mot file .bin")
	}
	path := flag.Arg(0)

	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 4*1024*1024)
	header, err := recfmt.ReadHeader(br)
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}

	tgidCache := map[uint32]tgidInfo{}
	byTID := map[uint32]*procCount{}
	byTGID := map[int]*procCount{}
	tgidSource := map[int]string{}
	bySyscall := map[uint16]int64{}
	seqByCPU := map[int][]uint32{}

	var total, kept, nrCount, firstCount, gapCount int64
	var minTs, maxTs uint64

	_, leftover, err := recfmt.ForEach(br, func(r recfmt.Record) error {
		total++
		// Bang seq theo CPU luon tinh tren TOAN BO ban ghi trong file: seq dem
		// moi lan dinh ghi, loc bot ban ghi se tao ra lo hong gia.
		seqByCPU[r.CPU()] = append(seqByCPU[r.CPU()], r.Seq)

		if *fromMono > 0 && r.TsEnter < *fromMono {
			return nil
		}
		if *toMono > 0 && r.TsEnter > *toMono {
			return nil
		}

		info := resolveTGID(tgidCache, r.TID)
		if *tgidFilter != 0 && info.tgid != *tgidFilter {
			return nil
		}

		kept++
		if kept == 1 || r.TsEnter < minTs {
			minTs = r.TsEnter
		}
		if r.TsEnter > maxTs {
			maxTs = r.TsEnter
		}

		tid := get(byTID, r.TID)
		tg := get(byTGID, info.tgid)
		tgidSource[info.tgid] = info.source
		bySyscall[r.SyscallNr]++

		tid.records++
		tg.records++
		if *nrFilter >= 0 && int(r.SyscallNr) == *nrFilter {
			nrCount++
			tid.nr++
			tg.nr++
		}
		if r.Flags&recfmt.FlagFirst != 0 {
			firstCount++
			tid.first++
			tg.first++
		}
		if r.Flags&recfmt.FlagGapBefore != 0 {
			gapCount++
			tid.gap++
			tg.gap++
		}
		return nil
	})
	if err != nil {
		return err
	}

	fmt.Printf("file: %s\n", path)
	for _, line := range header.Lines {
		fmt.Printf("# %s\n", line)
	}
	fmt.Println()

	fmt.Printf("tong so ban ghi trong file : %d\n", total)
	if hasFilter(*tgidFilter, *nrFilter, *fromMono, *toMono) {
		fmt.Printf("so ban ghi sau khi loc     : %d\n", kept)
		fmt.Printf("bo loc                     : %s\n", filterText(*tgidFilter, *fromMono, *toMono))
	}
	if leftover != 0 {
		fmt.Printf("CANH BAO: con %d byte thua o cuoi file, khong du mot ban ghi %d byte\n", leftover, recfmt.RecordSize)
	}
	if kept > 0 {
		fmt.Printf("ts_enter nho nhat / lon nhat: %d / %d (ns, CLOCK_MONOTONIC)\n", minTs, maxTs)
	}
	fmt.Printf("ban ghi co co FIRST        : %d\n", firstCount)
	fmt.Printf("ban ghi co co GAP_BEFORE   : %d\n", gapCount)
	if *nrFilter >= 0 {
		fmt.Printf("ban ghi co syscall_nr=%-5d: %d\n", *nrFilter, nrCount)
	}
	fmt.Println()

	printTGID(byTGID, tgidSource, *nrFilter)
	printTID(byTID, tgidCache, *nrFilter)
	printSyscalls(bySyscall)

	return printCPU(path, seqByCPU, total, kept)
}

func get[K comparable](m map[K]*procCount, k K) *procCount {
	c, ok := m[k]
	if !ok {
		c = &procCount{}
		m[k] = c
	}
	return c
}

func hasFilter(tgid, nr int, from, to uint64) bool {
	return tgid != 0 || nr >= 0 || from > 0 || to > 0
}

func filterText(tgid int, from, to uint64) string {
	var parts []string
	if tgid != 0 {
		parts = append(parts, fmt.Sprintf("tgid=%d", tgid))
	}
	if from > 0 {
		parts = append(parts, fmt.Sprintf("ts_enter>=%d", from))
	}
	if to > 0 {
		parts = append(parts, fmt.Sprintf("ts_enter<=%d", to))
	}
	if len(parts) == 0 {
		return "khong co"
	}
	return strings.Join(parts, ", ")
}

// resolveTGID tra tgid cua mot tid trong /proc. Neu tien trinh da thoat thi coi
// tid chinh la tgid (dung voi tien trinh don luong) va ghi ro nguon la "tid".
func resolveTGID(cache map[uint32]tgidInfo, tid uint32) tgidInfo {
	if info, ok := cache[tid]; ok {
		return info
	}

	info := tgidInfo{tgid: int(tid), source: "tid"}
	raw, err := os.ReadFile(fmt.Sprintf("/proc/%d/status", tid))
	if err == nil {
		for _, line := range strings.Split(string(raw), "\n") {
			rest, ok := strings.CutPrefix(line, "Tgid:")
			if !ok {
				continue
			}
			if n, err := strconv.Atoi(strings.TrimSpace(rest)); err == nil {
				info = tgidInfo{tgid: n, source: "/proc"}
			}
			break
		}
	}

	cache[tid] = info
	return info
}

func printTGID(byTGID map[int]*procCount, source map[int]string, nrFilter int) {
	type row struct {
		tgid int
		c    *procCount
	}
	rows := make([]row, 0, len(byTGID))
	for tgid, c := range byTGID {
		rows = append(rows, row{tgid, c})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].c.records != rows[j].c.records {
			return rows[i].c.records > rows[j].c.records
		}
		return rows[i].tgid < rows[j].tgid
	})

	fmt.Printf("so ban ghi theo tgid (%d tien trinh)\n", len(rows))
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	if nrFilter >= 0 {
		fmt.Fprintf(w, "tgid\tban_ghi\tnr=%d\tFIRST\tGAP_BEFORE\tnguon_tgid\t\n", nrFilter)
	} else {
		fmt.Fprintln(w, "tgid\tban_ghi\tFIRST\tGAP_BEFORE\tnguon_tgid\t")
	}
	var tot procCount
	for _, r := range rows {
		src := source[r.tgid]
		if src == "tid" {
			src = "? (suy tu tid)"
		}
		if nrFilter >= 0 {
			fmt.Fprintf(w, "%d\t%d\t%d\t%d\t%d\t%s\t\n", r.tgid, r.c.records, r.c.nr, r.c.first, r.c.gap, src)
		} else {
			fmt.Fprintf(w, "%d\t%d\t%d\t%d\t%s\t\n", r.tgid, r.c.records, r.c.first, r.c.gap, src)
		}
		tot.records += r.c.records
		tot.nr += r.c.nr
		tot.first += r.c.first
		tot.gap += r.c.gap
	}
	if nrFilter >= 0 {
		fmt.Fprintf(w, "TONG\t%d\t%d\t%d\t%d\t\t\n", tot.records, tot.nr, tot.first, tot.gap)
	} else {
		fmt.Fprintf(w, "TONG\t%d\t%d\t%d\t\t\n", tot.records, tot.first, tot.gap)
	}
	w.Flush()
	fmt.Println()
}

func printTID(byTID map[uint32]*procCount, cache map[uint32]tgidInfo, nrFilter int) {
	type row struct {
		tid uint32
		c   *procCount
	}
	rows := make([]row, 0, len(byTID))
	for tid, c := range byTID {
		rows = append(rows, row{tid, c})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].c.records != rows[j].c.records {
			return rows[i].c.records > rows[j].c.records
		}
		return rows[i].tid < rows[j].tid
	})

	limit := 40
	shown := len(rows)
	if shown > limit {
		shown = limit
	}
	fmt.Printf("so ban ghi theo tid (%d thread, in %d dong dau)\n", len(rows), shown)
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	if nrFilter >= 0 {
		fmt.Fprintf(w, "tid\ttgid\tban_ghi\tnr=%d\t\n", nrFilter)
	} else {
		fmt.Fprintln(w, "tid\ttgid\tban_ghi\t")
	}
	for _, r := range rows[:shown] {
		info := cache[r.tid]
		tgid := strconv.Itoa(info.tgid)
		if info.source == "tid" {
			tgid = "?"
		}
		if nrFilter >= 0 {
			fmt.Fprintf(w, "%d\t%s\t%d\t%d\t\n", r.tid, tgid, r.c.records, r.c.nr)
		} else {
			fmt.Fprintf(w, "%d\t%s\t%d\t\n", r.tid, tgid, r.c.records)
		}
	}
	w.Flush()
	fmt.Println()
}

func printSyscalls(bySyscall map[uint16]int64) {
	type row struct {
		nr uint16
		n  int64
	}
	rows := make([]row, 0, len(bySyscall))
	for nr, n := range bySyscall {
		rows = append(rows, row{nr, n})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].n != rows[j].n {
			return rows[i].n > rows[j].n
		}
		return rows[i].nr < rows[j].nr
	})

	limit := 20
	if len(rows) < limit {
		limit = len(rows)
	}
	fmt.Printf("top %d syscall_nr (tong cong %d gia tri khac nhau)\n", limit, len(rows))
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "syscall_nr\tban_ghi\t")
	for _, r := range rows[:limit] {
		fmt.Fprintf(w, "%d\t%d\t\n", r.nr, r.n)
	}
	w.Flush()
	fmt.Println()
}

// seqAnalysis la ket qua phan tich day seq cua mot CPU.
type seqAnalysis struct {
	records  int64
	min      uint32
	max      uint32
	holes    int64  // so doan lien tuc bi thieu
	missing  uint64 // tong so seq bi thieu
	dup      int64  // so seq xuat hien hon mot lan
	wrapped  bool   // day seq da quay vong qua 2^32
	seqLast  uint32 // seq cuoi cung doc tu .stats
	hasStats bool
	drops    uint64
}

// analyzeSeq sap xep day seq cua mot CPU va dem lo hong. Day seq la mot day
// tang dan modulo 2^32, nen sau khi sap xep tang dan theo gia tri uint32 ta tim
// khoang trong lon nhat tren vong tron va xoay day bat dau tu sau khoang do.
// Khi khong co quay vong, khoang trong lon nhat chinh la doan tu max ve min,
// nen phep xoay khong doi gi.
func analyzeSeq(seqs []uint32) seqAnalysis {
	var a seqAnalysis
	a.records = int64(len(seqs))
	if len(seqs) == 0 {
		return a
	}

	slices.Sort(seqs)
	if len(seqs) == 1 {
		a.min, a.max = seqs[0], seqs[0]
		return a
	}

	// Tim khoang trong lon nhat tren vong tron, ke ca doan noi phan tu cuoi
	// voi phan tu dau.
	start := 0
	biggest := uint64(seqs[0]) + (1 << 32) - uint64(seqs[len(seqs)-1])
	for i := 0; i+1 < len(seqs); i++ {
		d := uint64(seqs[i+1]) - uint64(seqs[i])
		if d > biggest {
			biggest = d
			start = i + 1
		}
	}
	a.wrapped = start != 0

	a.min = seqs[start]
	a.max = seqs[(start+len(seqs)-1)%len(seqs)]

	for i := 0; i+1 < len(seqs); i++ {
		cur := seqs[(start+i)%len(seqs)]
		next := seqs[(start+i+1)%len(seqs)]
		d := uint64(next-cur) & 0xffffffff
		switch {
		case d == 0:
			a.dup++
		case d > 1:
			a.holes++
			a.missing += d - 1
		}
	}

	return a
}

// finish them phan thieu o dau day (seq bat dau tu 1) va phan thieu o cuoi day
// (tu seq lon nhat doc duoc den seq cuoi cung kernel ghi nhan).
func (a *seqAnalysis) finish() {
	if a.records == 0 {
		if a.hasStats {
			a.missing = uint64(a.seqLast)
			if a.seqLast > 0 {
				a.holes = 1
			}
		}
		return
	}
	if !a.wrapped && a.min > 1 {
		a.holes++
		a.missing += uint64(a.min) - 1
	}
	if a.hasStats {
		if d := uint64(a.seqLast-a.max) & 0xffffffff; d > 0 {
			a.holes++
			a.missing += d
		}
	}
}

func printCPU(binPath string, seqByCPU map[int][]uint32, total, kept int64) error {
	statsPath := binPath + recfmt.StatsSuffix
	stats, statsErr := recfmt.ReadStats(statsPath)

	byCPU := map[int]*seqAnalysis{}
	for cpu, seqs := range seqByCPU {
		a := analyzeSeq(seqs)
		byCPU[cpu] = &a
	}
	if statsErr == nil {
		for _, c := range stats.PerCPU {
			a, ok := byCPU[c.CPU]
			if !ok {
				if c.SeqLast == 0 && c.Drops == 0 {
					continue
				}
				a = &seqAnalysis{}
				byCPU[c.CPU] = a
			}
			a.hasStats = true
			a.seqLast = c.SeqLast
			a.drops = c.Drops
		}
	}
	for _, a := range byCPU {
		a.finish()
	}

	cpus := make([]int, 0, len(byCPU))
	for cpu := range byCPU {
		cpus = append(cpus, cpu)
	}
	sort.Ints(cpus)

	if statsErr != nil {
		fmt.Printf("khong doc duoc %s: %v\n", statsPath, statsErr)
		fmt.Println("cot seq_cuoi va mat se de trong")
	}
	fmt.Println("theo tung CPU (cpu lay tu bit8..15 cua flags; seq_cuoi va mat lay tu .stats)")
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "cpu\tban_ghi\tseq_min\tseq_max\tlo_hong\tseq_thieu\tseq_cuoi\tmat\t")

	var totRec, totHoles int64
	var totMissing, totDrops, totAttempts uint64
	var anyWrapped, anyDup bool
	for _, cpu := range cpus {
		a := byCPU[cpu]
		seqLast, drops := "-", "-"
		if a.hasStats {
			seqLast = strconv.FormatUint(uint64(a.seqLast), 10)
			drops = strconv.FormatUint(a.drops, 10)
			totAttempts += uint64(a.seqLast)
			totDrops += a.drops
		}
		minS, maxS := "-", "-"
		if a.records > 0 {
			minS = strconv.FormatUint(uint64(a.min), 10)
			maxS = strconv.FormatUint(uint64(a.max), 10)
		}
		mark := ""
		if a.wrapped {
			mark = " (quay vong)"
			anyWrapped = true
		}
		if a.dup > 0 {
			anyDup = true
		}
		fmt.Fprintf(w, "%d\t%d\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n",
			cpu, a.records, minS, maxS, a.holes, a.missing, seqLast, drops, mark)
		totRec += a.records
		totHoles += a.holes
		totMissing += a.missing
	}
	fmt.Fprintf(w, "TONG\t%d\t\t\t%d\t%d\t%d\t%d\t\n", totRec, totHoles, totMissing, totAttempts, totDrops)
	w.Flush()
	fmt.Println()

	fmt.Println("y nghia cac cot:")
	fmt.Println("  ban_ghi   so ban ghi cua CPU do co trong file (tinh tren toan bo file,")
	fmt.Println("            khong phu thuoc -tgid/-nr/-from-mono/-to-mono)")
	fmt.Println("  seq_min   seq nho nhat doc duoc; bang 1 neu khong mat ban ghi nao o dau")
	fmt.Println("  lo_hong   so doan seq lien tuc bi thieu (ke ca doan dau tu 1 den seq_min")
	fmt.Println("            va doan cuoi tu seq_max den seq_cuoi)")
	fmt.Println("  seq_thieu tong so seq bi thieu; so nay doi chieu truc tiep voi cot mat")
	fmt.Println("  seq_cuoi  so lan dinh ghi tren CPU do, doc tu kernel luc collector dung")
	fmt.Println("  mat       bo dem bpf_ringbuf_reserve that bai, doc tu kernel")
	if anyWrapped {
		fmt.Println("  (quay vong) day seq cua CPU do da vuot qua 2^32 va quay lai tu dau")
	}
	if anyDup {
		fmt.Println("  CANH BAO: co seq xuat hien hon mot lan tren cung mot CPU")
	}
	fmt.Println()

	fmt.Println("doi chieu seq (toan cuc)")
	fmt.Printf("  so lan dinh ghi (tong seq_cuoi cua moi CPU): %d\n", totAttempts)
	if statsErr == nil {
		fmt.Printf("  so ban ghi collector doc duoc             : %d\n", stats.Records)
	}
	fmt.Printf("  so ban ghi dem duoc trong file            : %d\n", total)
	if kept != total {
		fmt.Printf("  so ban ghi con lai sau bo loc             : %d\n", kept)
	}
	fmt.Printf("  tong bo dem mat (ring buffer day)         : %d\n", totDrops)
	fmt.Printf("  tong so seq bi thieu theo CPU             : %d\n", totMissing)
	fmt.Printf("  dinh ghi - ban ghi trong file             : %d\n", int64(totAttempts)-total)

	return nil
}
