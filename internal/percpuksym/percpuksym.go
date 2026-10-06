// Package percpuksym nap dia chi cua bien per-CPU cua kernel (typed ksym) vao
// chuong trinh BPF.
//
// Ly do phai lam tay: loader Go github.com/cilium/ebpf v0.22.0 tu choi BTF Var
// co kieu trong section .ksyms ("data section .ksyms: expected vmw_steal_time
// to be *Void, not *btf.Var: not supported"), nen khong dung duoc thuoc tinh
// __ksym. Thay vao do mã BPF khai bao extern khong co __ksym, roi o day ta tra
// BTF id that cua VAR trong /sys/kernel/btf/vmlinux va ghi vao lenh ld_imm64
// duoi dang BPF_PSEUDO_BTF_ID, dung nhu libbpf lam cho typed ksym. Nho vay
// bpf_per_cpu_ptr() va bpf_this_cpu_ptr() nhan duoc con tro co kieu
// (PTR_TO_BTF_ID | MEM_PERCPU) thay vi mot so nguyen, va verifier van kiem tra
// kieu du lieu theo BTF cua kernel.
package percpuksym

import (
	"fmt"
	"strings"

	"github.com/cilium/ebpf"
	"github.com/cilium/ebpf/asm"
	"github.com/cilium/ebpf/btf"
)

// pseudoBTFID la BPF_PSEUDO_BTF_ID (src_reg = 3 cua lenh ld_imm64).
// cilium/ebpf khong co hang so nay nen dinh nghia tai day.
const pseudoBTFID = asm.Register(3)

// Resolver giu BTF id cua cac bien per-CPU can nap.
type Resolver struct {
	names []string
	ids   map[string]btf.TypeID
}

// NewResolver tra BTF id cua tung ten trong BTF cua kernel dang chay.
func NewResolver(names []string) (*Resolver, error) {
	kernelBTF, err := btf.LoadKernelSpec()
	if err != nil {
		return nil, fmt.Errorf("doc BTF cua kernel: %w", err)
	}

	ids := make(map[string]btf.TypeID, len(names))
	for _, name := range names {
		var v *btf.Var
		if err := kernelBTF.TypeByName(name, &v); err != nil {
			return nil, fmt.Errorf("tim BTF VAR %q trong vmlinux: %w", name, err)
		}
		id, err := kernelBTF.TypeID(v)
		if err != nil {
			return nil, fmt.Errorf("lay BTF id cua %q: %w", name, err)
		}
		ids[name] = id
	}

	return &Resolver{names: names, ids: ids}, nil
}

// Patch thay moi lenh nap dia chi ksym trong mot chuong trinh va tra ve so lan
// thay cho tung ten.
func (r *Resolver) Patch(prog *ebpf.ProgramSpec) map[string]int {
	patched := make(map[string]int, len(r.names))

	iter := prog.Instructions.Iterate()
	for iter.Next() {
		ins := iter.Ins
		if !ins.OpCode.IsDWordLoad() {
			continue
		}
		name := ins.Reference()
		id, ok := r.ids[name]
		if !ok {
			continue
		}

		// Dung lai nhan cua lenh cu: viec dung lai struct Instruction se
		// xoa phan metadata ksym noi bo cua cilium/ebpf.
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

	return patched
}

// PatchProgram thay ksym trong mot chuong trinh va bao loi neu co ten nao
// khong tim thay lenh nap.
func PatchProgram(prog *ebpf.ProgramSpec, names []string) error {
	r, err := NewResolver(names)
	if err != nil {
		return err
	}
	return requireAll(r, r.Patch(prog))
}

// PatchCollection thay ksym trong MOI chuong trinh cua spec. Can thiet khi ham
// doc ksym la __always_inline va duoc nhung vao nhieu chuong trinh. Moi ten
// phai duoc thay o it nhat mot chuong trinh.
func PatchCollection(spec *ebpf.CollectionSpec, names []string) error {
	r, err := NewResolver(names)
	if err != nil {
		return err
	}

	total := make(map[string]int, len(names))
	for _, prog := range spec.Programs {
		for name, n := range r.Patch(prog) {
			total[name] += n
		}
	}
	return requireAll(r, total)
}

func requireAll(r *Resolver, patched map[string]int) error {
	var missing []string
	for _, name := range r.names {
		if patched[name] == 0 {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("khong tim thay lenh nap ksym cho: %s", strings.Join(missing, ", "))
	}
	return nil
}
