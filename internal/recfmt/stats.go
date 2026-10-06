package recfmt

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

// StatsSuffix la duoi file thong ke di kem file .bin.
const StatsSuffix = ".stats"

// CPUStat la so lieu cua mot CPU lay tu kernel luc collector ket thuc.
type CPUStat struct {
	CPU     int
	SeqLast uint32 // so lan dinh ghi tren CPU nay (seq cuoi cung)
	Drops   uint64 // so lan bpf_ringbuf_reserve that bai
}

// Stats la noi dung file .bin.stats.
type Stats struct {
	Lines   []string // cac dong comment nguyen van
	Records int64    // so ban ghi collector doc duoc tu ring buffer
	PerCPU  []CPUStat
}

// TotalAttempts tra ve tong so lan dinh ghi tren moi CPU.
func (s Stats) TotalAttempts() uint64 {
	var n uint64
	for _, c := range s.PerCPU {
		n += uint64(c.SeqLast)
	}
	return n
}

// TotalDrops tra ve tong so ban ghi mat.
func (s Stats) TotalDrops() uint64 {
	var n uint64
	for _, c := range s.PerCPU {
		n += c.Drops
	}
	return n
}

var statsColumns = []string{"cpu", "seq_cuoi", "mat"}

// WriteStats ghi file thong ke dang van ban.
func WriteStats(path string, comments []string, records int64, perCPU []CPUStat) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	bw := bufio.NewWriter(f)
	for _, line := range comments {
		fmt.Fprintf(bw, "# %s\n", line)
	}
	fmt.Fprintf(bw, "# so_ban_ghi_doc_duoc: %d\n", records)
	fmt.Fprintf(bw, "%s\n", strings.Join(statsColumns, ","))
	for _, c := range perCPU {
		fmt.Fprintf(bw, "%d,%d,%d\n", c.CPU, c.SeqLast, c.Drops)
	}
	if err := bw.Flush(); err != nil {
		return err
	}
	return f.Close()
}

// ReadStats doc file thong ke.
func ReadStats(path string) (Stats, error) {
	f, err := os.Open(path)
	if err != nil {
		return Stats{}, err
	}
	defer f.Close()

	var s Stats
	br := bufio.NewReader(f)
	for {
		peek, err := br.Peek(1)
		if err != nil || peek[0] != '#' {
			break
		}
		line, err := br.ReadString('\n')
		if err != nil && line == "" {
			break
		}
		text := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "#"))
		s.Lines = append(s.Lines, text)
		if key, val, ok := strings.Cut(text, ":"); ok && strings.TrimSpace(key) == "so_ban_ghi_doc_duoc" {
			s.Records, _ = strconv.ParseInt(strings.TrimSpace(val), 10, 64)
		}
	}

	cr := csv.NewReader(br)
	cr.FieldsPerRecord = len(statsColumns)
	header, err := cr.Read()
	if err != nil {
		return s, fmt.Errorf("%s: doc dong tieu de: %w", path, err)
	}
	for i, want := range statsColumns {
		if header[i] != want {
			return s, fmt.Errorf("%s: cot %d la %q, mong doi %q", path, i+1, header[i], want)
		}
	}

	for {
		row, err := cr.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return s, fmt.Errorf("%s: %w", path, err)
		}
		cpu, err := strconv.Atoi(row[0])
		if err != nil {
			return s, fmt.Errorf("%s: cot cpu: %w", path, err)
		}
		seq, err := strconv.ParseUint(row[1], 10, 32)
		if err != nil {
			return s, fmt.Errorf("%s: cot seq_cuoi: %w", path, err)
		}
		drops, err := strconv.ParseUint(row[2], 10, 64)
		if err != nil {
			return s, fmt.Errorf("%s: cot mat: %w", path, err)
		}
		s.PerCPU = append(s.PerCPU, CPUStat{CPU: cpu, SeqLast: uint32(seq), Drops: drops})
	}

	return s, nil
}
