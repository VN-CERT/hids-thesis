// rec-export: xuat file .bin ra CSV cho phan tich (M4/M6/C5).
package main

import (
	"bufio"
	"encoding/csv"
	"flag"
	"fmt"
	"os"

	"hids/internal/recfmt"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "rec-export: %v\n", err)
		os.Exit(1)
	}
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func run() error {
	flag.Parse()
	if flag.NArg() != 1 {
		return fmt.Errorf("cach dung: rec-export <file.bin>")
	}

	f, err := os.Open(flag.Arg(0))
	if err != nil {
		return err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 4*1024*1024)
	header, err := recfmt.ReadHeader(br)
	if err != nil {
		return err
	}
	recordSize, err := recfmt.RecordSizeFromHeader(header)
	if err != nil {
		return err
	}
	payload, err := recfmt.RecordPayloadReader(header, br)
	if err != nil {
		return err
	}

	w := csv.NewWriter(os.Stdout)
	// Cot theo TEN (detector_c5 / c5_extract). Them cgroup_id, seq, vol_us.
	// vol_ns, dt_ns giu tuong thich nguoc voi script M4/M6.
	if err := w.Write([]string{
		"ts_enter", "cgroup_id", "tid", "seq", "syscall_nr", "flags",
		"cpu_ns", "steal_ns", "irq_ns", "rq_ns", "vol_us", "steal_off_ns",
		"inst", "cyc", "pmu_ok",
		"vol_ns", "dt_ns",
	}); err != nil {
		return err
	}

	lastTs := map[uint32]uint64{}
	_, _, err = recfmt.ForEach(payload, recordSize, func(r recfmt.Record) error {
		dt := ""
		if r.Flags&recfmt.FlagFirst == 0 {
			if prev, ok := lastTs[r.TID]; ok && r.TsEnter > prev {
				dt = fmt.Sprintf("%d", r.TsEnter-prev)
			}
		}
		lastTs[r.TID] = r.TsEnter
		volNs := uint64(r.VolUs) * 1000
		row := []string{
			fmt.Sprintf("%d", r.TsEnter),
			fmt.Sprintf("%d", r.CgroupID),
			fmt.Sprintf("%d", r.TID),
			fmt.Sprintf("%d", r.Seq),
			fmt.Sprintf("%d", r.SyscallNr),
			fmt.Sprintf("%d", r.Flags),
			fmt.Sprintf("%d", r.CPUNs),
			fmt.Sprintf("%d", r.StealNs),
			fmt.Sprintf("%d", r.IrqNs),
			fmt.Sprintf("%d", r.RqNs),
			fmt.Sprintf("%d", r.VolUs),
			fmt.Sprintf("%d", r.StealOffNs),
			fmt.Sprintf("%d", r.Inst),
			fmt.Sprintf("%d", r.Cyc),
			fmt.Sprintf("%d", boolToInt(r.Flags&recfmt.FlagPMU != 0)),
			fmt.Sprintf("%d", volNs),
			dt,
		}
		return w.Write(row)
	})
	if err != nil {
		return err
	}
	w.Flush()
	return w.Error()
}
