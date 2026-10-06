// hids-collect gan hids_sys_enter vao tp_btf/sys_enter, loc theo pid/cgroup va
// ghi cac ban ghi 48 byte ra file .bin. Can chay bang root.
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/cilium/ebpf/ringbuf"
	"golang.org/x/sys/unix"

	"hids/internal/bpflog"
	"hids/internal/buildinfo"
	"hids/internal/hostinfo"
	"hids/internal/recfmt"
	"hids/internal/stealcheck"
	"hids/internal/syscallbpf"
)

const logPath = "out/hids-collect.log"

type stringList []string

func (s *stringList) String() string     { return strings.Join(*s, ",") }
func (s *stringList) Set(v string) error { *s = append(*s, v); return nil }

type uintList []uint32

func (u *uintList) String() string {
	parts := make([]string, len(*u))
	for i, v := range *u {
		parts[i] = strconv.FormatUint(uint64(v), 10)
	}
	return strings.Join(parts, ",")
}

func (u *uintList) Set(v string) error {
	n, err := strconv.ParseUint(v, 10, 32)
	if err != nil {
		return err
	}
	*u = append(*u, uint32(n))
	return nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "hids-collect: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	var cgroupPaths stringList
	var tgids uintList
	flag.Var(&cgroupPaths, "cgroup", "thu muc cgroup can theo doi, lap lai duoc")
	flag.Var(&tgids, "pid", "tgid can theo doi, lap lai duoc")
	duration := flag.Duration("duration", 0, "thoi gian thu thap, 0 = den khi nhan SIGINT/SIGTERM")
	out := flag.String("out", "", "file .bin ket qua, de trong thi tu dat ten out/hids-<YYYYmmdd-HHMMSS>.bin")
	ringbufMB := flag.Int("ringbuf-mb", syscallbpf.DefaultRingbufMB, "kich thuoc ring buffer tinh bang MiB, phai la luy thua cua 2")
	allowNoStealclock := flag.Bool("allow-no-stealclock", false,
		"chay tiep khi so dong \"vmware-stealtime\" trong kernel log khac so CPU; khi do steal = 0")
	stealFallback := flag.Bool("steal-fallback", false,
		"dung rq->prev_steal_time thay cho vmw_steal_time; moi ban ghi mang co STEAL_FALLBACK")
	flag.Parse()

	if os.Geteuid() != 0 {
		return fmt.Errorf("can chay bang root (nap chuong trinh BPF)")
	}
	if *duration < 0 {
		return fmt.Errorf("-duration khong duoc am")
	}
	if *ringbufMB <= 0 || *ringbufMB&(*ringbufMB-1) != 0 {
		return fmt.Errorf("-ringbuf-mb phai la luy thua cua 2, nhan duoc %d", *ringbufMB)
	}
	if len(cgroupPaths) == 0 && len(tgids) == 0 {
		return fmt.Errorf("can it nhat mot -pid hoac mot -cgroup")
	}
	buildinfo.WarnIfDirty(os.Stderr)

	release, err := hostinfo.KernelRelease()
	if err != nil {
		return err
	}
	nrCPUs, err := hostinfo.OnlineCPUs()
	if err != nil {
		return err
	}
	possibleCPUs, err := hostinfo.PossibleCPUs()
	if err != nil {
		return err
	}
	// So CPU nam o bit8..15 cua flags nen chi bieu dien duoc 0..255.
	if possibleCPUs > recfmt.MaxCPU {
		return fmt.Errorf("may co %d CPU possible, vuot qua %d: truong flags chi danh 8 bit cho so CPU, "+
			"khong ghi duoc dung. Can kien truc su doi dac ta ban ghi truoc khi chay tren may nay",
			possibleCPUs, recfmt.MaxCPU)
	}

	preempt, err := hostinfo.PreemptMode()
	if err != nil {
		return err
	}
	configHZ, err := hostinfo.ConfigHZ()
	if err != nil {
		return err
	}
	schedstats, err := hostinfo.SchedSchedstats()
	if err != nil {
		return err
	}
	tsc, err := hostinfo.TSCKHz()
	if err != nil {
		return err
	}

	stealMode, stealStatus, err := checkSteal(nrCPUs, tsc.KHz, *allowNoStealclock, *stealFallback)
	if err != nil {
		return err
	}

	cgroupIDs := make([]uint64, 0, len(cgroupPaths))
	cgroupDesc := make([]string, 0, len(cgroupPaths))
	for _, p := range cgroupPaths {
		id, err := cgroupID(p)
		if err != nil {
			return err
		}
		cgroupIDs = append(cgroupIDs, id)
		cgroupDesc = append(cgroupDesc, fmt.Sprintf("%s (id=%d)", p, id))
	}

	outPath := *out
	if outPath == "" {
		outPath = filepath.Join("out", fmt.Sprintf("hids-%s.bin", time.Now().Format("20060102-150405")))
	}
	if dir := filepath.Dir(outPath); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}

	ringbufBytes := uint32(*ringbufMB) * 1024 * 1024
	coll, err := syscallbpf.Load(syscallbpf.Config{
		SelfTGID:      uint32(os.Getpid()),
		TGIDs:         tgids,
		CgroupIDs:     cgroupIDs,
		RingbufBytes:  ringbufBytes,
		TSCKHz:        tsc.KHz,
		StealFallback: stealMode == stealModeFallback,
		StealOff:      stealMode == stealModeOff,
	})
	if err != nil {
		bpflog.Report(logPath, "khong nap duoc chuong trinh BPF cua collector", err)
		return fmt.Errorf("nap BPF that bai, chi tiet o %s", logPath)
	}
	defer coll.Close()

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	defer f.Close()
	bw := bufio.NewWriterSize(f, 4*1024*1024)

	startMono, err := monotonicNs()
	if err != nil {
		return err
	}
	startWall := time.Now()

	filterPID := "khong co"
	if len(tgids) > 0 {
		filterPID = tgids.String()
	}
	filterCgroup := "khong co"
	if len(cgroupDesc) > 0 {
		filterCgroup = strings.Join(cgroupDesc, " | ")
	}

	header := []string{
		"hids-collect",
		fmt.Sprintf("uname_r: %s", release),
		fmt.Sprintf("nr_cpus: %d", nrCPUs),
		fmt.Sprintf("nr_cpus_possible: %d", possibleCPUs),
		fmt.Sprintf("git_commit: %s", buildinfo.GitCommit()),
		fmt.Sprintf("record_size: %d", recfmt.RecordSize),
		fmt.Sprintf("filter_pid: %s", filterPID),
		fmt.Sprintf("filter_cgroup: %s", filterCgroup),
		fmt.Sprintf("ringbuf_bytes: %d", ringbufBytes),
		fmt.Sprintf("stealclock: %s", stealStatus),
		fmt.Sprintf("steal_mode: %s", stealMode),
		fmt.Sprintf("tsc_khz: %d", tsc.KHz),
		fmt.Sprintf("tsc_source: %s | %s", tsc.Source, tsc.Line),
		fmt.Sprintf("preempt: %s", preempt),
		fmt.Sprintf("config_hz: %d", configHZ),
		fmt.Sprintf("kernel.sched_schedstats: %d", schedstats),
		fmt.Sprintf("irq_tracepoints (%d cap): %s", len(coll.IRQTracepoints()), strings.Join(coll.IRQTracepoints(), " ")),
		fmt.Sprintf("start_mono_ns: %d", startMono),
		fmt.Sprintf("start_wall: %s", startWall.Format(time.RFC3339Nano)),
		fmt.Sprintf("duration: %s", durationText(*duration)),
	}
	for _, line := range header {
		if _, err := fmt.Fprintf(bw, "# %s\n", line); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintf(bw, "%s\n", recfmt.EndMarker); err != nil {
		return err
	}

	fmt.Fprintf(os.Stderr, "ghi vao %s\n", outPath)
	fmt.Fprintf(os.Stderr, "loc pid: %s | loc cgroup: %s | ring buffer: %d MiB\n", filterPID, filterCgroup, *ringbufMB)
	// Tracepoint da gan xong tu luc Load(); tu day moi sys_enter deu duoc dem.
	// Script do dung dong nay de biet khi nao bat dau duoc.
	fmt.Fprintln(os.Stderr, "READY")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	periodicPath := outPath + recfmt.PeriodicSuffix
	pw, err := recfmt.NewPeriodicWriter(periodicPath, header)
	if err != nil {
		return err
	}
	defer pw.Close()
	stopPeriodic := make(chan struct{})
	periodicDone := make(chan struct{})
	go watchLoss(coll, pw, stopPeriodic, periodicDone)

	var timer <-chan time.Time
	if *duration > 0 {
		t := time.NewTimer(*duration)
		defer t.Stop()
		timer = t.C
	}

	go func() {
		select {
		case <-ctx.Done():
		case <-timer:
		}
		// Go khoi tracepoint truoc de khong con ban ghi moi, roi danh thuc vong
		// doc de no doc vet phan con lai trong ring buffer.
		if err := coll.Detach(); err != nil {
			fmt.Fprintf(os.Stderr, "go tracepoint: %v\n", err)
		}
		if err := coll.Flush(); err != nil {
			fmt.Fprintf(os.Stderr, "danh thuc vong doc: %v\n", err)
		}
	}()

	var rec ringbuf.Record
	var records int64
	var shortRecords int64
	var sinceFlush int64

	for {
		err := coll.ReadInto(&rec)
		if err != nil {
			if errors.Is(err, ringbuf.ErrFlushed) {
				// Doc vet cho den khi mot lan flush khong con ban ghi nao.
				if sinceFlush == 0 {
					break
				}
				sinceFlush = 0
				if err := coll.Flush(); err != nil {
					return fmt.Errorf("doc vet ring buffer: %w", err)
				}
				continue
			}
			if errors.Is(err, os.ErrClosed) {
				break
			}
			return fmt.Errorf("doc ring buffer: %w", err)
		}
		if len(rec.RawSample) != recfmt.RecordSize {
			shortRecords++
			continue
		}
		if _, err := bw.Write(rec.RawSample); err != nil {
			return err
		}
		records++
		sinceFlush++
	}

	if err := bw.Flush(); err != nil {
		return err
	}

	close(stopPeriodic)
	<-periodicDone

	stats, err := coll.Stats()
	if err != nil {
		return err
	}
	endMono, err := monotonicNs()
	if err != nil {
		return err
	}

	statsPath := outPath + recfmt.StatsSuffix
	comments := append([]string{}, header...)
	comments = append(comments,
		fmt.Sprintf("end_mono_ns: %d", endMono),
		fmt.Sprintf("end_wall: %s", time.Now().Format(time.RFC3339Nano)),
		fmt.Sprintf("bin: %s", outPath),
		fmt.Sprintf("ban_ghi_sai_kich_thuoc: %d", shortRecords),
	)
	if err := recfmt.WriteStats(statsPath, comments, records, stats); err != nil {
		return err
	}

	var attempts uint64
	var drops uint64
	for _, c := range stats {
		attempts += uint64(c.SeqLast)
		drops += c.Drops
	}
	fmt.Fprintf(os.Stderr, "ban ghi doc duoc: %d | so lan dinh ghi: %d | mat: %d\n", records, attempts, drops)

	if irq, err := coll.IRQStats(); err == nil {
		var hard, soft, vec, oddNs uint64
		var oddCnt, stuck uint32
		for _, c := range irq {
			hard += c.HardNs
			soft += c.SoftNs
			vec += c.VecNs
			oddNs += c.OddNs
			oddCnt += c.OddCnt
			if c.Depth != 0 {
				stuck++
			}
		}
		fmt.Fprintf(os.Stderr, "irq cong don (ns): hard %d | soft %d | vector %d\n", hard, soft, vec)
		fmt.Fprintf(os.Stderr, "irq bat thuong: %d khoang, %d ns | CPU con do sau khac 0: %d\n", oddCnt, oddNs, stuck)
	} else {
		bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc bo cong don irq luc ket thuc: %v", err))
	}

	var ru unix.Rusage
	if err := unix.Getrusage(unix.RUSAGE_SELF, &ru); err == nil {
		fmt.Fprintf(os.Stderr, "thoi gian chay: %.3f s | CPU collector: user %.3f s, sys %.3f s (getrusage RUSAGE_SELF)\n",
			float64(endMono-startMono)/1e9,
			float64(ru.Utime.Sec)+float64(ru.Utime.Usec)/1e6,
			float64(ru.Stime.Sec)+float64(ru.Stime.Usec)/1e6)
	}
	if fi, err := os.Stat(outPath); err == nil {
		fmt.Fprintf(os.Stderr, "kich thuoc file: %d byte\n", fi.Size())
	}
	fmt.Fprintf(os.Stderr, "du lieu: %s | thong ke: %s | theo doi: %s\n", outPath, statsPath, periodicPath)

	return nil
}

// Che do do steal, ghi nguyen van vao header.
const (
	stealModeVMW      = "vmw_steal_time"
	stealModeFallback = "rq->prev_steal_time (-steal-fallback)"
	stealModeOff      = "tat (-allow-no-stealclock)"
)

// checkSteal lam hai kiem tra fail-closed truoc khi thu thap:
//
//  1. so dong "vmware-stealtime" trong kernel log phai bang so CPU;
//  2. trong stealcheck.SettleTime giay dau, muc tang cua vmw_steal_time phai
//     khop voi muc tang cua rq->prev_steal_time tren tung CPU.
//
// Khong dat thi tu choi chay, tru khi nguoi dung ghi ro co de bo qua. Do steal
// sai ma khong bao thi toan bo so lieu nghien cuu khong dung duoc.
func checkSteal(nrCPUs int, tscKHz uint64, allowNoStealclock, forceFallback bool) (mode, status string, err error) {
	sc, err := stealcheck.CountStealClock(nrCPUs)
	if err != nil {
		return "", "", err
	}
	status = sc.Status()
	fmt.Fprintf(os.Stderr, "stealclock: %s\n", status)

	if !sc.OK {
		if !allowNoStealclock {
			return "", "", fmt.Errorf(
				"kernel log co %d dong \"vmware-stealtime\" (nguon: %s) nhung may co %d CPU: "+
					"stealclock khong bat du tren moi CPU nen khong do duoc steal. "+
					"Chay lai voi -allow-no-stealclock de thu thap voi steal = 0",
				sc.Lines, sc.Source, nrCPUs)
		}
		fmt.Fprintf(os.Stderr, "CANH BAO: chay voi -allow-no-stealclock, steal = 0 tren moi ban ghi\n")
		return stealModeOff, status, nil
	}

	if forceFallback {
		fmt.Fprintf(os.Stderr, "chay voi -steal-fallback: dung rq->prev_steal_time, moi ban ghi mang co STEAL_FALLBACK\n")
		return stealModeFallback, status, nil
	}

	fmt.Fprintf(os.Stderr, "doi chieu vmw_steal_time voi rq->prev_steal_time trong %s...\n", stealcheck.SettleTime)
	cmp, err := stealcheck.CompareStealPaths(nrCPUs, tscKHz)
	if err != nil {
		return "", "", fmt.Errorf("khong doi chieu duoc hai duong do steal: %w", err)
	}
	fmt.Fprintf(os.Stderr, "doi chieu xong: lech lon nhat %d ns tren %d CPU, nguong max(%d ns, %.0f%%)\n",
		cmp.MaxDiff, len(cmp.PerCPU), stealcheck.ToleranceNs, stealcheck.ToleranceRel*100)

	if !cmp.OK() {
		var b strings.Builder
		fmt.Fprintf(&b, "vmw_steal_time lech qua nguong so voi rq->prev_steal_time trong %s dau:\n", cmp.Window)
		fmt.Fprintf(&b, "  %4s %14s %14s %12s %12s\n", "cpu", "vmw_ns", "rq_steal_ns", "lech_ns", "nguong_ns")
		for _, c := range cmp.PerCPU {
			if c.OK {
				continue
			}
			fmt.Fprintf(&b, "  %4d %14d %14d %12d %12d\n", c.CPU, c.VmwNs, c.RqNs, c.DiffNs, c.LimitNs)
		}
		fmt.Fprintf(&b, "Chay lai voi -steal-fallback de dung rq->prev_steal_time")
		return "", "", errors.New(b.String())
	}

	return stealModeVMW, status, nil
}

// watchLoss ghi mot dong vao file .periodic sau moi recfmt.PeriodicInterval.
// Khi co ban ghi mat trong khoang vua qua, no in mot dong LOSS ra stderr va
// ghi vao log. Collector KHONG dung thu thap vi mat ban ghi: so ban ghi mat la
// du lieu can giu, khong phai ly do de im lang hay bo cuoc.
func watchLoss(coll *syscallbpf.Collector, pw *recfmt.PeriodicWriter, stop <-chan struct{}, done chan<- struct{}) {
	defer close(done)

	ticker := time.NewTicker(recfmt.PeriodicInterval)
	defer ticker.Stop()

	var prevAttempts, prevDrops uint64
	var prevHard, prevSoft, prevVec uint64
	sample := func() {
		stats, err := coll.Stats()
		if err != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc bo dem tu kernel: %v", err))
			return
		}
		var attempts, drops uint64
		for _, c := range stats {
			attempts += uint64(c.SeqLast)
			drops += c.Drops
		}
		irq, err := coll.IRQStats()
		if err != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc bo cong don irq: %v", err))
			return
		}
		var hard, soft, vec uint64
		for _, c := range irq {
			hard += c.HardNs
			soft += c.SoftNs
			vec += c.VecNs
		}
		mono, err := monotonicNs()
		if err != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc CLOCK_MONOTONIC: %v", err))
			return
		}
		dAttempts := attempts - prevAttempts
		dDrops := drops - prevDrops
		dHard, dSoft, dVec := hard-prevHard, soft-prevSoft, vec-prevVec
		prevAttempts, prevDrops = attempts, drops
		prevHard, prevSoft, prevVec = hard, soft, vec

		if werr := pw.Write(recfmt.PeriodicSample{
			MonoNs:        mono,
			Wall:          time.Now(),
			AttemptsDelta: dAttempts,
			DropsDelta:    dDrops,
			AttemptsTotal: attempts,
			DropsTotal:    drops,
			IrqHardDelta:  dHard,
			IrqSoftDelta:  dSoft,
			IrqVecDelta:   dVec,
			IrqHardTotal:  hard,
			IrqSoftTotal:  soft,
			IrqVecTotal:   vec,
		}); werr != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong ghi duoc file .periodic: %v", werr))
		}

		if dDrops > 0 {
			pct := 0.0
			if dAttempts > 0 {
				pct = float64(dDrops) / float64(dAttempts) * 100
			}
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf(
				"LOSS mono_ns=%d mat=%d dinh_ghi=%d ti_le=%.3f%% mat_tong=%d dinh_ghi_tong=%d (ring buffer day, van thu thap tiep)",
				mono, dDrops, dAttempts, pct, drops, attempts))
		}
	}

	sample() // dong moc, cac delta deu bang 0
	for {
		select {
		case <-stop:
			sample()
			return
		case <-ticker.C:
			sample()
		}
	}
}

// cgroupID tra ve id cgroup v2, chinh la so inode cua thu muc cgroup.
func cgroupID(path string) (uint64, error) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, fmt.Errorf("doc thu muc cgroup %s: %w", path, err)
	}
	if !info.IsDir() {
		return 0, fmt.Errorf("%s khong phai thu muc cgroup", path)
	}
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, fmt.Errorf("khong lay duoc so inode cua %s", path)
	}
	return st.Ino, nil
}

// monotonicNs doc CLOCK_MONOTONIC, cung dong ho voi bpf_ktime_get_ns().
func monotonicNs() (uint64, error) {
	var ts unix.Timespec
	if err := unix.ClockGettime(unix.CLOCK_MONOTONIC, &ts); err != nil {
		return 0, fmt.Errorf("doc CLOCK_MONOTONIC: %w", err)
	}
	return uint64(ts.Sec)*1e9 + uint64(ts.Nsec), nil
}

func durationText(d time.Duration) string {
	if d == 0 {
		return "khong gioi han"
	}
	return d.String()
}
