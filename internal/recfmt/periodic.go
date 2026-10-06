package recfmt

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"
)

// PeriodicSuffix la duoi file theo doi dinh ky di kem file .bin.
const PeriodicSuffix = ".periodic"

// PeriodicInterval la khoang giua hai dong trong file .periodic.
const PeriodicInterval = 10 * time.Second

// PeriodicSample la mot dong trong file .periodic.
type PeriodicSample struct {
	MonoNs uint64
	Wall   time.Time

	AttemptsDelta uint64 // so lan dinh ghi trong khoang vua qua
	DropsDelta    uint64 // so ban ghi mat trong khoang vua qua
	AttemptsTotal uint64 // cong don tu luc collector chay
	DropsTotal    uint64

	// Tong thoi gian irq cua moi CPU cong lai, theo tung loai.
	// Bang 0 o M2 vi chua do irq.
	IrqHardDelta uint64
	IrqSoftDelta uint64
	IrqVecDelta  uint64
	IrqHardTotal uint64
	IrqSoftTotal uint64
	IrqVecTotal  uint64
}

var periodicColumns = []string{
	"mono_ns", "wall",
	"dinh_ghi_delta", "mat_delta", "dinh_ghi_tong", "mat_tong",
	"irq_hard_delta_ns", "irq_soft_delta_ns", "irq_vec_delta_ns",
	"irq_hard_tong_ns", "irq_soft_tong_ns", "irq_vec_tong_ns",
}

// PeriodicWriter ghi file .periodic va day xuong dia sau moi dong, de du lieu
// khong mat khi tien trinh bi giet.
type PeriodicWriter struct {
	f  *os.File
	bw *bufio.Writer
}

// NewPeriodicWriter tao file va ghi phan dau.
func NewPeriodicWriter(path string, comments []string) (*PeriodicWriter, error) {
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	bw := bufio.NewWriter(f)
	for _, line := range comments {
		fmt.Fprintf(bw, "# %s\n", line)
	}
	fmt.Fprintf(bw, "# moi dong cach nhau %s\n", PeriodicInterval)
	fmt.Fprintf(bw, "%s\n", strings.Join(periodicColumns, ","))
	if err := bw.Flush(); err != nil {
		f.Close()
		return nil, err
	}
	return &PeriodicWriter{f: f, bw: bw}, nil
}

// Write ghi mot dong.
func (w *PeriodicWriter) Write(s PeriodicSample) error {
	fmt.Fprintf(w.bw, "%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
		s.MonoNs, s.Wall.Format(time.RFC3339Nano),
		s.AttemptsDelta, s.DropsDelta, s.AttemptsTotal, s.DropsTotal,
		s.IrqHardDelta, s.IrqSoftDelta, s.IrqVecDelta,
		s.IrqHardTotal, s.IrqSoftTotal, s.IrqVecTotal)
	return w.bw.Flush()
}

// Close day not phan con lai va dong file.
func (w *PeriodicWriter) Close() error {
	if err := w.bw.Flush(); err != nil {
		w.f.Close()
		return err
	}
	return w.f.Close()
}
