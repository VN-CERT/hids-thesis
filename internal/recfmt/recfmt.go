// Package recfmt dinh nghia dinh dang file .bin do hids-collect ghi ra:
// phan dau la cac dong van ban bat dau bang '#', ket thuc bang dong "#END",
// sau do la cac ban ghi nhi phan 48 byte noi tiep nhau (little-endian).
package recfmt

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"strings"
)

// RecordSize la kich thuoc co dinh cua mot ban ghi, theo dac ta trong hids.mdc.
const RecordSize = 48

// EndMarker la dong cuoi cua phan header.
const EndMarker = "#END"

// Co trong truong flags, chot trong .cursor/rules/hids.mdc.
const (
	FlagFirst         uint16 = 1 << 0
	FlagGapBefore     uint16 = 1 << 1
	FlagDSleep        uint16 = 1 << 2 // M3
	FlagMigrated      uint16 = 1 << 3 // M3
	FlagOverflow      uint16 = 1 << 4 // M3
	FlagStealFallback uint16 = 1 << 5 // M3
	FlagClamped       uint16 = 1 << 6 // M3
	// bit7 = 0, bit8..15 = so CPU luc sys_enter.
	FlagCPUShift        = 8
	FlagCPUMask  uint16 = 0xff << FlagCPUShift
)

// MaxCPU la so CPU lon nhat ma 8 bit trong flags bieu dien duoc.
const MaxCPU = 256

// Record la mot ban ghi syscall da giai ma.
type Record struct {
	TsEnter   uint64
	CgroupID  uint64
	TID       uint32
	Seq       uint32
	SyscallNr uint16
	Flags     uint16
	CPUNs     uint32
	StealNs   uint32
	IrqNs     uint32
	RqNs      uint32
	VolUs     uint32
}

// CPU tra ve so CPU luc sys_enter, lay tu bit8..15 cua flags.
func (r Record) CPU() int {
	return int(r.Flags&FlagCPUMask) >> FlagCPUShift
}

// Decode doc mot ban ghi tu dung RecordSize byte.
func Decode(b []byte) (Record, error) {
	if len(b) != RecordSize {
		return Record{}, fmt.Errorf("ban ghi dai %d byte, phai %d byte", len(b), RecordSize)
	}
	return Record{
		TsEnter:   binary.LittleEndian.Uint64(b[0:]),
		CgroupID:  binary.LittleEndian.Uint64(b[8:]),
		TID:       binary.LittleEndian.Uint32(b[16:]),
		Seq:       binary.LittleEndian.Uint32(b[20:]),
		SyscallNr: binary.LittleEndian.Uint16(b[24:]),
		Flags:     binary.LittleEndian.Uint16(b[26:]),
		CPUNs:     binary.LittleEndian.Uint32(b[28:]),
		StealNs:   binary.LittleEndian.Uint32(b[32:]),
		IrqNs:     binary.LittleEndian.Uint32(b[36:]),
		RqNs:      binary.LittleEndian.Uint32(b[40:]),
		VolUs:     binary.LittleEndian.Uint32(b[44:]),
	}, nil
}

// Header la phan van ban o dau file.
type Header struct {
	Lines  []string          // nguyen van, khong co dau '#'
	Values map[string]string // cac dong dang "khoa: gia tri"
}

// Get tra ve gia tri cua mot khoa trong header.
func (h Header) Get(key string) string {
	if h.Values == nil {
		return ""
	}
	return h.Values[key]
}

// ReadHeader doc phan header toi dong "#END".
func ReadHeader(r *bufio.Reader) (Header, error) {
	h := Header{Values: map[string]string{}}
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return h, fmt.Errorf("doc header: %w", err)
		}
		line = strings.TrimRight(line, "\n")
		if line == EndMarker {
			return h, nil
		}
		if !strings.HasPrefix(line, "#") {
			return h, fmt.Errorf("header co dong khong bat dau bang '#': %q", line)
		}
		text := strings.TrimSpace(strings.TrimPrefix(line, "#"))
		h.Lines = append(h.Lines, text)
		if key, val, ok := strings.Cut(text, ":"); ok {
			h.Values[strings.TrimSpace(key)] = strings.TrimSpace(val)
		}
	}
}

// ForEach doc het cac ban ghi con lai va goi fn cho tung ban ghi.
// Tra ve so ban ghi doc duoc va so byte thua o cuoi file (neu co).
func ForEach(r io.Reader, fn func(Record) error) (int64, int, error) {
	buf := make([]byte, RecordSize*4096)
	var count int64
	var leftover int

	for {
		n, err := io.ReadFull(r, buf)
		if n == 0 && (err == io.EOF || err == io.ErrUnexpectedEOF) {
			return count, leftover, nil
		}

		full := n / RecordSize * RecordSize
		leftover = n - full
		for off := 0; off < full; off += RecordSize {
			rec, derr := Decode(buf[off : off+RecordSize])
			if derr != nil {
				return count, leftover, derr
			}
			if ferr := fn(rec); ferr != nil {
				return count, leftover, ferr
			}
			count++
		}

		if err == io.EOF || err == io.ErrUnexpectedEOF {
			return count, leftover, nil
		}
		if err != nil {
			return count, leftover, err
		}
	}
}
