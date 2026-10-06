// Package hostinfo doc cac thong tin may can cho phep do: USER_HZ, tan so TSC,
// phien ban kernel, so CPU online. Moi gia tri deu doc tu kernel hoac cong cu
// co san; khong co hang so nao duoc doan.
package hostinfo

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

// atCLKTCK la AT_CLKTCK trong auxiliary vector (include/uapi/linux/auxvec.h).
const atCLKTCK = 17

// KernelRelease tra ve uname -r.
func KernelRelease() (string, error) {
	var u unix.Utsname
	if err := unix.Uname(&u); err != nil {
		return "", fmt.Errorf("uname: %w", err)
	}
	return unix.ByteSliceToString(u.Release[:]), nil
}

// UserHZ tra ve USER_HZ (sysconf(_SC_CLK_TCK)). Doc tu auxiliary vector cua
// chinh tien trinh (/proc/self/auxv, AT_CLKTCK); neu khong co thi hoi getconf.
func UserHZ() (uint64, string, error) {
	if hz, err := userHZFromAuxv("/proc/self/auxv"); err == nil {
		return hz, "/proc/self/auxv AT_CLKTCK", nil
	} else if out, gerr := exec.Command("getconf", "CLK_TCK").Output(); gerr == nil {
		hz, perr := strconv.ParseUint(strings.TrimSpace(string(out)), 10, 64)
		if perr == nil && hz > 0 {
			return hz, "getconf CLK_TCK", nil
		}
		return 0, "", fmt.Errorf("doc USER_HZ: auxv loi (%v), getconf tra ve %q", err, strings.TrimSpace(string(out)))
	} else {
		return 0, "", fmt.Errorf("doc USER_HZ: auxv loi (%v), getconf loi (%v)", err, gerr)
	}
}

func userHZFromAuxv(path string) (uint64, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	for off := 0; off+16 <= len(raw); off += 16 {
		key := binary.LittleEndian.Uint64(raw[off:])
		val := binary.LittleEndian.Uint64(raw[off+8:])
		if key == atCLKTCK {
			if val == 0 {
				return 0, fmt.Errorf("AT_CLKTCK = 0")
			}
			return val, nil
		}
	}
	return 0, fmt.Errorf("khong co AT_CLKTCK trong %s", path)
}

var tscLineRe = regexp.MustCompile(`TSC freq read from hypervisor\s*:\s*([0-9]+)(?:\.([0-9]+))?\s*MHz`)

// TSCInfo mo ta tan so TSC lay tu kernel log.
type TSCInfo struct {
	KHz    uint64 // tan so TSC, kHz
	Source string // lenh da dung
	Line   string // dong log nguyen van
}

// TSCKHz tim dong kernel log "TSC freq read from hypervisor : X MHz" bang dmesg,
// neu khong duoc thi journalctl -k -b. Khong tim thay thi bao loi, khong doan.
func TSCKHz() (TSCInfo, error) {
	type source struct {
		name string
		args []string
	}
	sources := []source{
		{"dmesg", []string{"dmesg"}},
		{"journalctl -k -b", []string{"journalctl", "-k", "-b", "--no-pager"}},
	}

	var problems []string
	for _, s := range sources {
		out, err := exec.Command(s.args[0], s.args[1:]...).Output()
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", s.name, err))
			continue
		}
		line, khz, ok := parseTSCKHz(out)
		if !ok {
			problems = append(problems, fmt.Sprintf("%s: khong co dong \"TSC freq read from hypervisor\"", s.name))
			continue
		}
		return TSCInfo{KHz: khz, Source: s.name, Line: line}, nil
	}

	return TSCInfo{}, fmt.Errorf("khong lay duoc tan so TSC tu kernel log (%s)", strings.Join(problems, "; "))
}

// parseTSCKHz lay dong khop cuoi cung va doi MHz thap phan sang kHz nguyen,
// khong qua so thuc de tranh sai so lam tron.
func parseTSCKHz(out []byte) (string, uint64, bool) {
	var line string
	var khz uint64
	found := false

	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		m := tscLineRe.FindStringSubmatch(sc.Text())
		if m == nil {
			continue
		}
		whole, err := strconv.ParseUint(m[1], 10, 64)
		if err != nil {
			continue
		}
		frac := m[2]
		if len(frac) > 3 {
			frac = frac[:3] // kHz chi can 3 chu so thap phan cua MHz
		}
		for len(frac) < 3 {
			frac += "0"
		}
		fracVal, err := strconv.ParseUint(frac, 10, 64)
		if err != nil {
			continue
		}
		line = strings.TrimSpace(sc.Text())
		khz = whole*1000 + fracVal
		found = true
	}

	return line, khz, found
}

// PreemptMode doc /sys/kernel/debug/sched/preempt. File nay liet ke cac che do
// va dat che do dang dung trong ngoac, vi du "none (voluntary) full".
func PreemptMode() (string, error) {
	raw, err := os.ReadFile("/sys/kernel/debug/sched/preempt")
	if err != nil {
		return "", fmt.Errorf("doc /sys/kernel/debug/sched/preempt: %w", err)
	}
	text := strings.TrimSpace(string(raw))
	for _, f := range strings.Fields(text) {
		if strings.HasPrefix(f, "(") && strings.HasSuffix(f, ")") {
			return fmt.Sprintf("%s (nguyen van: %q)", strings.Trim(f, "()"), text), nil
		}
	}
	return fmt.Sprintf("khong xac dinh (nguyen van: %q)", text), nil
}

// ConfigHZ doc CONFIG_HZ tu /boot/config-<uname -r>.
func ConfigHZ() (int, error) {
	release, err := KernelRelease()
	if err != nil {
		return 0, err
	}
	path := "/boot/config-" + release
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, fmt.Errorf("doc %s: %w", path, err)
	}
	for _, line := range strings.Split(string(raw), "\n") {
		rest, ok := strings.CutPrefix(line, "CONFIG_HZ=")
		if !ok {
			continue
		}
		n, err := strconv.Atoi(strings.TrimSpace(rest))
		if err != nil {
			return 0, fmt.Errorf("doc %s: CONFIG_HZ=%q khong hop le", path, rest)
		}
		return n, nil
	}
	return 0, fmt.Errorf("doc %s: khong co dong CONFIG_HZ=", path)
}

// SchedSchedstats doc kernel.sched_schedstats.
func SchedSchedstats() (int, error) {
	raw, err := os.ReadFile("/proc/sys/kernel/sched_schedstats")
	if err != nil {
		return 0, fmt.Errorf("doc /proc/sys/kernel/sched_schedstats: %w", err)
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(raw)))
	if err != nil {
		return 0, fmt.Errorf("doc kernel.sched_schedstats: gia tri %q khong hop le", strings.TrimSpace(string(raw)))
	}
	return n, nil
}

// OnlineCPUs tra ve so CPU online, tinh bang chi so lon nhat trong
// /sys/devices/system/cpu/online cong mot.
func OnlineCPUs() (int, error) {
	return cpuCount("/sys/devices/system/cpu/online")
}

// PossibleCPUs tra ve so CPU possible. Day la so luong ban sao ma kernel cap
// cho map PERCPU, va la can tren cua gia tri bpf_get_smp_processor_id().
func PossibleCPUs() (int, error) {
	return cpuCount("/sys/devices/system/cpu/possible")
}

func cpuCount(path string) (int, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, fmt.Errorf("doc %s: %w", path, err)
	}
	max := -1
	for _, part := range strings.Split(strings.TrimSpace(string(raw)), ",") {
		if part == "" {
			continue
		}
		lo, hi, ok := strings.Cut(part, "-")
		end := lo
		if ok {
			end = hi
		}
		n, err := strconv.Atoi(strings.TrimSpace(end))
		if err != nil {
			return 0, fmt.Errorf("doc %s: gia tri %q khong hop le", path, part)
		}
		if n > max {
			max = n
		}
	}
	if max < 0 {
		return 0, fmt.Errorf("doc %s: khong co CPU nao", path)
	}
	return max + 1, nil
}
