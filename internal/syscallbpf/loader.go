package syscallbpf

import (
	"errors"
	"fmt"
	"os"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/ringbuf"
	"github.com/cilium/ebpf/rlimit"

	"hids/internal/recfmt"
)

// DefaultRingbufMB la kich thuoc ring buffer mac dinh.
const DefaultRingbufMB = 64

// Config la cau hinh nap vao kernel truoc khi nap chuong trinh.
type Config struct {
	SelfTGID     uint32   // tgid cua chinh collector, luon bi bo qua
	TGIDs        []uint32 // tap PID dich
	CgroupIDs    []uint64 // tap cgroup dich (so inode thu muc cgroup v2)
	RingbufBytes uint32   // kich thuoc ring buffer, phai la luy thua cua 2
}

// Collector giu chuong trinh BPF da nap, link va bo doc ring buffer.
type Collector struct {
	coll   *ebpf.Collection
	lnk    link.Link
	reader *ringbuf.Reader
}

// Load nap chuong trinh, nap cau hinh loc vao map va gan vao tp_btf/sys_enter.
func Load(cfg Config) (*Collector, error) {
	if cfg.RingbufBytes == 0 {
		cfg.RingbufBytes = DefaultRingbufMB * 1024 * 1024
	}
	if cfg.RingbufBytes&(cfg.RingbufBytes-1) != 0 {
		return nil, fmt.Errorf("kich thuoc ring buffer %d byte khong phai luy thua cua 2", cfg.RingbufBytes)
	}
	if len(cfg.TGIDs) == 0 && len(cfg.CgroupIDs) == 0 {
		return nil, errors.New("khong co bo loc nao: can it nhat mot -pid hoac mot -cgroup")
	}

	if err := rlimit.RemoveMemlock(); err != nil {
		return nil, fmt.Errorf("go gioi han memlock: %w", err)
	}

	spec, err := loadSysEnter()
	if err != nil {
		return nil, err
	}

	spec.Maps["hids_events"].MaxEntries = cfg.RingbufBytes
	if err := spec.Variables["hids_self_tgid"].Set(cfg.SelfTGID); err != nil {
		return nil, fmt.Errorf("dat hids_self_tgid: %w", err)
	}
	filterCgroup := uint8(0)
	if len(cfg.CgroupIDs) > 0 {
		filterCgroup = 1
	}
	if err := spec.Variables["hids_filter_cgroup"].Set(filterCgroup); err != nil {
		return nil, fmt.Errorf("dat hids_filter_cgroup: %w", err)
	}

	coll, err := ebpf.NewCollectionWithOptions(spec, ebpf.CollectionOptions{
		Programs: ebpf.ProgramOptions{LogLevel: ebpf.LogLevelBranch},
	})
	if err != nil {
		return nil, err
	}

	c := &Collector{coll: coll}
	defer func() {
		if c.coll != nil && c.lnk == nil {
			coll.Close()
		}
	}()

	one := uint8(1)
	for _, tgid := range cfg.TGIDs {
		if err := coll.Maps["hids_pids"].Put(tgid, one); err != nil {
			return nil, fmt.Errorf("nap tgid %d vao hids_pids: %w", tgid, err)
		}
	}
	for _, id := range cfg.CgroupIDs {
		if err := coll.Maps["hids_cgroups"].Put(id, one); err != nil {
			return nil, fmt.Errorf("nap cgroup id %d vao hids_cgroups: %w", id, err)
		}
	}

	reader, err := ringbuf.NewReader(coll.Maps["hids_events"])
	if err != nil {
		return nil, fmt.Errorf("mo ring buffer: %w", err)
	}
	c.reader = reader

	lnk, err := link.AttachTracing(link.TracingOptions{Program: coll.Programs["hids_sys_enter"]})
	if err != nil {
		reader.Close()
		return nil, fmt.Errorf("gan hids_sys_enter vao tp_btf/sys_enter: %w", err)
	}
	c.lnk = lnk

	return c, nil
}

// ReadInto doc mot ban ghi tu ring buffer vao rec.
func (c *Collector) ReadInto(rec *ringbuf.Record) error {
	return c.reader.ReadInto(rec)
}

// Detach go chuong trinh khoi tracepoint de khong con ban ghi moi sinh ra.
// Cac ban ghi con trong ring buffer van doc tiep duoc.
func (c *Collector) Detach() error {
	if c.lnk == nil {
		return nil
	}
	err := c.lnk.Close()
	c.lnk = nil
	return err
}

// Flush danh thuc vong doc dang cho: ReadInto tra ve het cac ban ghi dang nam
// trong ring buffer roi tra ve ringbuf.ErrFlushed.
//
// Khong dung SetDeadline cho viec nay: SetDeadline giu cung mot mutex voi
// ReadInto nen se treo khi vong doc dang cho du lieu.
func (c *Collector) Flush() error {
	return c.reader.Flush()
}

// AvailableBytes tra ve so byte dang cho doc trong ring buffer.
func (c *Collector) AvailableBytes() int {
	return c.reader.AvailableBytes()
}

// Stats doc bo dem seq va bo dem mat cua tung CPU tu kernel.
func (c *Collector) Stats() ([]recfmt.CPUStat, error) {
	var seq []uint32
	if err := c.coll.Maps["hids_seq"].Lookup(uint32(0), &seq); err != nil {
		return nil, fmt.Errorf("doc hids_seq: %w", err)
	}
	var drops []uint64
	if err := c.coll.Maps["hids_drops"].Lookup(uint32(0), &drops); err != nil {
		return nil, fmt.Errorf("doc hids_drops: %w", err)
	}
	if len(seq) != len(drops) {
		return nil, fmt.Errorf("hids_seq co %d CPU, hids_drops co %d CPU", len(seq), len(drops))
	}

	out := make([]recfmt.CPUStat, len(seq))
	for i := range seq {
		out[i] = recfmt.CPUStat{CPU: i, SeqLast: seq[i], Drops: drops[i]}
	}
	return out, nil
}

// Close go sach moi thu khoi kernel: link, ring buffer, chuong trinh, map.
// Khong co gi duoc pin nen sau khi dong kernel khong con doi tuong nao.
func (c *Collector) Close() error {
	var firstErr error
	if c.lnk != nil {
		if err := c.lnk.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
		c.lnk = nil
	}
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
