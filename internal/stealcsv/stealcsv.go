// Package stealcsv dinh nghia dinh dang CSV dung chung giua steal-probe va steal-summary.
package stealcsv

import (
	"bufio"
	"encoding/csv"
	"fmt"
	"io"
	"math/bits"
	"os"
	"strconv"
	"strings"
	"time"
)

// Columns la thu tu cot cua phan du lieu.
var Columns = []string{
	"mono_ns",
	"wall",
	"cpu",
	"vmw_raw",
	"vmw_ns",
	"rq_steal_ns",
	"procstat_steal_ticks",
}

// WallLayout la dinh dang thoi gian tuong (ISO 8601, gio may).
const WallLayout = "2006-01-02T15:04:05.000000000-07:00"

// Meta la cac dong comment o dau file.
type Meta struct {
	Values map[string]string
	Lines  []string
}

// Get tra ve gia tri cua mot khoa trong phan comment.
func (m Meta) Get(key string) string {
	if m.Values == nil {
		return ""
	}
	return m.Values[key]
}

// Record la mot dong du lieu: mot CPU tai mot lan chup.
type Record struct {
	MonoNs        uint64
	Wall          time.Time
	CPU           int
	VmwRaw        uint64
	VmwNs         uint64
	RqStealNs     uint64
	ProcstatTicks uint64
	HasVmw        bool
	HasRq         bool
}

// VmwNs doi bo dem vTSC sang nano giay: raw * 1e6 / tsc_khz, tinh 128 bit de khong tran.
func VmwNs(raw, tscKHz uint64) (uint64, error) {
	if tscKHz == 0 {
		return 0, fmt.Errorf("tsc_khz = 0")
	}
	hi, lo := bits.Mul64(raw, 1_000_000)
	if hi >= tscKHz {
		return 0, fmt.Errorf("tran khi doi vmw_raw=%d sang ns voi tsc_khz=%d", raw, tscKHz)
	}
	q, _ := bits.Div64(hi, lo, tscKHz)
	return q, nil
}

// Writer ghi file CSV theo dung dinh dang tren.
type Writer struct {
	f  *os.File
	bw *bufio.Writer
	cw *csv.Writer
}

// Create tao file CSV moi va ghi cac dong comment metaLines (khong co dau #).
func Create(path string, metaLines []string) (*Writer, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	bw := bufio.NewWriterSize(f, 64*1024)
	for _, line := range metaLines {
		if _, err := fmt.Fprintf(bw, "# %s\n", line); err != nil {
			f.Close()
			return nil, err
		}
	}
	cw := csv.NewWriter(bw)
	if err := cw.Write(Columns); err != nil {
		f.Close()
		return nil, err
	}
	return &Writer{f: f, bw: bw, cw: cw}, nil
}

// Write ghi mot dong du lieu.
func (w *Writer) Write(r Record) error {
	vmwRaw, vmwNs := "", ""
	if r.HasVmw {
		vmwRaw = strconv.FormatUint(r.VmwRaw, 10)
		vmwNs = strconv.FormatUint(r.VmwNs, 10)
	}
	rqNs := ""
	if r.HasRq {
		rqNs = strconv.FormatUint(r.RqStealNs, 10)
	}
	return w.cw.Write([]string{
		strconv.FormatUint(r.MonoNs, 10),
		r.Wall.Format(WallLayout),
		strconv.Itoa(r.CPU),
		vmwRaw,
		vmwNs,
		rqNs,
		strconv.FormatUint(r.ProcstatTicks, 10),
	})
}

// Flush day du lieu xuong dia.
func (w *Writer) Flush() error {
	w.cw.Flush()
	if err := w.cw.Error(); err != nil {
		return err
	}
	return w.bw.Flush()
}

// Close day du lieu va dong file.
func (w *Writer) Close() error {
	if err := w.Flush(); err != nil {
		w.f.Close()
		return err
	}
	return w.f.Close()
}

// Read doc toan bo file CSV: phan comment va cac dong du lieu.
func Read(path string) ([]Record, Meta, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, Meta{}, err
	}
	defer f.Close()

	meta := Meta{Values: map[string]string{}}
	br := bufio.NewReaderSize(f, 64*1024)
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
		meta.Lines = append(meta.Lines, text)
		if key, val, ok := strings.Cut(text, ":"); ok {
			meta.Values[strings.TrimSpace(key)] = strings.TrimSpace(val)
		}
	}

	cr := csv.NewReader(br)
	cr.FieldsPerRecord = len(Columns)
	header, err := cr.Read()
	if err != nil {
		return nil, meta, fmt.Errorf("%s: doc dong tieu de: %w", path, err)
	}
	for i, want := range Columns {
		if header[i] != want {
			return nil, meta, fmt.Errorf("%s: cot %d la %q, mong doi %q", path, i+1, header[i], want)
		}
	}

	var recs []Record
	line := len(meta.Lines) + 1
	for {
		row, err := cr.Read()
		if err == io.EOF {
			break
		}
		line++
		if err != nil {
			return nil, meta, fmt.Errorf("%s: dong %d: %w", path, line, err)
		}
		rec, err := parseRow(row)
		if err != nil {
			return nil, meta, fmt.Errorf("%s: dong %d: %w", path, line, err)
		}
		recs = append(recs, rec)
	}

	return recs, meta, nil
}

func parseRow(row []string) (Record, error) {
	var r Record
	var err error

	if r.MonoNs, err = strconv.ParseUint(row[0], 10, 64); err != nil {
		return r, fmt.Errorf("mono_ns: %w", err)
	}
	if r.Wall, err = time.Parse(WallLayout, row[1]); err != nil {
		return r, fmt.Errorf("wall: %w", err)
	}
	if r.CPU, err = strconv.Atoi(row[2]); err != nil {
		return r, fmt.Errorf("cpu: %w", err)
	}
	if row[3] != "" {
		if r.VmwRaw, err = strconv.ParseUint(row[3], 10, 64); err != nil {
			return r, fmt.Errorf("vmw_raw: %w", err)
		}
		if r.VmwNs, err = strconv.ParseUint(row[4], 10, 64); err != nil {
			return r, fmt.Errorf("vmw_ns: %w", err)
		}
		r.HasVmw = true
	}
	if row[5] != "" {
		if r.RqStealNs, err = strconv.ParseUint(row[5], 10, 64); err != nil {
			return r, fmt.Errorf("rq_steal_ns: %w", err)
		}
		r.HasRq = true
	}
	if r.ProcstatTicks, err = strconv.ParseUint(row[6], 10, 64); err != nil {
		return r, fmt.Errorf("procstat_steal_ticks: %w", err)
	}

	return r, nil
}
