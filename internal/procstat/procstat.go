// Package procstat doc cot steal cua tung CPU trong /proc/stat.
// Day la gia tri tham chieu do kernel cung cap, khong tinh lai trong du an.
package procstat

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Path la duong dan file tham chieu.
const Path = "/proc/stat"

// stealField la vi tri cot steal tinh tu sau ten cpu:
// user nice system idle iowait irq softirq steal guest guest_nice.
const stealField = 8

// Reader doc /proc/stat nhieu lan ma khong cap phat lai bo dem.
type Reader struct {
	buf   []byte
	steal []uint64
}

// NewReader tao reader cho nrCPUs CPU dau tien.
func NewReader(nrCPUs int) *Reader {
	return &Reader{
		buf:   make([]byte, 0, 8192),
		steal: make([]uint64, nrCPUs),
	}
}

// ReadSteal doc /proc/stat va tra ve so tick steal cua tung CPU, don vi 1/USER_HZ giay.
// Lat cat tra ve dung lai bo dem noi bo.
func (r *Reader) ReadSteal() ([]uint64, error) {
	f, err := os.Open(Path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	r.buf = r.buf[:0]
	tmp := make([]byte, 8192)
	for {
		n, err := f.Read(tmp)
		if n > 0 {
			r.buf = append(r.buf, tmp[:n]...)
		}
		if err != nil {
			break
		}
	}

	for i := range r.steal {
		r.steal[i] = 0
	}

	seen := make([]bool, len(r.steal))
	sc := bufio.NewScanner(bytes.NewReader(r.buf))
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "cpu") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 1+stealField {
			continue
		}
		idxStr := strings.TrimPrefix(fields[0], "cpu")
		if idxStr == "" {
			continue // dong tong "cpu", bo qua
		}
		idx, err := strconv.Atoi(idxStr)
		if err != nil || idx < 0 || idx >= len(r.steal) {
			continue
		}
		v, err := strconv.ParseUint(fields[stealField], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("%s: dong %q: cot steal khong phai so: %w", Path, line, err)
		}
		r.steal[idx] = v
		seen[idx] = true
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("doc %s: %w", Path, err)
	}

	for i, ok := range seen {
		if !ok {
			return nil, fmt.Errorf("%s: khong co dong cpu%d", Path, i)
		}
	}

	return r.steal, nil
}
