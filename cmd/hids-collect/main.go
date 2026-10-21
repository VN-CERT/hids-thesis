// hids-collect gan hids_sys_enter vao tp_btf/sys_enter, loc theo pid/cgroup va
// ghi cac ban ghi 64 byte ra file .bin. Can chay bang root.
package main

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/cilium/ebpf/ringbuf"
	"github.com/klauspost/compress/zstd"
	"golang.org/x/sys/unix"

	"hids/internal/bpflog"
	"hids/internal/buildinfo"
	"hids/internal/cgroupexpand"
	"hids/internal/hostinfo"
	"hids/internal/recfmt"
	"hids/internal/stealcheck"
	"hids/internal/syscallbpf"
)

const logPath = "out/hids-collect.log"

type stringList []string

func pmuEventsLine(mode string) string {
	if mode == "off" {
		return "pmu_events: khong co (pmu off)"
	}
	return "pmu_events: instructions:u,cycles:u"
}

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
	discard := flag.Bool("discard", false,
		"doc ring buffer nhung khong ghi ban ghi ra file (do overhead ghi dia)")
	sysEnterHook := flag.String("sys-enter-hook", syscallbpf.SysEnterHookTracepoint,
		"diem gan sys_enter: tracepoint (mac dinh) hoac fentry (x64_sys_call)")
	zstdLevel := flag.Int("zstd-level", 2,
		"muc nen zstd luong (1-3); 0 = khong nen")
	datadir := flag.String("datadir", "", "thu muc thu thap dai ngay (xoay file, proc/host TSV); de trong = che do cu")
	rotate := flag.Duration("rotate", time.Hour, "chu ky xoay file wall clock khi -datadir duoc dat")
	minFreeGB := flag.Float64("min-free-gb", 50, "ngung ghi .bin khi dung luong trong duoi nguong (GB)")
	noProc := flag.Bool("no-proc", false, "tat luong proc (BPF proc_events) - co thu nghiem M6b-1.1")
	noHost := flag.Bool("no-host", false, "tat luong host stats 1Hz - co thu nghiem M6b-1.1")
	cgroupRefresh := flag.Duration("cgroup-refresh", time.Second, "chu ky quet lai cgroup (mac dinh 1s) - co thu nghiem M6b-1.1")
	rbPoll := flag.Duration("rb-poll", 200*time.Millisecond, "deadline moi lan cho doc ring buffer syscall (mac dinh 200ms; xoay file co the tre toi da bang gia tri nay)")
	pmu := flag.String("pmu", "host", "che do PMU: off|host (mac dinh, production: chi luong host doc tong)|on (thi nghiem: BPF doc theo ban ghi); auto = bi danh cua host")
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
	if *sysEnterHook != syscallbpf.SysEnterHookTracepoint && *sysEnterHook != syscallbpf.SysEnterHookFentry {
		return fmt.Errorf("-sys-enter-hook phai la %q hoac %q, nhan %q",
			syscallbpf.SysEnterHookTracepoint, syscallbpf.SysEnterHookFentry, *sysEnterHook)
	}
	if *zstdLevel < 0 || *zstdLevel > 3 {
		return fmt.Errorf("-zstd-level phai trong 0..3, nhan duoc %d", *zstdLevel)
	}
	if *rotate <= 0 {
		return fmt.Errorf("-rotate phai > 0")
	}
	if *rbPoll <= 0 {
		return fmt.Errorf("-rb-poll phai > 0")
	}
	if *pmu != "auto" && *pmu != "host" && *pmu != "on" && *pmu != "off" {
		return fmt.Errorf("-pmu phai la off, host, on (hoac auto = host), nhan %q", *pmu)
	}
	if len(cgroupPaths) == 0 && len(tgids) == 0 {
		return fmt.Errorf("can it nhat mot -pid hoac mot -cgroup")
	}
	buildinfo.WarnIfDirty(os.Stderr)

	if *datadir != "" {
		return runLongRun(longRunOpts{
			datadir:       *datadir,
			rotate:        *rotate,
			minFreeGB:     *minFreeGB,
			cgroupPaths:   cgroupPaths,
			tgids:         tgids,
			duration:      *duration,
			ringbufMB:     *ringbufMB,
			allowNoSteal:  *allowNoStealclock,
			stealFallback: *stealFallback,
			discard:       *discard,
			sysEnterHook:  *sysEnterHook,
			zstdLevel:     *zstdLevel,
			noProc:        *noProc,
			noHost:        *noHost,
			cgroupRefresh: *cgroupRefresh,
			rbPoll:        *rbPoll,
			pmu:           *pmu,
		})
	}

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

	stealMode, stealStatus, stealEvidence, err := checkSteal(nrCPUs, tsc.KHz, *allowNoStealclock, *stealFallback)
	if err != nil {
		return err
	}

	cgroupDesc := make([]string, 0, len(cgroupPaths))
	for _, p := range cgroupPaths {
		id, err := cgroupID(p)
		if err != nil {
			return err
		}
		cgroupDesc = append(cgroupDesc, fmt.Sprintf("%s (goc id=%d)", p, id))
	}
	var cgroupIDs []uint64
	if len(cgroupPaths) > 0 {
		cgroupIDs, err = cgroupexpand.DescendantIDs(cgroupPaths)
		if err != nil {
			return err
		}
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
		SysEnterHook:  *sysEnterHook,
		PMU:           *pmu,
	})
	if err != nil {
		bpflog.Report(logPath, "khong nap duoc chuong trinh BPF cua collector", err)
		return fmt.Errorf("nap BPF that bai, chi tiet o %s", logPath)
	}
	defer coll.Close()
	if coll.PMUWarning() != "" {
		fmt.Fprintf(os.Stderr, "CANH BAO: %s\n", coll.PMUWarning())
	}
	pmuState := coll.PMUMode()

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	defer f.Close()

	startMono, err := monotonicNs()
	if err != nil {
		return err
	}
	startWall := time.Now()

	filterTGIDs := "khong co"
	if len(tgids) > 0 {
		filterTGIDs = tgids.String()
	}
	filterPIDFlag := 0
	if len(tgids) > 0 {
		filterPIDFlag = 1
	}
	rbWakeBytes := uint64(ringbufBytes) / 8
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
		fmt.Sprintf("filter_tgids: %s", filterTGIDs),
		fmt.Sprintf("filter_pid: %d", filterPIDFlag),
		fmt.Sprintf("filter_cgroup: %s", filterCgroup),
		fmt.Sprintf("ringbuf_bytes: %d", ringbufBytes),
		fmt.Sprintf("rb_wake_bytes: %d", rbWakeBytes),
		fmt.Sprintf("stealclock: %s", stealStatus),
		fmt.Sprintf("stealclock_evidence: %s", stealEvidence),
		fmt.Sprintf("steal_mode: %s", stealMode),
		fmt.Sprintf("tsc_khz: %d", tsc.KHz),
		fmt.Sprintf("tsc_source: %s | %s", tsc.Source, tsc.Line),
		fmt.Sprintf("preempt: %s", preempt),
		fmt.Sprintf("config_hz: %d", configHZ),
		fmt.Sprintf("kernel.sched_schedstats: %d", schedstats),
	}
	// Bon tuy chon nay quyet dinh gia tri tham chieu nao dung duoc khi doi
	// chieu: khong co IRQ_TIME_ACCOUNTING va PARAVIRT_TIME_ACCOUNTING thi
	// sum_exec_runtime trong schedstat da gom ca irq va steal.
	for _, name := range []string{"IRQ_TIME_ACCOUNTING", "PARAVIRT_TIME_ACCOUNTING", "SCHEDSTATS", "SCHED_INFO"} {
		value, err := hostinfo.KernelConfig(name)
		if err != nil {
			return err
		}
		header = append(header, fmt.Sprintf("CONFIG_%s: %s", name, value))
	}
	header = append(header,
		fmt.Sprintf("irq_tracepoints (%d cap): %s", len(coll.IRQTracepoints()), strings.Join(coll.IRQTracepoints(), " ")),
		fmt.Sprintf("discard: %v", *discard),
		fmt.Sprintf("sys_enter_hook: %s", *sysEnterHook),
		fmt.Sprintf("zstd_level: %d", *zstdLevel),
		fmt.Sprintf("pmu: %s", pmuState),
		pmuEventsLine(pmuState),
		fmt.Sprintf("start_mono_ns: %d", startMono),
		fmt.Sprintf("start_wall: %s", startWall.Format(time.RFC3339Nano)),
		fmt.Sprintf("duration: %s", durationText(*duration)),
	)
	for _, line := range header {
		if _, err := fmt.Fprintf(f, "# %s\n", line); err != nil {
			return err
		}
	}
	if _, err := fmt.Fprintf(f, "%s\n", recfmt.EndMarker); err != nil {
		return err
	}

	var zstdEnc *zstd.Encoder
	var recordOut io.Writer = f
	if *zstdLevel > 0 {
		zstdEnc, err = zstd.NewWriter(f,
			zstd.WithEncoderLevel(zstd.EncoderLevelFromZstd(*zstdLevel)),
			zstd.WithEncoderConcurrency(4))
		if err != nil {
			return fmt.Errorf("tao bo nen zstd: %w", err)
		}
		defer zstdEnc.Close()
		recordOut = zstdEnc
	}
	bw := bufio.NewWriterSize(recordOut, 4*1024*1024)
	var asyncSink *asyncRecordSink
	if *zstdLevel > 0 && !*discard {
		asyncSink = startAsyncRecordSink(bw)
	}

	if *discard {
		fmt.Fprintln(os.Stderr, "che do -discard: doc ring buffer, khong ghi ban ghi nhi phan")
	} else {
		fmt.Fprintf(os.Stderr, "ghi vao %s\n", outPath)
	}
	fmt.Fprintf(os.Stderr, "loc pid: %s | loc cgroup: %s | ring buffer: %d MiB\n", filterTGIDs, filterCgroup, *ringbufMB)
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

	stopCgroupRefresh := make(chan struct{})
	if len(cgroupPaths) > 0 {
		go refreshCgroupFilter(coll, cgroupPaths, stopCgroupRefresh)
	}

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

	readPoll := *rbPoll
	for {
		coll.SetDeadline(time.Now().Add(readPoll))
		err := coll.ReadInto(&rec)
		if err != nil {
			if errors.Is(err, os.ErrDeadlineExceeded) {
				continue
			}
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
		if !*discard {
			if asyncSink != nil {
				if err := asyncSink.enqueue(rec.RawSample); err != nil {
					return err
				}
			} else if _, err := bw.Write(rec.RawSample); err != nil {
				return err
			}
		}
		records++
		sinceFlush++
	}

	if asyncSink != nil {
		if err := asyncSink.close(); err != nil {
			return err
		}
	} else if err := bw.Flush(); err != nil {
		return err
	}

	close(stopCgroupRefresh)
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
		var hard, soft, softRaw, vec, oddNs uint64
		var oddCnt uint32
		active := 0
		for _, c := range irq {
			hard += c.HardNs
			soft += c.SoftExclNs
			softRaw += c.SoftRawNs
			vec += c.VecNs
			oddNs += c.OddNs
			oddCnt += c.OddCnt
			active += c.Active
		}
		fmt.Fprintf(os.Stderr, "irq cong don (ns): hard %d | soft %d | vector %d | tong %d\n", hard, soft, vec, hard+soft+vec)
		fmt.Fprintf(os.Stderr, "soft_raw cong don (ns): %d (ke ca hard/vector long ben trong, de so voi softirqs-bpfcc)\n", softRaw)
		fmt.Fprintf(os.Stderr, "irq bat thuong: %d khoang, %d ns | loai con dang hoat dong: %d\n", oddCnt, oddNs, active)
	} else {
		bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc bo cong don irq luc ket thuc: %v", err))
	}

	if misses, err := coll.RecursionMisses(); err == nil {
		var total uint64
		for _, m := range misses {
			total += m.Misses
		}
		fmt.Fprintf(os.Stderr, "recursion_misses (bpf_prog_info), tong %d tren %d chuong trinh:\n", total, len(misses))
		for _, m := range misses {
			fmt.Fprintf(os.Stderr, "  %-40s %d\n", m.Program, m.Misses)
		}
	} else {
		bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc recursion_misses: %v", err))
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
func checkSteal(nrCPUs int, tscKHz uint64, allowNoStealclock, forceFallback bool) (mode, status, evidence string, err error) {
	sc, err := stealcheck.DetectStealClock(nrCPUs)
	if err != nil {
		return "", "", "", err
	}
	status = sc.Status()
	evidence = sc.Evidence
	fmt.Fprintf(os.Stderr, "stealclock: %s\n", status)
	fmt.Fprintf(os.Stderr, "stealclock_evidence: %s\n", evidence)

	if !sc.OK {
		if !allowNoStealclock {
			return "", "", evidence, fmt.Errorf(
				"khong chung minh duoc stealclock tren %d CPU (%s). "+
					"Khong dung -allow-no-stealclock trong phép do",
				nrCPUs, sc.Source)
		}
		fmt.Fprintf(os.Stderr, "CANH BAO: chay voi -allow-no-stealclock, steal = 0 tren moi ban ghi\n")
		return stealModeOff, status, evidence, nil
	}

	if forceFallback {
		fmt.Fprintf(os.Stderr, "chay voi -steal-fallback: dung rq->prev_steal_time, moi ban ghi mang co STEAL_FALLBACK\n")
		return stealModeFallback, status, evidence, nil
	}

	fmt.Fprintf(os.Stderr, "doi chieu vmw_steal_time voi rq->prev_steal_time trong %s...\n", stealcheck.SettleTime)
	cmp, err := stealcheck.CompareStealPaths(nrCPUs, tscKHz)
	if err != nil {
		return "", "", evidence, fmt.Errorf("khong doi chieu duoc hai duong do steal: %w", err)
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
		return "", "", evidence, errors.New(b.String())
	}

	return stealModeVMW, status, evidence, nil
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
	var prevHard, prevSoft, prevVec, prevSoftRaw uint64
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
		var hard, soft, vec, softRaw uint64
		for _, c := range irq {
			hard += c.HardNs
			soft += c.SoftExclNs
			vec += c.VecNs
			softRaw += c.SoftRawNs
		}
		mono, err := monotonicNs()
		if err != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("khong doc duoc CLOCK_MONOTONIC: %v", err))
			return
		}
		dAttempts := attempts - prevAttempts
		dDrops := drops - prevDrops
		dHard, dSoft, dVec := hard-prevHard, soft-prevSoft, vec-prevVec
		dSoftRaw := softRaw - prevSoftRaw
		prevAttempts, prevDrops = attempts, drops
		prevHard, prevSoft, prevVec, prevSoftRaw = hard, soft, vec, softRaw

		if werr := pw.Write(recfmt.PeriodicSample{
			MonoNs:          mono,
			Wall:            time.Now(),
			AttemptsDelta:   dAttempts,
			DropsDelta:      dDrops,
			AttemptsTotal:   attempts,
			DropsTotal:      drops,
			IrqHardDelta:    dHard,
			IrqSoftDelta:    dSoft,
			IrqVecDelta:     dVec,
			IrqSoftRawDelta: dSoftRaw,
			IrqHardTotal:    hard,
			IrqSoftTotal:    soft,
			IrqVecTotal:     vec,
			IrqSoftRawTotal: softRaw,
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
func refreshCgroupFilter(coll *syscallbpf.Collector, roots []string, stop <-chan struct{}) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ids, err := cgroupexpand.DescendantIDs(roots)
			if err != nil {
				bpflog.Note(os.Stderr, logPath, fmt.Sprintf("quet cgroup con chau: %v", err))
				continue
			}
			if err := coll.ReplaceCgroupFilter(ids); err != nil {
				bpflog.Note(os.Stderr, logPath, fmt.Sprintf("cap nhat map cgroup: %v", err))
			}
		}
	}
}

// asyncRecordSink: goroutine doc ringbuf chi day vao channel; goroutine khac ghi/nen.
const asyncRecordQueue = 32768

type asyncRecordSink struct {
	ch   chan *[]byte
	done chan error
	pool sync.Pool
}

func startAsyncRecordSink(bw *bufio.Writer) *asyncRecordSink {
	s := &asyncRecordSink{
		ch:   make(chan *[]byte, asyncRecordQueue),
		done: make(chan error, 1),
	}
	s.pool.New = func() interface{} {
		b := make([]byte, recfmt.RecordSize)
		return &b
	}
	go func() {
		var err error
		for bp := range s.ch {
			if _, err = bw.Write(*bp); err != nil {
				s.pool.Put(bp)
				break
			}
			s.pool.Put(bp)
		}
		if err == nil {
			err = bw.Flush()
		}
		s.done <- err
	}()
	return s
}

func (s *asyncRecordSink) enqueue(sample []byte) error {
	bp := s.pool.Get().(*[]byte)
	copy(*bp, sample)
	s.ch <- bp
	return nil
}

func (s *asyncRecordSink) close() error {
	close(s.ch)
	return <-s.done
}

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
