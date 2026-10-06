// steal-probe chup bo dem steal cua tung CPU bang BPF va doc gia tri tham chieu
// trong /proc/stat ngay sau do, roi ghi ra CSV. Can chay bang root.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/cilium/ebpf"

	"hids/internal/buildinfo"
	"hids/internal/hostinfo"
	"hids/internal/procstat"
	"hids/internal/stealbpf"
	"hids/internal/stealcsv"
)

const logPath = "out/steal-probe.log"

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "steal-probe: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	interval := flag.Duration("interval", time.Second, "khoang cach giua hai lan chup")
	duration := flag.Duration("duration", 0, "tong thoi gian chay, 0 = chay den khi nhan SIGINT/SIGTERM")
	out := flag.String("out", "", "file CSV ket qua, de trong thi tu dat ten out/steal-<YYYYmmdd-HHMMSS>.csv")
	noVMW := flag.Bool("no-vmw", false, "bo qua vmw_steal_time, chi doc runqueues.prev_steal_time (de kiem tra duong du phong)")
	flag.Parse()

	if *interval <= 0 {
		return fmt.Errorf("-interval phai lon hon 0")
	}
	if *duration < 0 {
		return fmt.Errorf("-duration khong duoc am")
	}
	if os.Geteuid() != 0 {
		return fmt.Errorf("can chay bang root (nap chuong trinh BPF va doc ksym kernel)")
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
	if nrCPUs > stealbpf.MaxCPUs {
		return fmt.Errorf("may co %d CPU online, chuong trinh BPF chi doc toi da %d CPU", nrCPUs, stealbpf.MaxCPUs)
	}
	userHZ, userHZSrc, err := hostinfo.UserHZ()
	if err != nil {
		return err
	}
	tsc, err := hostinfo.TSCKHz()
	if err != nil {
		return fmt.Errorf("%w; dung lai vi khong duoc doan tan so TSC", err)
	}

	outPath := *out
	if outPath == "" {
		outPath = filepath.Join("out", fmt.Sprintf("steal-%s.csv", time.Now().Format("20060102-150405")))
	}
	if dir := filepath.Dir(outPath); dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return err
		}
	}

	snap, vmwErr, err := stealbpf.Load(*noVMW)
	if vmwErr != nil {
		reportBPFError("khong nap duoc ban doc vmw_steal_time, chuyen sang ban chi co runqueues", vmwErr)
	}
	if err != nil {
		reportBPFError("khong nap duoc chuong trinh BPF", err)
		return fmt.Errorf("nap BPF that bai, chi tiet o %s", logPath)
	}
	defer snap.Close()

	w, err := stealcsv.Create(outPath, []string{
		fmt.Sprintf("uname_r: %s", release),
		fmt.Sprintf("nr_cpus: %d", nrCPUs),
		fmt.Sprintf("tsc_khz: %d", tsc.KHz),
		fmt.Sprintf("tsc_source: %s | %s", tsc.Source, tsc.Line),
		fmt.Sprintf("bpf_mechanism: %s", snap.Mechanism()),
		fmt.Sprintf("git_commit: %s", buildinfo.GitCommit()),
		fmt.Sprintf("interval: %s", *interval),
		fmt.Sprintf("duration: %s", durationText(*duration)),
		fmt.Sprintf("user_hz: %d (%s)", userHZ, userHZSrc),
		fmt.Sprintf("reference: %s cot steal (1/USER_HZ giay), doc ngay sau moi lan chup BPF", procstat.Path),
	})
	if err != nil {
		return err
	}
	defer w.Close()

	fmt.Fprintf(os.Stderr, "ghi vao %s\n", outPath)
	fmt.Fprintf(os.Stderr, "co che BPF: %s\n", snap.Mechanism())
	fmt.Fprintf(os.Stderr, "tsc_khz=%d nr_cpus=%d user_hz=%d interval=%s duration=%s\n",
		tsc.KHz, nrCPUs, userHZ, *interval, durationText(*duration))

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	reader := procstat.NewReader(nrCPUs)
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	start := time.Now()
	var deadline time.Time
	if *duration > 0 {
		deadline = start.Add(*duration)
	}

	cycles := 0
	sample := func() error {
		if err := sampleOnce(w, snap, reader, nrCPUs, tsc.KHz); err != nil {
			return err
		}
		cycles++
		return nil
	}

	if err := sample(); err != nil {
		return err
	}

loop:
	for {
		select {
		case <-ctx.Done():
			break loop
		case t := <-ticker.C:
			if !deadline.IsZero() && t.After(deadline) {
				break loop
			}
			if err := sample(); err != nil {
				return err
			}
		}
	}

	if err := w.Flush(); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "da ghi %d chu ky x %d CPU vao %s\n", cycles, nrCPUs, outPath)
	return nil
}

func sampleOnce(w *stealcsv.Writer, snap *stealbpf.Snapshotter, reader *procstat.Reader, nrCPUs int, tscKHz uint64) error {
	wall := time.Now()

	slots, err := snap.Snapshot(nrCPUs)
	if err != nil {
		return err
	}
	ticks, err := reader.ReadSteal()
	if err != nil {
		return err
	}

	for i, s := range slots {
		rec := stealcsv.Record{
			MonoNs:        s.TsNs,
			Wall:          wall,
			CPU:           int(s.CPU),
			RqStealNs:     s.RqStealNs,
			HasRq:         s.HasRQ(),
			ProcstatTicks: ticks[i],
		}
		if s.HasVMW() {
			ns, err := stealcsv.VmwNs(s.VmwRaw, tscKHz)
			if err != nil {
				return err
			}
			rec.VmwRaw = s.VmwRaw
			rec.VmwNs = ns
			rec.HasVmw = true
		}
		if err := w.Write(rec); err != nil {
			return err
		}
	}

	// Day xuong dia sau moi chu ky de du lieu khong mat khi dung giua chung.
	return w.Flush()
}

// reportBPFError in nguyen van loi verifier/libbpf ra stderr va ghi them vao out/steal-probe.log.
func reportBPFError(context string, err error) {
	text := formatBPFError(err)
	fmt.Fprintf(os.Stderr, "%s:\n%s\n", context, text)

	if mkErr := os.MkdirAll(filepath.Dir(logPath), 0o755); mkErr != nil {
		fmt.Fprintf(os.Stderr, "khong tao duoc thu muc log: %v\n", mkErr)
		return
	}
	f, openErr := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if openErr != nil {
		fmt.Fprintf(os.Stderr, "khong mo duoc %s: %v\n", logPath, openErr)
		return
	}
	defer f.Close()
	fmt.Fprintf(f, "=== %s %s ===\n%s\n", time.Now().Format(time.RFC3339), context, text)
}

func formatBPFError(err error) string {
	var ve *ebpf.VerifierError
	if errors.As(err, &ve) {
		return fmt.Sprintf("%+v", ve)
	}
	return err.Error()
}

func durationText(d time.Duration) string {
	if d == 0 {
		return "khong gioi han"
	}
	return d.String()
}
