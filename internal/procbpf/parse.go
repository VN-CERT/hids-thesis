package procbpf

import (
	"encoding/binary"
	"fmt"
)

// Event la mot su kien fork/exec/exit da giai ma tu ring buffer.
type Event struct {
	Ts       uint64
	CgroupID uint64
	Type     uint32
	TGID     uint32
	TID      uint32
	PPID     uint32
	Comm     string
	Filename string
}

// ParseEvent giai ma dung EventSize byte little-endian.
func ParseEvent(raw []byte) (Event, error) {
	if len(raw) != EventSize {
		return Event{}, fmt.Errorf("ban ghi proc dai %d byte, phai %d", len(raw), EventSize)
	}
	ev := Event{
		Ts:       binary.LittleEndian.Uint64(raw[0:8]),
		CgroupID: binary.LittleEndian.Uint64(raw[8:16]),
		Type:     binary.LittleEndian.Uint32(raw[16:20]),
		TGID:     binary.LittleEndian.Uint32(raw[20:24]),
		TID:      binary.LittleEndian.Uint32(raw[24:28]),
		PPID:     binary.LittleEndian.Uint32(raw[28:32]),
		Comm:     cstr(raw[32:48]),
		Filename: cstr(raw[48:176]),
	}
	return ev, nil
}

// TypeName tra ve fork/exec/exit hoac so neu khong biet.
func TypeName(t uint32) string {
	switch t {
	case TypeFork:
		return "fork"
	case TypeExec:
		return "exec"
	case TypeExit:
		return "exit"
	default:
		return fmt.Sprintf("%d", t)
	}
}

func cstr(b []byte) string {
	for i, c := range b {
		if c == 0 {
			return string(b[:i])
		}
	}
	return string(b)
}
