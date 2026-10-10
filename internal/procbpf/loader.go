package procbpf

import (
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/ringbuf"
)

// EventSize la kich thuoc ban ghi ring buffer (176 byte).
const EventSize = 176

const (
	TypeFork = 1
	TypeExec = 2
	TypeExit = 3
)

var progNames = []string{"hids_proc_fork", "hids_proc_exec", "hids_proc_exit"}

// Config cau hinh nap proc BPF.
type Config struct {
	SelfTGID uint32
}

// Collector giu object proc_events.
type Collector struct {
	coll   *ebpf.Collection
	links  []link.Link
	reader *ringbuf.Reader
}

// Load nap va gan tracepoint sched_process_*.
func Load(cfg Config) (*Collector, error) {
	spec, err := loadProcEvents()
	if err != nil {
		return nil, err
	}
	coll, err := ebpf.NewCollectionWithOptions(spec, ebpf.CollectionOptions{
		Programs: ebpf.ProgramOptions{LogLevel: ebpf.LogLevelBranch},
	})
	if err != nil {
		return nil, err
	}
	c := &Collector{coll: coll}
	ok := false
	defer func() {
		if !ok {
			c.Close()
		}
	}()
	v := coll.Variables["hids_proc_self_tgid"]
	if v == nil {
		return nil, errors.New("khong tim thay hids_proc_self_tgid")
	}
	if err := v.Set(cfg.SelfTGID); err != nil {
		return nil, fmt.Errorf("dat hids_proc_self_tgid: %w", err)
	}
	reader, err := ringbuf.NewReader(coll.Maps["hids_proc_events"])
	if err != nil {
		return nil, fmt.Errorf("mo hids_proc_events: %w", err)
	}
	c.reader = reader
	for _, name := range progNames {
		prog := coll.Programs[name]
		if prog == nil {
			return nil, fmt.Errorf("khong tim thay %s", name)
		}
		lnk, err := link.AttachTracing(link.TracingOptions{Program: prog})
		if err != nil {
			return nil, fmt.Errorf("gan %s: %w", name, err)
		}
		c.links = append(c.links, lnk)
	}
	ok = true
	return c, nil
}

// ReplaceCgroupFilter cap nhat hids_proc_cgroups.
func (c *Collector) ReplaceCgroupFilter(ids []uint64) error {
	m := c.coll.Maps["hids_proc_cgroups"]
	if m == nil {
		return errors.New("khong tim thay hids_proc_cgroups")
	}
	var key uint64
	var val uint8
	iter := m.Iterate()
	for iter.Next(&key, &val) {
		if err := m.Delete(key); err != nil {
			return fmt.Errorf("xoa cgroup id %d: %w", key, err)
		}
	}
	one := uint8(1)
	for _, id := range ids {
		if err := m.Put(id, one); err != nil {
			return fmt.Errorf("nap cgroup id %d: %w", id, err)
		}
	}
	return nil
}

// ReadInto doc mot su kien proc.
func (c *Collector) ReadInto(rec *ringbuf.Record) error {
	return c.reader.ReadInto(rec)
}

// SetDeadline dat timeout doc.
func (c *Collector) SetDeadline(t time.Time) {
	c.reader.SetDeadline(t)
}

// Flush danh thuc vong doc.
func (c *Collector) Flush() error {
	return c.reader.Flush()
}

// Drops tra ve tong so ban ghi mat (per-CPU map).
func (c *Collector) Drops() (uint64, error) {
	var perCPU []uint64
	if err := c.coll.Maps["hids_proc_drops"].Lookup(uint32(0), &perCPU); err != nil {
		return 0, fmt.Errorf("doc hids_proc_drops: %w", err)
	}
	var sum uint64
	for _, d := range perCPU {
		sum += d
	}
	return sum, nil
}

// DropsPerCPU tra ve bo dem mat theo CPU (de doi chieu).
func (c *Collector) DropsPerCPU() ([]uint64, error) {
	var perCPU []uint64
	if err := c.coll.Maps["hids_proc_drops"].Lookup(uint32(0), &perCPU); err != nil {
		return nil, fmt.Errorf("doc hids_proc_drops: %w", err)
	}
	return perCPU, nil
}

// Detach go tracepoint.
func (c *Collector) Detach() error {
	var firstErr error
	for i := len(c.links) - 1; i >= 0; i-- {
		if err := c.links[i].Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	c.links = nil
	return firstErr
}

// Close giai phong tai nguyen.
func (c *Collector) Close() error {
	firstErr := c.Detach()
	if c.reader != nil {
		if err := c.reader.Close(); err != nil && !errors.Is(err, os.ErrClosed) && firstErr == nil {
			firstErr = err
		}
		c.reader = nil
	}
	if c.coll != nil {
		c.coll.Close()
		c.coll = nil
	}
	return firstErr
}
