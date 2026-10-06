package stealbpf

import (
	"errors"
	"fmt"
	"strings"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/asm"
	"github.com/cilium/ebpf/btf"
	"github.com/cilium/ebpf/rlimit"
)

// MaxCPUs la so CPU toi da chuong trinh BPF doc duoc (bang HIDS_MAX_CPUS trong bpf/steal_snap.bpf.c).
const MaxCPUs = 64

// Co trong Slot.Flags, khop HIDS_SLOT_* trong bpf/steal_snap.bpf.c.
const (
	FlagVMW uint32 = 1 << 0
	FlagRQ  uint32 = 1 << 1
)

// pseudoBTFID la BPF_PSEUDO_BTF_ID (src_reg = 3 cua lenh ld_imm64).
// cilium/ebpf khong co hang so nay nen dinh nghia tai day.
const pseudoBTFID = asm.Register(3)

// Ten cac co che doc, ghi nguyen van vao header CSV.
const (
	MechSyscallFull   = "SEC(syscall) + BPF_PROG_RUN, bpf_per_cpu_ptr(vmw_steal_time) + bpf_per_cpu_ptr(runqueues)"
	MechSyscallRQOnly = "SEC(syscall) + BPF_PROG_RUN, chi bpf_per_cpu_ptr(runqueues) (ksym vmw_steal_time khong nap duoc)"
)

// Slot la mot ban ghi cua mot CPU, trung bo cuc voi struct hids_steal_slot trong BPF.
type Slot struct {
	TsNs      uint64
	VmwRaw    uint64
	RqStealNs uint64
	Flags     uint32
	CPU       uint32
}

// HasVMW cho biet vmw_steal_time.clock doc duoc o lan chup nay.
func (s Slot) HasVMW() bool { return s.Flags&FlagVMW != 0 }

// HasRQ cho biet runqueues.prev_steal_time doc duoc o lan chup nay.
func (s Slot) HasRQ() bool { return s.Flags&FlagRQ != 0 }

type snapArgs struct {
	NrCpus uint32
	Pad    uint32
}

// Snapshotter giu chuong trinh BPF da nap va chup bo dem steal theo yeu cau.
type Snapshotter struct {
	coll      *ebpf.Collection
	prog      *ebpf.Program
	slots     *ebpf.Variable
	count     *ebpf.Variable
	mechanism string
	hasVMW    bool

	buf [MaxCPUs]Slot
}

// Mechanism mo ta co che da dung de nap va chay chuong trinh.
func (s *Snapshotter) Mechanism() string { return s.mechanism }

// HasVMW cho biet chuong trinh dang nap co doc vmw_steal_time hay khong.
func (s *Snapshotter) HasVMW() bool { return s.hasVMW }

// Close go toan bo chuong trinh va map khoi kernel. Khong co gi duoc pin nen
// sau khi dong, kernel khong con doi tuong nao cua cong cu nay.
func (s *Snapshotter) Close() error {
	if s.coll == nil {
		return nil
	}
	s.coll.Close()
	s.coll = nil
	s.prog = nil
	return nil
}

// Snapshot chay chuong trinh BPF mot lan va tra ve ban ghi cua nrCPUs CPU dau tien.
// Lat cat tra ve dung lai bo dem noi bo, copy neu can giu.
func (s *Snapshotter) Snapshot(nrCPUs int) ([]Slot, error) {
	if nrCPUs <= 0 || nrCPUs > MaxCPUs {
		return nil, fmt.Errorf("nr_cpus=%d ngoai khoang 1..%d", nrCPUs, MaxCPUs)
	}

	args := snapArgs{NrCpus: uint32(nrCPUs)}
	ret, err := s.prog.Run(&ebpf.RunOptions{Context: &args})
	if err != nil {
		return nil, fmt.Errorf("BPF_PROG_RUN hids_steal_snap: %w", err)
	}
	if ret != 0 {
		return nil, fmt.Errorf("hids_steal_snap tra ve %d", ret)
	}

	if err := s.slots.Get(&s.buf); err != nil {
		return nil, fmt.Errorf("doc hids_steal_slots: %w", err)
	}

	return s.buf[:nrCPUs], nil
}

// SnapCount tra ve so lan chuong trinh da chay (bien hids_snap_count).
func (s *Snapshotter) SnapCount() (uint64, error) {
	var n uint64
	if err := s.count.Get(&n); err != nil {
		return 0, fmt.Errorf("doc hids_snap_count: %w", err)
	}
	return n, nil
}

// Load nap chuong trinh BPF. Uu tien ban doc ca vmw_steal_time va runqueues;
// neu ban do khong nap duoc, nap ban chi doc runqueues va tra loi nguyen van
// cua lan dau qua vmwErr. Dat skipVMW = true de bo qua ban day du (dung de
// kiem tra nhanh du phong).
func Load(skipVMW bool) (snap *Snapshotter, vmwErr error, err error) {
	if err := rlimit.RemoveMemlock(); err != nil {
		return nil, nil, fmt.Errorf("go gioi han memlock: %w", err)
	}

	var errFull error
	if skipVMW {
		errFull = errors.New("bo qua ban doc vmw_steal_time theo yeu cau (-no-vmw)")
	} else {
		full, err := loadVariant(loadStealSnap, []string{"vmw_steal_time", "runqueues"}, MechSyscallFull, true)
		if err == nil {
			return full, nil, nil
		}
		errFull = err
	}

	rqOnly, errRQ := loadVariant(loadStealSnapRq, []string{"runqueues"}, MechSyscallRQOnly, false)
	if errRQ != nil {
		return nil, errFull, fmt.Errorf("nap ban chi co runqueues cung that bai: %w", errRQ)
	}

	return rqOnly, errFull, nil
}

func loadVariant(specFn func() (*ebpf.CollectionSpec, error), ksyms []string, mech string, hasVMW bool) (*Snapshotter, error) {
	spec, err := specFn()
	if err != nil {
		return nil, err
	}

	prog := spec.Programs["hids_steal_snap"]
	if prog == nil {
		return nil, errors.New("khong tim thay chuong trinh hids_steal_snap trong ELF")
	}

	if err := assignPerCPUKsyms(prog, ksyms); err != nil {
		return nil, err
	}

	coll, err := ebpf.NewCollectionWithOptions(spec, ebpf.CollectionOptions{
		Programs: ebpf.ProgramOptions{LogLevel: ebpf.LogLevelBranch},
	})
	if err != nil {
		return nil, err
	}

	s := &Snapshotter{
		coll:      coll,
		prog:      coll.Programs["hids_steal_snap"],
		slots:     coll.Variables["hids_steal_slots"],
		count:     coll.Variables["hids_snap_count"],
		mechanism: mech,
		hasVMW:    hasVMW,
	}
	if s.prog == nil || s.slots == nil || s.count == nil {
		coll.Close()
		return nil, errors.New("thieu chuong trinh hoac bien toan cuc sau khi nap")
	}

	return s, nil
}

// assignPerCPUKsyms thay lenh nap dia chi ksym bang ld_imm64 kieu BPF_PSEUDO_BTF_ID
// tro toi BTF id that cua bien per-CPU trong vmlinux BTF, de bpf_per_cpu_ptr() nhan
// duoc con tro co kieu (PTR_TO_BTF_ID | MEM_PERCPU) thay vi mot so nguyen.
func assignPerCPUKsyms(prog *ebpf.ProgramSpec, names []string) error {
	kernelBTF, err := btf.LoadKernelSpec()
	if err != nil {
		return fmt.Errorf("doc BTF cua kernel: %w", err)
	}

	ids := make(map[string]btf.TypeID, len(names))
	for _, name := range names {
		var v *btf.Var
		if err := kernelBTF.TypeByName(name, &v); err != nil {
			return fmt.Errorf("tim BTF VAR %q trong vmlinux: %w", name, err)
		}
		id, err := kernelBTF.TypeID(v)
		if err != nil {
			return fmt.Errorf("lay BTF id cua %q: %w", name, err)
		}
		ids[name] = id
	}

	patched := make(map[string]int, len(names))
	iter := prog.Instructions.Iterate()
	for iter.Next() {
		ins := iter.Ins
		if !ins.OpCode.IsDWordLoad() {
			continue
		}
		name := ins.Reference()
		id, ok := ids[name]
		if !ok {
			continue
		}

		symbol := ins.Symbol()
		next := asm.Instruction{
			OpCode:   asm.LoadImmOp(asm.DWord),
			Dst:      ins.Dst,
			Src:      pseudoBTFID,
			Constant: int64(id),
		}
		if symbol != "" {
			next = next.WithSymbol(symbol)
		}
		*ins = next
		patched[name]++
	}

	var missing []string
	for _, name := range names {
		if patched[name] == 0 {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("khong tim thay lenh nap ksym cho: %s", strings.Join(missing, ", "))
	}

	return nil
}
