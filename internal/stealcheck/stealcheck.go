// Package stealcheck kiem tra duong do steal truoc khi collector bat dau thu
// thap. Hong duong do steal thi so lieu sai ma khong bao, nen cac kiem tra o
// day la fail-closed: khong dat thi tu choi chay, chi di tiep khi nguoi dung
// ghi ro co de bo qua.
package stealcheck

import (
	"bufio"
	"bytes"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"hids/internal/stealbpf"
	"hids/internal/stealcsv"
)

// SettleTime la thoi gian cho giua hai lan chup khi so vmw_ns voi
// rq->prev_steal_time.
const SettleTime = 3 * time.Second

// Nguong lech cho phep giua hai duong do steal.
const (
	ToleranceNs  = 2_000_000 // 2 ms
	ToleranceRel = 0.01      // 1%
)

// StealClock la ket qua kiem stealclock (journal hoac chung minh runtime).
type StealClock struct {
	Lines    int    // so dong vmware-stealtime trong journal (neu co)
	NrCPUs   int    // so CPU mong doi
	Source   string // lenh / phuong phap
	Evidence string // journalctl | vmw_steal_time_snapshot
	OK       bool
}

// Status tra ve mo ta ngan gon de ghi vao header.
func (s StealClock) Status() string {
	if !s.OK {
		return fmt.Sprintf("KHONG DU (evidence=%s, %s)", s.Evidence, s.Source)
	}
	if s.Evidence == "journalctl" {
		return fmt.Sprintf("bat (%d/%d dong \"vmware-stealtime\" trong %s)", s.Lines, s.NrCPUs, s.Source)
	}
	return fmt.Sprintf("bat (%s: %s)", s.Evidence, s.Source)
}

func countVMWStealtimeInJournal() (int, error) {
	args := []string{"journalctl", "-k", "-b", "--no-pager"}
	out, err := exec.Command(args[0], args[1:]...).Output()
	if err != nil {
		return 0, fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}
	n := 0
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		if strings.Contains(sc.Text(), "vmware-stealtime") {
			n++
		}
	}
	return n, nil
}

// ProveVMWStealActive chup vmw_steal_time hai lan cach SettleTime; moi CPU phai
// co muc tang > 0 (chu ky vTSC).
func ProveVMWStealActive(nrCPUs int) error {
	snap, vmwErr, err := stealbpf.Load(false)
	if err != nil {
		return err
	}
	defer snap.Close()
	if !snap.HasVMW() {
		return fmt.Errorf("khong nap vmw_steal_time: %v", vmwErr)
	}
	first, err := snap.Snapshot(nrCPUs)
	if err != nil {
		return err
	}
	start := make([]stealbpf.Slot, len(first))
	copy(start, first)
	time.Sleep(SettleTime)
	end, err := snap.Snapshot(nrCPUs)
	if err != nil {
		return err
	}
	for i := 0; i < nrCPUs; i++ {
		if !start[i].HasVMW() || !end[i].HasVMW() {
			return fmt.Errorf("CPU %d: khong doc duoc vmw_steal_time", i)
		}
		if end[i].VmwRaw <= start[i].VmwRaw {
			return fmt.Errorf("CPU %d: vmw_steal_time khong tang trong %s", i, SettleTime)
		}
	}
	return nil
}

// DetectStealClock: journalctl -k -b truoc; neu khong du thi chung minh runtime.
func DetectStealClock(nrCPUs int) (StealClock, error) {
	src := "journalctl -k -b --no-pager"
	n, err := countVMWStealtimeInJournal()
	if err != nil {
		return StealClock{}, err
	}
	if n == nrCPUs {
		return StealClock{
			Lines: n, NrCPUs: nrCPUs, Source: src,
			Evidence: "journalctl", OK: true,
		}, nil
	}
	runtimeSrc := fmt.Sprintf("vmw_steal_time snapshot 2x cach %s", SettleTime)
	if err := ProveVMWStealActive(nrCPUs); err != nil {
		return StealClock{
			Lines: n, NrCPUs: nrCPUs, Source: src + "; " + runtimeSrc,
			Evidence: "none", OK: false,
		}, nil
	}
	return StealClock{
		Lines: n, NrCPUs: nrCPUs, Source: runtimeSrc,
		Evidence: "vmw_steal_time_snapshot", OK: true,
	}, nil
}

// CountStealClock giu ten goi cu; goi DetectStealClock.
func CountStealClock(nrCPUs int) (StealClock, error) {
	return DetectStealClock(nrCPUs)
}

// CPUCompare la ket qua so hai duong do steal tren mot CPU.
type CPUCompare struct {
	CPU     int
	VmwNs   uint64 // muc tang cua vmw_steal_time, quy ra ns
	RqNs    uint64 // muc tang cua rq->prev_steal_time, ns
	DiffNs  int64  // VmwNs - RqNs
	LimitNs uint64 // nguong cho phep cua CPU nay
	OK      bool
}

// Compare la ket qua so tren moi CPU.
type Compare struct {
	Window   time.Duration
	TSCKHz   uint64
	PerCPU   []CPUCompare
	Bad      []int // cac CPU vuot nguong
	MaxDiff  int64
	Mechanis string // co che doc da dung
}

// OK cho biet moi CPU deu trong nguong.
func (c Compare) OK() bool { return len(c.Bad) == 0 }

// CompareStealPaths chup bo dem steal hai lan cach nhau SettleTime va so muc
// tang cua vmw_steal_time voi muc tang cua rq->prev_steal_time tren tung CPU.
func CompareStealPaths(nrCPUs int, tscKHz uint64) (Compare, error) {
	if tscKHz == 0 {
		return Compare{}, fmt.Errorf("thieu tan so TSC")
	}

	snap, vmwErr, err := stealbpf.Load(false)
	if err != nil {
		return Compare{}, err
	}
	defer snap.Close()
	if !snap.HasVMW() {
		return Compare{}, fmt.Errorf("khong nap duoc duong doc vmw_steal_time: %v", vmwErr)
	}

	first, err := snap.Snapshot(nrCPUs)
	if err != nil {
		return Compare{}, err
	}
	start := make([]stealbpf.Slot, len(first))
	copy(start, first)

	time.Sleep(SettleTime)

	end, err := snap.Snapshot(nrCPUs)
	if err != nil {
		return Compare{}, err
	}

	out := Compare{
		Window:   SettleTime,
		TSCKHz:   tscKHz,
		Mechanis: snap.Mechanism(),
	}
	for i := range end {
		if !start[i].HasVMW() || !end[i].HasVMW() || !start[i].HasRQ() || !end[i].HasRQ() {
			return Compare{}, fmt.Errorf("CPU %d: khong doc duoc ca hai bo dem steal", i)
		}
		vmw, err := stealcsv.VmwNs(end[i].VmwRaw-start[i].VmwRaw, tscKHz)
		if err != nil {
			return Compare{}, fmt.Errorf("CPU %d: %w", i, err)
		}
		rq := end[i].RqStealNs - start[i].RqStealNs

		diff := int64(vmw) - int64(rq)
		limit := uint64(ToleranceNs)
		if rel := uint64(float64(rq) * ToleranceRel); rel > limit {
			limit = rel
		}
		abs := diff
		if abs < 0 {
			abs = -abs
		}
		cc := CPUCompare{
			CPU:     i,
			VmwNs:   vmw,
			RqNs:    rq,
			DiffNs:  diff,
			LimitNs: limit,
			OK:      uint64(abs) <= limit,
		}
		if !cc.OK {
			out.Bad = append(out.Bad, i)
		}
		if abs > out.MaxDiff {
			out.MaxDiff = abs
		}
		out.PerCPU = append(out.PerCPU, cc)
	}

	return out, nil
}
