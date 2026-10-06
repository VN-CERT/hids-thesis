// rec-stat thong ke file .bin do hids-collect ghi ra.
// Cong cu chi in so lieu, khong ket luan dat hay khong.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
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
	byTID := map[uint32]int64{}
	byTGID := map[int]int64{}
	tgidSource := map[int]string{}
	bySyscall := map[uint16]int64{}

	var total, kept, nrCount, firstCount, gapCount int64
	var minTs, maxTs uint64

	_, leftover, err := recfmt.ForEach(br, func(r recfmt.Record) error {
		total++
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
		byTID[r.TID]++
		byTGID[info.tgid]++
		tgidSource[info.tgid] = info.source
		bySyscall[r.SyscallNr]++
		if *nrFilter >= 0 && int(r.SyscallNr) == *nrFilter {
			nrCount++
		}
		if r.Flags&recfmt.FlagFirst != 0 {
			firstCount++
		}
		if r.Flags&recfmt.FlagGapBefore != 0 {
			gapCount++
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

	printTGID(byTGID, tgidSource)
	printTID(byTID, tgidCache)
	printSyscalls(bySyscall)

	return printCPU(path, kept)
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

func printTGID(byTGID map[int]int64, source map[int]string) {
	type row struct {
		tgid int
		n    int64
	}
	rows := make([]row, 0, len(byTGID))
	for tgid, n := range byTGID {
		rows = append(rows, row{tgid, n})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].n != rows[j].n {
			return rows[i].n > rows[j].n
		}
		return rows[i].tgid < rows[j].tgid
	})

	fmt.Printf("so ban ghi theo tgid (%d tien trinh)\n", len(rows))
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "tgid\tban_ghi\tnguon_tgid\t")
	for _, r := range rows {
		src := source[r.tgid]
		if src == "tid" {
			src = "? (suy tu tid)"
		}
		fmt.Fprintf(w, "%d\t%d\t%s\t\n", r.tgid, r.n, src)
	}
	w.Flush()
	fmt.Println()
}

func printTID(byTID map[uint32]int64, cache map[uint32]tgidInfo) {
	type row struct {
		tid uint32
		n   int64
	}
	rows := make([]row, 0, len(byTID))
	for tid, n := range byTID {
		rows = append(rows, row{tid, n})
	}
	sort.Slice(rows, func(i, j int) bool {
		if rows[i].n != rows[j].n {
			return rows[i].n > rows[j].n
		}
		return rows[i].tid < rows[j].tid
	})

	fmt.Printf("so ban ghi theo tid (%d thread)\n", len(rows))
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "tid\ttgid\tban_ghi\t")
	for _, r := range rows {
		info := cache[r.tid]
		tgid := strconv.Itoa(info.tgid)
		if info.source == "tid" {
			tgid = "?"
		}
		fmt.Fprintf(w, "%d\t%s\t%d\t\n", r.tid, tgid, r.n)
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

func printCPU(binPath string, kept int64) error {
	statsPath := binPath + recfmt.StatsSuffix
	stats, err := recfmt.ReadStats(statsPath)
	if err != nil {
		fmt.Printf("khong doc duoc %s: %v\n", statsPath, err)
		fmt.Println("khong co so lieu seq/mat theo CPU")
		return nil
	}

	fmt.Printf("theo tung CPU (lay tu %s)\n", statsPath)
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', tabwriter.AlignRight)
	fmt.Fprintln(w, "cpu\tseq_cuoi\tmat\t")
	for _, c := range stats.PerCPU {
		if c.SeqLast == 0 && c.Drops == 0 {
			continue
		}
		fmt.Fprintf(w, "%d\t%d\t%d\t\n", c.CPU, c.SeqLast, c.Drops)
	}
	fmt.Fprintf(w, "TONG\t%d\t%d\t\n", stats.TotalAttempts(), stats.TotalDrops())
	w.Flush()
	fmt.Println()

	attempts := stats.TotalAttempts()
	drops := stats.TotalDrops()
	fmt.Println("doi chieu seq (toan cuc)")
	fmt.Printf("  so lan dinh ghi (tong seq_cuoi cua moi CPU): %d\n", attempts)
	fmt.Printf("  so ban ghi collector doc duoc             : %d\n", stats.Records)
	fmt.Printf("  so ban ghi dem duoc trong file            : %d\n", kept)
	fmt.Printf("  tong bo dem mat (ring buffer day)         : %d\n", drops)
	fmt.Printf("  dinh ghi - ban ghi doc duoc               : %d\n", int64(attempts)-stats.Records)
	fmt.Println()
	fmt.Println("ghi chu: ban ghi 48 byte khong co truong cpu nen khong tach duoc ban ghi")
	fmt.Println("theo CPU; vi vay khong in duoc seq nho nhat/lon nhat va so lo hong seq cua")
	fmt.Println("tung CPU. Xem muc 8 cua bao cao R002.")

	return nil
}
