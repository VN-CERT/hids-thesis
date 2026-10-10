package hostsample

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// ReadSample doc host va cgroup tai thoi diem hien tai.
func ReadSample(cgroups []CgroupTarget) (Sample, error) {
	var ts unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_MONOTONIC, &ts); err != nil {
		return Sample{}, fmt.Errorf("CLOCK_MONOTONIC: %w", err)
	}
	mono := uint64(ts.Sec)*1e9 + uint64(ts.Nsec)

	var wt unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_REALTIME, &wt); err != nil {
		return Sample{}, fmt.Errorf("CLOCK_REALTIME: %w", err)
	}
	wall := time.Unix(wt.Sec, int64(wt.Nsec)).UTC()

	s := Sample{MonoNs: mono, Wall: wall}
	if err := readCPUStat(&s); err != nil {
		return s, err
	}
	if err := readLoad1(&s); err != nil {
		return s, err
	}
	s.PressCPU = readPressureSome("/proc/pressure/cpu")
	s.PressMem = readPressureSome("/proc/pressure/memory")
	s.PressIO = readPressureSome("/proc/pressure/io")

	for _, cg := range cgroups {
		cs, err := readCgroup(cg.Path)
		if err != nil {
			return s, fmt.Errorf("cgroup %s: %w", cg.Path, err)
		}
		s.Cgroups = append(s.Cgroups, cs)
	}
	return s, nil
}

func readCPUStat(s *Sample) error {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "cpu ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 9 {
			return fmt.Errorf("dong cpu trong /proc/stat qua ngan: %q", line)
		}
		parse := func(i int) (uint64, error) {
			return strconv.ParseUint(fields[i], 10, 64)
		}
		var e error
		if s.CPUUser, e = parse(1); e != nil {
			return e
		}
		if s.CPUNice, e = parse(2); e != nil {
			return e
		}
		if s.CPUSys, e = parse(3); e != nil {
			return e
		}
		if s.CPUIdle, e = parse(4); e != nil {
			return e
		}
		if s.CPUIOWait, e = parse(5); e != nil {
			return e
		}
		if s.CPUIrq, e = parse(6); e != nil {
			return e
		}
		if s.CPUSoft, e = parse(7); e != nil {
			return e
		}
		if s.CPUSteal, e = parse(8); e != nil {
			return e
		}
		return nil
	}
	return fmt.Errorf("khong tim thay dong cpu trong /proc/stat")
}

func readLoad1(s *Sample) error {
	raw, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return err
	}
	fields := strings.Fields(string(raw))
	if len(fields) < 1 {
		return fmt.Errorf("/proc/loadavg rong")
	}
	s.Load1 = fields[0]
	return nil
}

func readPressureSome(path string) PressureSome {
	raw, err := os.ReadFile(path)
	if err != nil {
		return PressureSome{Avg10: "na", Total: "na", Present: false}
	}
	for _, line := range strings.Split(string(raw), "\n") {
		if !strings.HasPrefix(line, "some ") {
			continue
		}
		p := PressureSome{Present: true, Avg10: "na", Total: "na"}
		for _, tok := range strings.Fields(line[5:]) {
			key, val, ok := strings.Cut(tok, "=")
			if !ok {
				continue
			}
			switch key {
			case "avg10":
				p.Avg10 = val
			case "total":
				p.Total = val
			}
		}
		return p
	}
	return PressureSome{Avg10: "na", Total: "na", Present: false}
}

func readCgroup(path string) (CgroupSample, error) {
	cs := CgroupSample{Path: path}
	cs.UsageUsec = readKeyFile(filepath.Join(path, "cpu.stat"), "usage_usec")
	cs.NrPeriods = readKeyFile(filepath.Join(path, "cpu.stat"), "nr_periods")
	cs.NrThrottled = readKeyFile(filepath.Join(path, "cpu.stat"), "nr_throttled")
	cs.ThrottledUsec = readKeyFile(filepath.Join(path, "cpu.stat"), "throttled_usec")
	cs.MemoryCurrent = readSingleFile(filepath.Join(path, "memory.current"))
	cs.CPUPressTotal = readPressureTotal(filepath.Join(path, "cpu.pressure"))
	cs.MemPressureTot = readPressureTotal(filepath.Join(path, "memory.pressure"))
	return cs, nil
}

func readKeyFile(path, key string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "na"
	}
	prefix := key + " "
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix))
		}
	}
	return "na"
}

func readSingleFile(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "na"
	}
	return strings.TrimSpace(string(raw))
}

func readPressureTotal(path string) string {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "na"
	}
	for _, line := range strings.Split(string(raw), "\n") {
		if !strings.HasPrefix(line, "some ") {
			continue
		}
		for _, tok := range strings.Fields(line[5:]) {
			key, val, ok := strings.Cut(tok, "=")
			if ok && key == "total" {
				return val
			}
		}
	}
	return "na"
}

func sanitizeCol(path string) string {
	base := filepath.Base(strings.TrimSuffix(path, "/"))
	if base == "" || base == "." {
		base = "cgroup"
	}
	var b strings.Builder
	for _, r := range base {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
			b.WriteRune(r)
		default:
			b.WriteRune('_')
		}
	}
	return b.String()
}

// CgroupID tra inode cgroup v2.
func CgroupID(path string) (uint64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, err
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, fmt.Errorf("khong lay duoc inode cua %s", path)
	}
	return st.Ino, nil
}
