package syscallbpf

import (
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/ringbuf"
	"github.com/cilium/ebpf/rlimit"

	"hids/internal/percpuksym"
	"hids/internal/recfmt"
)

// DefaultRingbufMB la kich thuoc ring buffer mac dinh.
const DefaultRingbufMB = 64

// perCPUKsyms la cac bien per-CPU cua kernel ma chuong trinh BPF doc.
var perCPUKsyms = []string{"vmw_steal_time", "runqueues"}

const mainProgramTracepoint = "hids_sys_enter"
const mainProgramFentry = "hids_sys_enter_fentry"

// SysEnterHookTracepoint / SysEnterHookFentry chon diem gan chuong trinh phat ban ghi.
const (
	SysEnterHookTracepoint = "tracepoint"
	SysEnterHookFentry     = "fentry"
)

// schedPrograms la cac chuong trinh dung cho ranh gioi ON-CPU / OFF-CPU.
var schedPrograms = []string{"hids_sched_switch", "hids_sched_wakeup", "hids_sched_wakeup_new"}

// irqProgramPrefix la tien to ten cac chuong trinh do irq.
const irqProgramPrefix = "hids_irq_"

// Config la cau hinh nap vao kernel truoc khi nap chuong trinh.
type Config struct {
	SelfTGID      uint32   // tgid cua chinh collector, luon bi bo qua
	TGIDs         []uint32 // tap PID dich
	CgroupIDs     []uint64 // tap cgroup dich (so inode thu muc cgroup v2)
	RingbufBytes  uint32   // kich thuoc ring buffer, phai la luy thua cua 2
	TSCKHz        uint64   // tan so TSC, de quy chu ky steal ra ns trong BPF
	StealFallback bool     // dung rq->prev_steal_time thay vi vmw_steal_time
	StealOff      bool     // khong do steal (khong co stealclock)
	SysEnterHook  string   // tracepoint (mac dinh) hoac fentry (x64_sys_call)
}

// IRQStat la so lieu irq cua mot CPU.
type IRQStat struct {
	CPU        int
	HardNs     uint64
	VecNs      uint64
	SoftRawNs  uint64 // ke ca hard/vector long ben trong, de so voi softirqs-bpfcc
	SoftExclNs uint64 // da tru phan long, day la phan dung cho thanh phan irq
	OddNs      uint64 // tong khoang irq bi loai vi qua dai, phai bang 0
	OddCnt     uint32 // so khoang bi loai, phai bang 0
	Active     int    // so loai con dang hoat dong luc doc, phai bang 0 luc ket thuc
}

// TotalNs tra ve thanh phan irq cua CPU nay: hard + vector + soft da tru phan long.
func (s IRQStat) TotalNs() uint64 { return s.HardNs + s.VecNs + s.SoftExclNs }

// irqState trung bo cuc voi struct hids_irqstate trong BPF.
type irqState struct {
	HardStart      uint64
	HardStartSteal uint64
	HardNs         uint64
	VecStart       uint64
	VecStartSteal  uint64
	VecNs          uint64
	SoftStart      uint64
	SoftStartSteal uint64
	SoftSnap       uint64
	SoftRawNs      uint64
	SoftExclNs     uint64
	OddNs          uint64
	OddCnt         uint32
	Pad            uint32
}

// Collector giu chuong trinh BPF da nap, cac link va bo doc ring buffer.
type Collector struct {
	coll        *ebpf.Collection
	links       []link.Link
	mainLink    link.Link
	mainHook    string
	reader      *ringbuf.Reader
	irqTPs      []string
}

// Load nap chuong trinh, nap cau hinh loc vao map va gan vao cac tracepoint.
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
	if !cfg.StealOff && !cfg.StealFallback && cfg.TSCKHz == 0 {
		return nil, errors.New("thieu tan so TSC: khong quy doi duoc chu ky steal ra ns")
	}

	if err := rlimit.RemoveMemlock(); err != nil {
		return nil, fmt.Errorf("go gioi han memlock: %w", err)
	}

	spec, err := loadSysEnter()
	if err != nil {
		return nil, err
	}

	// Ham doc ksym la __always_inline nen duoc nhung vao nhieu chuong trinh;
	// phai va tat ca.
	if err := percpuksym.PatchCollection(spec, perCPUKsyms); err != nil {
		return nil, err
	}

	spec.Maps["hids_events"].MaxEntries = cfg.RingbufBytes

	filterCgroup := uint8(0)
	if len(cfg.CgroupIDs) > 0 {
		filterCgroup = 1
	}
	filterPID := uint8(0)
	if len(cfg.TGIDs) > 0 {
		filterPID = 1
	}
	rbWakeBytes := uint64(cfg.RingbufBytes) / 8
	vars := map[string]any{
		"hids_self_tgid":       cfg.SelfTGID,
		"hids_filter_cgroup":   filterCgroup,
		"hids_filter_pid":      filterPID,
		"hids_rb_wake_bytes":   rbWakeBytes,
		"hids_tsc_khz":         cfg.TSCKHz,
		"hids_steal_fallback":  boolToU8(cfg.StealFallback),
		"hids_steal_off":       boolToU8(cfg.StealOff),
	}
	for name, val := range vars {
		v := spec.Variables[name]
		if v == nil {
			return nil, fmt.Errorf("khong tim thay bien %s trong ELF", name)
		}
		if err := v.Set(val); err != nil {
			return nil, fmt.Errorf("dat %s: %w", name, err)
		}
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

	one := uint8(1)
	for _, tgid := range cfg.TGIDs {
		if err := coll.Maps["hids_pids"].Put(tgid, one); err != nil {
			return nil, fmt.Errorf("nap tgid %d vao hids_pids: %w", tgid, err)
		}
	}
	if len(cfg.CgroupIDs) > 0 {
		if err := c.ReplaceCgroupFilter(cfg.CgroupIDs); err != nil {
			return nil, err
		}
	}

	reader, err := ringbuf.NewReader(coll.Maps["hids_events"])
	if err != nil {
		return nil, fmt.Errorf("mo ring buffer: %w", err)
	}
	c.reader = reader

	// Gan cac chuong trinh phu TRUOC chuong trinh chinh: khi hids_sys_enter
	// bat dau tao trang thai thread thi may trang thai da san sang.
	//
	// Thu tu trong moi cap irq quan trong: phai gan *_exit TRUOC *_entry.
	// Neu gan entry truoc, mot irq roi vao dung khe giua hai lan gan se duoc
	// ghi entry (do sau 0 -> 1, dat moc) nhung khong co exit de ha do sau,
	// nen CPU do ket o do sau 1 voi mot moc cu; lan exit sau do cong ca
	// khoang thoi gian tu luc gan vao bo cong don irq. Detach lam nguoc lai
	// (xem Detach): go entry truoc, con exit de dong not irq dang chay.
	entries, exits := irqProgramNames(coll)
	for _, name := range exits {
		if err := c.attach(name); err != nil {
			return nil, err
		}
		c.irqTPs = append(c.irqTPs, strings.TrimPrefix(name, irqProgramPrefix))
	}
	for _, name := range entries {
		if err := c.attach(name); err != nil {
			return nil, err
		}
	}
	for _, name := range schedPrograms {
		if err := c.attach(name); err != nil {
			return nil, err
		}
	}

	mainName := mainProgramTracepoint
	switch cfg.SysEnterHook {
	case "", SysEnterHookTracepoint:
		mainName = mainProgramTracepoint
	case SysEnterHookFentry:
		mainName = mainProgramFentry
	default:
		return nil, fmt.Errorf("sys_enter_hook khong hop le: %q (can %q hoac %q)",
			cfg.SysEnterHook, SysEnterHookTracepoint, SysEnterHookFentry)
	}
	prog := coll.Programs[mainName]
	if prog == nil {
		return nil, fmt.Errorf("khong tim thay chuong trinh %s", mainName)
	}
	lnk, err := link.AttachTracing(link.TracingOptions{Program: prog})
	if err != nil {
		return nil, fmt.Errorf("gan %s: %w", mainName, err)
	}
	c.mainLink = lnk
	c.mainHook = cfg.SysEnterHook
	if c.mainHook == "" {
		c.mainHook = SysEnterHookTracepoint
	}

	ok = true
	return c, nil
}

func boolToU8(b bool) uint8 {
	if b {
		return 1
	}
	return 0
}

// irqProgramNames tra ve ten cac chuong trinh do irq, tach thanh nhom entry va
// nhom exit, moi nhom sap xep de thu tu gan va danh sach ghi vao header luon
// on dinh.
func irqProgramNames(coll *ebpf.Collection) (entries, exits []string) {
	for name := range coll.Programs {
		if !strings.HasPrefix(name, irqProgramPrefix) {
			continue
		}
		switch {
		case strings.HasSuffix(name, "_entry"):
			entries = append(entries, name)
		case strings.HasSuffix(name, "_exit"):
			exits = append(exits, name)
		}
	}
	sort.Strings(entries)
	sort.Strings(exits)
	return entries, exits
}

func (c *Collector) attach(name string) error {
	prog := c.coll.Programs[name]
	if prog == nil {
		return fmt.Errorf("khong tim thay chuong trinh %s", name)
	}
	lnk, err := link.AttachTracing(link.TracingOptions{Program: prog})
	if err != nil {
		return fmt.Errorf("gan %s: %w", name, err)
	}
	c.links = append(c.links, lnk)
	return nil
}

// IRQTracepoints tra ve ten cac tracepoint irq da gan (khong co tien to
// hids_irq_, moi ten la mot cap *_entry/*_exit).
func (c *Collector) IRQTracepoints() []string {
	seen := map[string]bool{}
	var out []string
	for _, n := range c.irqTPs {
		base := strings.TrimSuffix(strings.TrimSuffix(n, "_entry"), "_exit")
		if !seen[base] {
			seen[base] = true
			out = append(out, base)
		}
	}
	sort.Strings(out)
	return out
}

// ReadInto doc mot ban ghi tu ring buffer vao rec.
func (c *Collector) ReadInto(rec *ringbuf.Record) error {
	return c.reader.ReadInto(rec)
}

// SetDeadline dat timeout cho ReadInto (O1: poll 10 ms).
func (c *Collector) SetDeadline(t time.Time) {
	c.reader.SetDeadline(t)
}

// SysEnterHook tra ve che do gan chinh (tracepoint hoac fentry).
func (c *Collector) SysEnterHook() string {
	if c.mainHook == "" {
		return SysEnterHookTracepoint
	}
	return c.mainHook
}

// ReplaceCgroupFilter thay toan bo key trong hids_cgroups bang tap id moi.
func (c *Collector) ReplaceCgroupFilter(ids []uint64) error {
	m := c.coll.Maps["hids_cgroups"]
	if m == nil {
		return errors.New("khong tim thay map hids_cgroups")
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

// Detach go chuong trinh khoi tracepoint de khong con ban ghi moi sinh ra.
// Cac ban ghi con trong ring buffer van doc tiep duoc.
//
// Go theo thu tu NGUOC voi luc gan, nen trong moi cap irq thi *_entry duoc go
// truoc *_exit: irq dang chay van co exit de ha do sau ve 0.
func (c *Collector) Detach() error {
	var firstErr error
	if c.mainLink != nil {
		if err := c.mainLink.Close(); err != nil {
			firstErr = err
		}
		c.mainLink = nil
	}
	for i := len(c.links) - 1; i >= 0; i-- {
		if err := c.links[i].Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	c.links = nil
	return firstErr
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

// IRQStats doc bo cong don irq cua tung CPU tu kernel.
func (c *Collector) IRQStats() ([]IRQStat, error) {
	var raw []irqState
	if err := c.coll.Maps["hids_irq"].Lookup(uint32(0), &raw); err != nil {
		return nil, fmt.Errorf("doc hids_irq: %w", err)
	}
	out := make([]IRQStat, len(raw))
	for i, r := range raw {
		active := 0
		for _, start := range []uint64{r.HardStart, r.VecStart, r.SoftStart} {
			if start != 0 {
				active++
			}
		}
		out[i] = IRQStat{
			CPU:        i,
			HardNs:     r.HardNs,
			VecNs:      r.VecNs,
			SoftRawNs:  r.SoftRawNs,
			SoftExclNs: r.SoftExclNs,
			OddNs:      r.OddNs,
			OddCnt:     r.OddCnt,
			Active:     active,
		}
	}
	return out, nil
}

// RecursionMiss la so lan kernel tu choi chay lai mot chuong trinh BPF vi no
// da dang chay tren cung CPU. Phai bang 0; khac 0 nghia la co su kien bi bo qua.
type RecursionMiss struct {
	Program string
	Misses  uint64
}

// RecursionMisses doc recursion_misses cua TUNG chuong trinh tu bpf_prog_info.
func (c *Collector) RecursionMisses() ([]RecursionMiss, error) {
	names := make([]string, 0, len(c.coll.Programs))
	for name := range c.coll.Programs {
		names = append(names, name)
	}
	sort.Strings(names)

	out := make([]RecursionMiss, 0, len(names))
	for _, name := range names {
		// recursion_misses duoc kernel dem khong dieu kien (bpf_prog_inc_misses_counter),
		// khong can bat bpf_stats_enabled.
		stats, err := c.coll.Programs[name].Stats()
		if err != nil {
			return nil, fmt.Errorf("doc bpf_prog_info cua %s: %w", name, err)
		}
		out = append(out, RecursionMiss{Program: name, Misses: stats.RecursionMisses})
	}
	return out, nil
}

// Close go sach moi thu khoi kernel: link, ring buffer, chuong trinh, map.
// Khong co gi duoc pin nen sau khi dong kernel khong con doi tuong nao.
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
