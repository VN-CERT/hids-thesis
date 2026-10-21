package main

import (
	"bufio"
	"context"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/cilium/ebpf/ringbuf"
	"github.com/klauspost/compress/zstd"
	"golang.org/x/sys/unix"

	"hids/internal/bpflog"
	"hids/internal/buildinfo"
	"hids/internal/cgroupexpand"
	"hids/internal/hostinfo"
	"hids/internal/hostsample"
	"hids/internal/procbpf"
	"hids/internal/recfmt"
	"hids/internal/syscallbpf"
)

type longRunOpts struct {
	datadir       string
	rotate        time.Duration
	minFreeGB     float64
	cgroupPaths   []string
	tgids         []uint32
	duration      time.Duration
	ringbufMB     int
	allowNoSteal  bool
	stealFallback bool
	discard       bool
	sysEnterHook  string
	zstdLevel     int
	// Co thu nghiem chan doan CPU (M6b-1.1); mac dinh giu nguyen hanh vi.
	noProc        bool
	noHost        bool
	cgroupRefresh time.Duration
	// Deadline cho doc ring buffer syscall (M6b-1.2 cau 1.2); mac dinh 200ms.
	rbPoll time.Duration
	// M6c: che do PMU auto|on|off.
	pmu string
}

type tsvZstWriter struct {
	path  string
	f     *os.File
	zenc  *zstd.Encoder
	bw    *bufio.Writer
	wrote int64
}

func newTSVZst(path string, headerCols []string, zlevel int) (*tsvZstWriter, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	f, err := os.Create(path)
	if err != nil {
		return nil, err
	}
	// File ten .tsv.zst luon nen; -zstd-level 0 chi ap dung luong .bin.
	if zlevel < 1 {
		zlevel = 1
	}
	zenc, err := zstd.NewWriter(f, zstd.WithEncoderLevel(zstd.EncoderLevelFromZstd(zlevel)))
	if err != nil {
		f.Close()
		return nil, err
	}
	recordOut := io.Writer(zenc)
	bw := bufio.NewWriter(recordOut)
	w := &tsvZstWriter{path: path, f: f, zenc: zenc, bw: bw}
	if len(headerCols) > 0 {
		if err := w.writeRow(headerCols); err != nil {
			w.close()
			return nil, err
		}
	}
	return w, nil
}

func (w *tsvZstWriter) writeRow(cols []string) error {
	cw := csv.NewWriter(w.bw)
	cw.Comma = '\t'
	if err := cw.Write(cols); err != nil {
		return err
	}
	cw.Flush()
	w.wrote++
	return cw.Error()
}

func (w *tsvZstWriter) flushClose() (int64, error) {
	if w.bw != nil {
		if err := w.bw.Flush(); err != nil {
			return 0, err
		}
	}
	if w.zenc != nil {
		if err := w.zenc.Close(); err != nil {
			return 0, err
		}
	}
	var size int64
	if w.f != nil {
		if err := w.f.Sync(); err != nil {
			return 0, err
		}
		if fi, err := w.f.Stat(); err == nil {
			size = fi.Size()
		}
		if err := w.f.Close(); err != nil {
			return size, err
		}
		w.f = nil
	}
	return size, nil
}

func (w *tsvZstWriter) close() error {
	_, err := w.flushClose()
	return err
}

type segmentWriters struct {
	tag       string
	binPath   string
	binFile   *os.File
	zstdEnc   *zstd.Encoder
	recordOut io.Writer
	bw        *bufio.Writer
	asyncSink *asyncRecordSink
	periodic  *recfmt.PeriodicWriter
	procW     *tsvZstWriter
	hostW     *tsvZstWriter
	binBytes  int64
	procBytes int64
	hostBytes int64
	records   int64
	header    []string
}

type writerSet struct {
	mu       sync.Mutex
	seg      *segmentWriters
	opts     longRunOpts
	hostname string
	hostHdr  []string
	cgroups  []hostsample.CgroupTarget
	statsFn  func() ([]recfmt.CPUStat, error)
	// totalRecords cong don toan phien, khong reset khi xoay file
	// (dung cho records_per_sec trong status.tsv; M6b-1.1 phan B).
	totalRecords int64
}

func periodTag(t time.Time, rotate time.Duration) string {
	start := t.UTC()
	if rotate >= time.Hour {
		start = start.Truncate(time.Hour)
		return start.Format("2006010215")
	}
	start = start.Truncate(rotate)
	return start.Format("200601021504")
}

func (ws *writerSet) openSegment(tag string, baseHeader []string) error {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg != nil {
		if err := ws.closeSegmentLocked(); err != nil {
			return err
		}
	}
	binName := fmt.Sprintf("%s-%s.bin", ws.hostname, tag)
	binPath := filepath.Join(ws.opts.datadir, binName)
	procPath := filepath.Join(ws.opts.datadir, fmt.Sprintf("proc-%s.tsv.zst", tag))
	hostPath := filepath.Join(ws.opts.datadir, fmt.Sprintf("host-%s.tsv.zst", tag))

	f, err := os.Create(binPath)
	if err != nil {
		return err
	}
	header := append([]string{}, baseHeader...)
	header = append(header, fmt.Sprintf("segment_tag: %s", tag))
	for _, line := range header {
		if _, err := fmt.Fprintf(f, "# %s\n", line); err != nil {
			f.Close()
			return err
		}
	}
	if _, err := fmt.Fprintf(f, "%s\n", recfmt.EndMarker); err != nil {
		f.Close()
		return err
	}

	var recordOut io.Writer = f
	var zenc *zstd.Encoder
	if ws.opts.zstdLevel > 0 {
		zenc, err = zstd.NewWriter(f, zstd.WithEncoderLevel(zstd.EncoderLevelFromZstd(ws.opts.zstdLevel)))
		if err != nil {
			f.Close()
			return err
		}
		recordOut = zenc
	}
	bw := bufio.NewWriterSize(recordOut, 4*1024*1024)
	var asyncSink *asyncRecordSink
	if ws.opts.zstdLevel > 0 && !ws.opts.discard {
		asyncSink = startAsyncRecordSink(bw)
	}

	pw, err := recfmt.NewPeriodicWriter(binPath+recfmt.PeriodicSuffix, header)
	if err != nil {
		f.Close()
		return err
	}
	procW, err := newTSVZst(procPath, []string{
		"mono_ns", "type", "tgid", "tid", "ppid", "cgroup_id", "comm", "filename",
	}, ws.opts.zstdLevel)
	if err != nil {
		pw.Close()
		f.Close()
		return err
	}
	hostW, err := newTSVZst(hostPath, ws.hostHdr, ws.opts.zstdLevel)
	if err != nil {
		procW.close()
		pw.Close()
		f.Close()
		return err
	}

	ws.seg = &segmentWriters{
		tag: tag, binPath: binPath, binFile: f, zstdEnc: zenc, recordOut: recordOut,
		bw: bw, asyncSink: asyncSink, periodic: pw, procW: procW, hostW: hostW, header: header,
	}
	fmt.Fprintf(os.Stderr, "mo segment %s -> %s\n", tag, binPath)
	return nil
}

func (ws *writerSet) closeSegmentLocked() error {
	if ws.seg == nil {
		return nil
	}
	seg := ws.seg
	ws.seg = nil
	if ws.statsFn != nil && seg.binPath != "" {
		if stats, err := ws.statsFn(); err == nil {
			_ = recfmt.WriteStats(seg.binPath+recfmt.StatsSuffix, seg.header, seg.records, stats)
		}
	}
	var err error
	if seg.asyncSink != nil {
		err = seg.asyncSink.close()
	} else if seg.bw != nil {
		err = seg.bw.Flush()
	}
	if seg.zstdEnc != nil {
		if e := seg.zstdEnc.Close(); e != nil && err == nil {
			err = e
		}
	}
	if seg.binFile != nil {
		if e := seg.binFile.Sync(); e != nil && err == nil {
			err = e
		}
		if fi, e := seg.binFile.Stat(); e == nil {
			seg.binBytes = fi.Size()
		}
		if e := seg.binFile.Close(); e != nil && err == nil {
			err = e
		}
	}
	if seg.procW != nil {
		if n, e := seg.procW.flushClose(); e != nil && err == nil {
			err = e
		} else {
			seg.procBytes = n
		}
	}
	if seg.hostW != nil {
		if n, e := seg.hostW.flushClose(); e != nil && err == nil {
			err = e
		} else {
			seg.hostBytes = n
		}
	}
	if seg.periodic != nil {
		if e := seg.periodic.Close(); e != nil && err == nil {
			err = e
		}
	}
	return err
}

func (ws *writerSet) maybeRotate(now time.Time, baseHeader []string) error {
	tag := periodTag(now, ws.opts.rotate)
	ws.mu.Lock()
	need := ws.seg == nil || ws.seg.tag != tag
	ws.mu.Unlock()
	if need {
		return ws.openSegment(tag, baseHeader)
	}
	return nil
}

func (ws *writerSet) writeRecord(raw []byte) error {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg == nil || ws.opts.discard {
		return nil
	}
	var err error
	if ws.seg.asyncSink != nil {
		err = ws.seg.asyncSink.enqueue(raw)
	} else {
		_, err = ws.seg.bw.Write(raw)
	}
	if err == nil {
		ws.seg.records++
		ws.totalRecords++
	}
	return err
}

func (ws *writerSet) writeProcRow(cols []string) error {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg == nil || ws.seg.procW == nil {
		return nil
	}
	return ws.seg.procW.writeRow(cols)
}

func (ws *writerSet) writeHostRow(cols []string) error {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg == nil || ws.seg.hostW == nil {
		return nil
	}
	return ws.seg.hostW.writeRow(cols)
}

func (ws *writerSet) segmentByteTotals() (bin, proc, host int64) {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg == nil {
		return 0, 0, 0
	}
	if ws.seg.binFile != nil {
		if fi, err := ws.seg.binFile.Stat(); err == nil {
			bin = fi.Size()
		}
	}
	if ws.seg.procW != nil && ws.seg.procW.f != nil {
		if fi, err := ws.seg.procW.f.Stat(); err == nil {
			proc = fi.Size()
		}
	}
	if ws.seg.hostW != nil && ws.seg.hostW.f != nil {
		if fi, err := ws.seg.hostW.f.Stat(); err == nil {
			host = fi.Size()
		}
	}
	return bin, proc, host
}

func (ws *writerSet) currentPeriodic() *recfmt.PeriodicWriter {
	ws.mu.Lock()
	defer ws.mu.Unlock()
	if ws.seg == nil {
		return nil
	}
	return ws.seg.periodic
}

func freeGB(dir string) (float64, error) {
	var st unix.Statfs_t
	if err := unix.Statfs(dir, &st); err != nil {
		return 0, err
	}
	free := float64(st.Bavail) * float64(st.Bsize)
	return free / (1024 * 1024 * 1024), nil
}

func runLongRun(o longRunOpts) error {
	if o.rotate <= 0 {
		return fmt.Errorf("-rotate phai > 0")
	}
	if o.cgroupRefresh <= 0 {
		o.cgroupRefresh = time.Second
	}
	if o.rbPoll <= 0 {
		o.rbPoll = 200 * time.Millisecond
	}
	if err := os.MkdirAll(o.datadir, 0o755); err != nil {
		return err
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
	if possibleCPUs > recfmt.MaxCPU {
		return fmt.Errorf("may co %d CPU possible, vuot qua %d", possibleCPUs, recfmt.MaxCPU)
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
	stealMode, stealStatus, stealEvidence, err := checkSteal(nrCPUs, tsc.KHz, o.allowNoSteal, o.stealFallback)
	if err != nil {
		return err
	}

	cgroupDesc := make([]string, 0, len(o.cgroupPaths))
	var cgroupIDs []uint64
	for _, p := range o.cgroupPaths {
		id, err := cgroupID(p)
		if err != nil {
			return err
		}
		cgroupDesc = append(cgroupDesc, fmt.Sprintf("%s (goc id=%d)", p, id))
	}
	if len(o.cgroupPaths) > 0 {
		cgroupIDs, err = cgroupexpand.DescendantIDs(o.cgroupPaths)
		if err != nil {
			return err
		}
	}

	hostname, _ := os.Hostname()
	if hostname == "" {
		hostname = "host"
	}
	cgTargets := make([]hostsample.CgroupTarget, 0, len(o.cgroupPaths))
	for _, p := range o.cgroupPaths {
		id, _ := hostsample.CgroupID(p)
		cgTargets = append(cgTargets, hostsample.CgroupTarget{Path: p, ID: id})
	}

	ringbufBytes := uint32(o.ringbufMB) * 1024 * 1024
	coll, err := syscallbpf.Load(syscallbpf.Config{
		SelfTGID:      uint32(os.Getpid()),
		TGIDs:         o.tgids,
		CgroupIDs:     cgroupIDs,
		RingbufBytes:  ringbufBytes,
		TSCKHz:        tsc.KHz,
		StealFallback: stealMode == stealModeFallback,
		StealOff:      stealMode == stealModeOff,
		SysEnterHook:  o.sysEnterHook,
		PMU:           o.pmu,
	})
	if err != nil {
		bpflog.Report(logPath, "khong nap duoc syscall BPF", err)
		return fmt.Errorf("nap BPF that bai, chi tiet o %s", logPath)
	}
	defer coll.Close()

	var procColl *procbpf.Collector
	if !o.noProc {
		procColl, err = procbpf.Load(procbpf.Config{SelfTGID: uint32(os.Getpid())})
		if err != nil {
			bpflog.Report(logPath, "khong nap duoc proc BPF", err)
			return fmt.Errorf("nap proc BPF that bai, chi tiet o %s", logPath)
		}
		defer procColl.Close()
		if len(cgroupIDs) > 0 {
			if err := procColl.ReplaceCgroupFilter(cgroupIDs); err != nil {
				return err
			}
		}
	}

	startMono, err := monotonicNs()
	if err != nil {
		return err
	}
	startWall := time.Now()

	filterTGIDs := "khong co"
	if len(o.tgids) > 0 {
		parts := make([]string, len(o.tgids))
		for i, v := range o.tgids {
			parts[i] = strconv.FormatUint(uint64(v), 10)
		}
		filterTGIDs = strings.Join(parts, ",")
	}
	filterPIDFlag := 0
	if len(o.tgids) > 0 {
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
		fmt.Sprintf("datadir: %s", o.datadir),
		fmt.Sprintf("rotate: %s", o.rotate),
		fmt.Sprintf("min_free_gb: %.0f", o.minFreeGB),
		fmt.Sprintf("no_proc: %v", o.noProc),
		fmt.Sprintf("no_host: %v", o.noHost),
		fmt.Sprintf("cgroup_refresh: %s", o.cgroupRefresh),
		fmt.Sprintf("rb_poll: %s", o.rbPoll),
	}
	if coll.PMUWarning() != "" {
		fmt.Fprintf(os.Stderr, "CANH BAO: %s\n", coll.PMUWarning())
	}
	pmuState := "off"
	if coll.PMUOn() {
		pmuState = "on"
	}
	header = append(header,
		fmt.Sprintf("pmu: %s", pmuState),
		"pmu_events: instructions:u,cycles:u",
	)
	for _, name := range []string{"IRQ_TIME_ACCOUNTING", "PARAVIRT_TIME_ACCOUNTING", "SCHEDSTATS", "SCHED_INFO"} {
		value, err := hostinfo.KernelConfig(name)
		if err != nil {
			return err
		}
		header = append(header, fmt.Sprintf("CONFIG_%s: %s", name, value))
	}
	header = append(header,
		fmt.Sprintf("irq_tracepoints (%d cap): %s", len(coll.IRQTracepoints()), strings.Join(coll.IRQTracepoints(), " ")),
		fmt.Sprintf("discard: %v", o.discard),
		fmt.Sprintf("sys_enter_hook: %s", o.sysEnterHook),
		fmt.Sprintf("zstd_level: %d", o.zstdLevel),
		fmt.Sprintf("start_mono_ns: %d", startMono),
		fmt.Sprintf("start_wall: %s", startWall.Format(time.RFC3339Nano)),
		fmt.Sprintf("duration: %s", durationText(o.duration)),
	)

	ws := &writerSet{
		opts:     o,
		hostname: hostname,
		hostHdr:  hostsample.HeaderTSV(cgTargets),
		cgroups:  cgTargets,
		statsFn:  coll.Stats,
	}
	if err := ws.openSegment(periodTag(startWall, o.rotate), header); err != nil {
		return err
	}
	defer func() {
		ws.mu.Lock()
		_ = ws.closeSegmentLocked()
		ws.mu.Unlock()
	}()

	fmt.Fprintf(os.Stderr, "longrun datadir=%s rotate=%s min_free_gb=%.0f\n", o.datadir, o.rotate, o.minFreeGB)
	fmt.Fprintf(os.Stderr, "loc pid: %s | loc cgroup: %s | ring buffer: %d MiB\n", filterTGIDs, filterCgroup, o.ringbufMB)
	fmt.Fprintln(os.Stderr, "READY")

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	var diskPaused atomic.Bool
	var diskSkipped atomic.Int64
	minGB := o.minFreeGB

	stopPeriodic := make(chan struct{})
	periodicDone := make(chan struct{})
	go func() {
		defer close(periodicDone)
		ticker := time.NewTicker(recfmt.PeriodicInterval)
		defer ticker.Stop()
		var prevAttempts, prevDrops uint64
		var prevHard, prevSoft, prevVec, prevSoftRaw uint64
		sample := func() {
			pw := ws.currentPeriodic()
			if pw == nil {
				return
			}
			stats, err := coll.Stats()
			if err != nil {
				return
			}
			var attempts, drops uint64
			for _, c := range stats {
				attempts += uint64(c.SeqLast)
				drops += c.Drops
			}
			irq, _ := coll.IRQStats()
			var hard, soft, vec, softRaw uint64
			for _, c := range irq {
				hard += c.HardNs
				soft += c.SoftExclNs
				vec += c.VecNs
				softRaw += c.SoftRawNs
			}
			mono, _ := monotonicNs()
			dAttempts := attempts - prevAttempts
			dDrops := drops - prevDrops
			prevAttempts, prevDrops = attempts, drops
			dHard, dSoft, dVec := hard-prevHard, soft-prevSoft, vec-prevVec
			dSoftRaw := softRaw - prevSoftRaw
			prevHard, prevSoft, prevVec, prevSoftRaw = hard, soft, vec, softRaw
			_ = pw.Write(recfmt.PeriodicSample{
				MonoNs: mono, Wall: time.Now(),
				AttemptsDelta: dAttempts, DropsDelta: dDrops,
				AttemptsTotal: attempts, DropsTotal: drops,
				IrqHardDelta: dHard, IrqSoftDelta: dSoft, IrqVecDelta: dVec, IrqSoftRawDelta: dSoftRaw,
				IrqHardTotal: hard, IrqSoftTotal: soft, IrqVecTotal: vec, IrqSoftRawTotal: softRaw,
			})
			if dDrops > 0 {
				bpflog.Note(os.Stderr, logPath, fmt.Sprintf(
					"LOSS mono_ns=%d mat=%d dinh_ghi=%d mat_tong=%d", mono, dDrops, dAttempts, drops))
			}
		}
		sample()
		for {
			select {
			case <-stopPeriodic:
				sample()
				return
			case <-ticker.C:
				sample()
			}
		}
	}()

	stopDisk := make(chan struct{})
	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stopDisk:
				return
			case <-ticker.C:
				threshold := minGB
				if raw, err := os.ReadFile(filepath.Join(o.datadir, "min_free_gb")); err == nil {
					if v, err := strconv.ParseFloat(strings.TrimSpace(string(raw)), 64); err == nil {
						threshold = v
					}
				}
				free, err := freeGB(o.datadir)
				if err != nil {
					continue
				}
				if diskPaused.Load() {
					if free > threshold+10 {
						diskPaused.Store(false)
						fmt.Fprintln(os.Stderr, "RESUME_DISK")
					}
				} else if free < threshold {
					diskPaused.Store(true)
					fmt.Fprintln(os.Stderr, "PAUSE_DISK")
				}
			}
		}
	}()

	var prevKernelDrops uint64
	var prevProcDrops uint64
	var prevRecords int64
	var prevStatusWall time.Time
	statusPath := filepath.Join(o.datadir, "status.tsv")
	stopStatus := make(chan struct{})
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stopStatus:
				return
			case now := <-ticker.C:
				if prevStatusWall.IsZero() {
					prevStatusWall = now
				}
				if now.Sub(prevStatusWall) < 60*time.Second {
					continue
				}
				elapsed := now.Sub(prevStatusWall).Seconds()
				prevStatusWall = now

				stats, _ := coll.Stats()
				var drops uint64
				for _, c := range stats {
					drops += c.Drops
				}
				kernDelta := drops - prevKernelDrops
				prevKernelDrops = drops

				var procD uint64
				if procColl != nil {
					procD, _ = procColl.Drops()
				}
				procDelta := procD - prevProcDrops
				prevProcDrops = procD

				ws.mu.Lock()
				recs := ws.totalRecords
				ws.mu.Unlock()
				recDelta := recs - prevRecords
				prevRecords = recs
				if recDelta < 0 {
					recDelta = 0
				}
				rps := float64(recDelta) / elapsed

				skipped := diskSkipped.Load()
				binB, procB, hostB := ws.segmentByteTotals()
				_ = procB
				_ = hostB
				free, _ := freeGB(o.datadir)

				var ru unix.Rusage
				rss := int64(0)
				cpuSec := 0.0
				if err := unix.Getrusage(unix.RUSAGE_SELF, &ru); err == nil {
					rss = int64(ru.Maxrss) * 1024
					cpuSec = float64(ru.Utime.Sec) + float64(ru.Utime.Usec)/1e6 +
						float64(ru.Stime.Sec) + float64(ru.Stime.Usec)/1e6
				}

				row := []string{
					now.UTC().Format(time.RFC3339Nano),
					fmt.Sprintf("%.2f", rps),
					strconv.FormatUint(kernDelta, 10),
					strconv.FormatInt(skipped, 10),
					strconv.FormatInt(binB, 10),
					fmt.Sprintf("%.2f", free),
					strconv.FormatInt(rss, 10),
					fmt.Sprintf("%.3f", cpuSec),
					strconv.FormatUint(procDelta, 10),
				}
				writeStatusRow(statusPath, row)
			}
		}
	}()

	stopHost := make(chan struct{})
	if !o.noHost {
		go func() {
			ticker := time.NewTicker(time.Second)
			defer ticker.Stop()
			var prevPMUInst, prevPMUCyc uint64
			if coll.PMUOn() {
				prevPMUInst, prevPMUCyc, _ = coll.PMUTotals()
			}
			for {
				select {
				case <-stopHost:
					return
				case <-ticker.C:
					s, err := hostsample.ReadSample(ws.cgroups)
					if err != nil {
						bpflog.Note(os.Stderr, logPath, fmt.Sprintf("hostsample: %v", err))
						continue
					}
					if coll.PMUOn() {
						inst, cyc, perr := coll.PMUTotals()
						if perr == nil {
							s.PMUInstDelta = strconv.FormatUint(inst-prevPMUInst, 10)
							s.PMUCycDelta = strconv.FormatUint(cyc-prevPMUCyc, 10)
							prevPMUInst, prevPMUCyc = inst, cyc
						}
					}
					_ = ws.maybeRotate(time.Now(), header)
					if err := ws.writeHostRow(s.RowTSV()); err != nil {
						bpflog.Note(os.Stderr, logPath, fmt.Sprintf("ghi host: %v", err))
					}
				}
			}
		}()
	}

	stopCgroup := make(chan struct{})
	if len(o.cgroupPaths) > 0 {
		go refreshCgroupBoth(coll, procColl, o.cgroupPaths, stopCgroup, o.cgroupRefresh)
	}

	var timer <-chan time.Time
	if o.duration > 0 {
		t := time.NewTimer(o.duration)
		defer t.Stop()
		timer = t.C
	}

	go func() {
		select {
		case <-ctx.Done():
		case <-timer:
		}
		_ = coll.Detach()
		if procColl != nil {
			_ = procColl.Detach()
		}
		_ = coll.Flush()
		if procColl != nil {
			_ = procColl.Flush()
		}
	}()

	readPoll := o.rbPoll
	handleProcEvent := func(pr *ringbuf.Record) {
		if len(pr.RawSample) != procbpf.EventSize {
			return
		}
		ev, err := procbpf.ParseEvent(pr.RawSample)
		if err != nil {
			return
		}
		row := []string{
			strconv.FormatUint(ev.Ts, 10),
			procbpf.TypeName(ev.Type),
			strconv.FormatUint(uint64(ev.TGID), 10),
			strconv.FormatUint(uint64(ev.TID), 10),
			strconv.FormatUint(uint64(ev.PPID), 10),
			strconv.FormatUint(ev.CgroupID, 10),
			ev.Comm,
			ev.Filename,
		}
		if err := ws.writeProcRow(row); err != nil {
			bpflog.Note(os.Stderr, logPath, fmt.Sprintf("ghi proc: %v", err))
		}
	}

	errCh := make(chan error, 2)
	var readers sync.WaitGroup
	if procColl != nil {
		readers.Add(2)
	} else {
		readers.Add(1)
	}
	go func() {
		defer readers.Done()
		var rec ringbuf.Record
		var sinceFlush int64
		for {
			if err := ws.maybeRotate(time.Now(), header); err != nil {
				errCh <- err
				return
			}
			coll.SetDeadline(time.Now().Add(readPoll))
			err := coll.ReadInto(&rec)
			if err == nil {
				sinceFlush++
				if len(rec.RawSample) != recfmt.RecordSize {
					continue
				}
				if diskPaused.Load() {
					diskSkipped.Add(1)
					continue
				}
				if werr := ws.writeRecord(rec.RawSample); werr != nil {
					errCh <- werr
					return
				}
				continue
			}
			if errors.Is(err, os.ErrDeadlineExceeded) {
				continue
			}
			if errors.Is(err, ringbuf.ErrFlushed) {
				if sinceFlush == 0 {
					return
				}
				sinceFlush = 0
				if ferr := coll.Flush(); ferr != nil {
					errCh <- fmt.Errorf("doc vet syscall ringbuf: %w", ferr)
					return
				}
				continue
			}
			if errors.Is(err, os.ErrClosed) {
				return
			}
			errCh <- fmt.Errorf("doc syscall ringbuf: %w", err)
			return
		}
	}()
	if procColl != nil {
		go func() {
			defer readers.Done()
			var procRec ringbuf.Record
			var sinceFlush int64
			for {
				// Khong dat deadline: cho khong thoi han. BPF proc nop voi co 0
				// nen kernel tu danh thuc khi co su kien. Dung bang Flush ->
				// ErrFlushed nhu ban sua SIGTERM (M6b-1.2 cau 1.1).
				perr := procColl.ReadInto(&procRec)
				if perr == nil {
					sinceFlush++
					handleProcEvent(&procRec)
					continue
				}
				if errors.Is(perr, os.ErrDeadlineExceeded) {
					continue
				}
				if errors.Is(perr, ringbuf.ErrFlushed) {
					if sinceFlush == 0 {
						return
					}
					sinceFlush = 0
					_ = procColl.Flush()
					continue
				}
				if errors.Is(perr, os.ErrClosed) {
					return
				}
				errCh <- fmt.Errorf("doc proc ringbuf: %w", perr)
				return
			}
		}()
	}
	readers.Wait()
	select {
	case err := <-errCh:
		if err != nil {
			return err
		}
	default:
	}

	close(stopHost)
	close(stopDisk)
	close(stopStatus)
	close(stopCgroup)
	close(stopPeriodic)
	<-periodicDone

	endMono, _ := monotonicNs()
	fmt.Fprintf(os.Stderr, "ket thuc longrun end_mono_ns=%d disk_skipped=%d\n", endMono, diskSkipped.Load())
	return nil
}

func refreshCgroupBoth(sc *syscallbpf.Collector, pc *procbpf.Collector, roots []string, stop <-chan struct{}, interval time.Duration) {
	if interval <= 0 {
		interval = time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-stop:
			return
		case <-ticker.C:
			ids, err := cgroupexpand.DescendantIDs(roots)
			if err != nil {
				bpflog.Note(os.Stderr, logPath, fmt.Sprintf("quet cgroup: %v", err))
				continue
			}
			if err := sc.ReplaceCgroupFilter(ids); err != nil {
				bpflog.Note(os.Stderr, logPath, fmt.Sprintf("cap nhat hids_cgroups: %v", err))
			}
			if pc != nil {
				if err := pc.ReplaceCgroupFilter(ids); err != nil {
					bpflog.Note(os.Stderr, logPath, fmt.Sprintf("cap nhat hids_proc_cgroups: %v", err))
				}
			}
		}
	}
}

func writeStatusRow(path string, cols []string) {
	needHeader := false
	if fi, err := os.Stat(path); err != nil || fi.Size() == 0 {
		needHeader = true
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	w := csv.NewWriter(f)
	w.Comma = '\t'
	if needHeader {
		_ = w.Write([]string{
			"wall", "records_per_sec", "kernel_drops_delta", "disk_skipped_total",
			"bin_bytes_compressed", "free_gb", "rss_bytes", "cpu_seconds_total", "proc_drops_delta",
		})
	}
	_ = w.Write(cols)
	w.Flush()
}
