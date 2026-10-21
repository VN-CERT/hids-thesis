// Package recfmt dinh nghia dinh dang file .bin do hids-collect ghi ra:
// phan dau la cac dong van ban bat dau bang '#', ket thuc bang dong "#END",
// sau do la cac ban ghi nhi phan 48, 56 hoac 64 byte noi tiep nhau (little-endian).
package recfmt

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// RecordSize la kich thuoc ban ghi moi (M6c), theo dac ta trong hids.mdc.
const RecordSize = 64

// RecordSize56 la kich thuoc ban ghi M6a.
const RecordSize56 = 56

// LegacyRecordSize la kich thuoc ban ghi truoc M6a.
const LegacyRecordSize = 48

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
	FlagPMU           uint16 = 1 << 7 // M6c: inst/cyc hop le cho ca khoang
	// bit8..15 = so CPU luc sys_enter.
	FlagCPUShift        = 8
	FlagCPUMask  uint16 = 0xff << FlagCPUShift
)

// MaxCPU la so CPU lon nhat ma 8 bit trong flags bieu dien duoc.
const MaxCPU = 256

// Record la mot ban ghi syscall da giai ma.
type Record struct {
	TsEnter    uint64
	CgroupID   uint64
	TID        uint32
	Seq        uint32
	SyscallNr  uint16
	Flags      uint16
	CPUNs      uint32
	StealNs    uint32
	IrqNs      uint32
	RqNs       uint32
	VolUs      uint32
	StealOffNs uint32
	Inst       uint32 // M6c: so lenh che do user trong cac doan ON-CPU (chi khi FlagPMU)
	Cyc        uint32 // M6c: so chu ky che do user trong cac doan ON-CPU (chi khi FlagPMU)
	Reserved   uint32
}

// CPU tra ve so CPU luc sys_enter, lay tu bit8..15 cua flags.
func (r Record) CPU() int {
	return int(r.Flags&FlagCPUMask) >> FlagCPUShift
}

// RecordSizeFromHeader tra ve kich thuoc ban ghi tu header; mac dinh 48 neu khong co.
func RecordSizeFromHeader(h Header) (int, error) {
	raw := h.Get("record_size")
	if raw == "" {
		return LegacyRecordSize, nil
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("record_size khong hop le: %q", raw)
	}
	if n != LegacyRecordSize && n != RecordSize56 && n != RecordSize {
		return 0, fmt.Errorf("record_size %d: chi ho tro %d, %d hoac %d", n, LegacyRecordSize, RecordSize56, RecordSize)
	}
	return n, nil
}

// validRecordSize cho biet size co nam trong ba kich thuoc da chot khong.
func validRecordSize(n int) bool {
	return n == LegacyRecordSize || n == RecordSize56 || n == RecordSize
}

// Decode doc mot ban ghi tu dung size byte (48, 56 hoac 64).
func Decode(b []byte) (Record, error) {
	switch len(b) {
	case LegacyRecordSize:
		return decode48(b)
	case RecordSize56:
		return decode56(b)
	case RecordSize:
		return decode64(b)
	default:
		return Record{}, fmt.Errorf("ban ghi dai %d byte, phai %d, %d hoac %d byte", len(b), LegacyRecordSize, RecordSize56, RecordSize)
	}
}

func decode48(b []byte) (Record, error) {
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

func decode56(b []byte) (Record, error) {
	r, err := decode48(b[:LegacyRecordSize])
	if err != nil {
		return r, err
	}
	r.StealOffNs = binary.LittleEndian.Uint32(b[48:52])
	r.Reserved = binary.LittleEndian.Uint32(b[52:56])
	return r, nil
}

func decode64(b []byte) (Record, error) {
	r, err := decode56(b[:RecordSize56])
	if err != nil {
		return r, err
	}
	// Ban 64 byte: inst/cyc the cho cho reserved cua ban 56, them reserved moi.
	r.Inst = binary.LittleEndian.Uint32(b[52:56])
	r.Cyc = binary.LittleEndian.Uint32(b[56:60])
	r.Reserved = binary.LittleEndian.Uint32(b[60:64])
	return r, nil
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
// recordSize phai la LegacyRecordSize, RecordSize56 hoac RecordSize (lay tu header).
// Tra ve so ban ghi doc duoc va so byte thua o cuoi file (neu co).
func ForEach(r io.Reader, recordSize int, fn func(Record) error) (int64, int, error) {
	if !validRecordSize(recordSize) {
		return 0, 0, fmt.Errorf("recordSize %d: chi ho tro %d, %d hoac %d", recordSize, LegacyRecordSize, RecordSize56, RecordSize)
	}
	buf := make([]byte, recordSize*4096)
	var count int64
	var leftover int

	for {
		n, err := io.ReadFull(r, buf)
		if n == 0 && (err == io.EOF || err == io.ErrUnexpectedEOF) {
			return count, leftover, nil
		}

		full := n / recordSize * recordSize
		leftover = n - full
		for off := 0; off < full; off += recordSize {
			rec, derr := Decode(buf[off : off+recordSize])
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
