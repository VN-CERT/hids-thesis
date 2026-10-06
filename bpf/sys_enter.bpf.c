// SPDX-License-Identifier: GPL-2.0
//
// Chuong trinh BPF cua collector. Ghi mot ban ghi 48 byte cho moi sys_enter
// cua cac thread duoc chon, kem phan ra 5 thanh phan cua khoang giua hai
// sys_enter lien tiep: cpu, steal, irq, rq, vol.
//
// Cac chuong trinh trong file nay:
//   hids_sys_enter            tp_btf/sys_enter        phat ban ghi
//   hids_sched_switch         tp_btf/sched_switch     ranh gioi ON-CPU / OFF-CPU
//   hids_sched_wakeup         tp_btf/sched_wakeup     moc het ngu
//   hids_sched_wakeup_new     tp_btf/sched_wakeup_new moc het ngu (task moi)
//   hids_irq_<ten>_entry/exit tp_btf/<ten>_entry|exit bo cong don irq per-CPU
//
// Dinh nghia 5 thanh phan va bang flags nam trong .cursor/rules/hids.mdc;
// khong doi o day.
//
// Ve khai bao ksym: vmw_steal_time va runqueues la bien per-CPU cua kernel,
// doc qua bpf_this_cpu_ptr. Chung KHONG mang thuoc tinh __ksym vi loader Go
// github.com/cilium/ebpf v0.22.0 tu choi BTF Var co kieu trong section .ksyms.
// internal/stealbpf.AssignPerCPUKsyms tra BTF id that cua VAR trong
// /sys/kernel/btf/vmlinux va ghi vao lenh ld_imm64 duoi dang BPF_PSEUDO_BTF_ID,
// dung nhu libbpf lam cho typed ksym.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

/* So level to tien toi da duyet khi loc theo cgroup. */
#define HIDS_MAX_CGROUP_LEVEL 16

/* Bang flags chot trong .cursor/rules/hids.mdc. */
#define HIDS_F_FIRST          (1U << 0)
#define HIDS_F_GAP_BEFORE     (1U << 1)
#define HIDS_F_D_SLEEP        (1U << 2)
#define HIDS_F_MIGRATED       (1U << 3)
#define HIDS_F_OVERFLOW       (1U << 4)
#define HIDS_F_STEAL_FALLBACK (1U << 5)
#define HIDS_F_CLAMPED        (1U << 6)

/* bit8..15 chua so CPU luc sys_enter. User space tu choi chay neu may co hon
 * 256 CPU possible, nen 8 bit luon du. */
#define HIDS_F_CPU_SHIFT 8

/* Cac co co the con no tu truoc, chuyen sang ban ghi ke tiep. */
#define HIDS_PENDING_MASK \
	(HIDS_F_GAP_BEFORE | HIDS_F_D_SLEEP | HIDS_F_MIGRATED | HIDS_F_OVERFLOW | HIDS_F_CLAMPED)

/* include/linux/sched.h */
#define HIDS_TASK_RUNNING         0x0000
#define HIDS_TASK_UNINTERRUPTIBLE 0x0002

/* Loai doan OFF-CPU. */
#define HIDS_OFF_NONE     0
#define HIDS_OFF_RUNNABLE 1 /* bi tuoc CPU hoac vẫn RUNNING: ca doan la rq */
#define HIDS_OFF_SLEEP    2 /* di ngu: vol toi wakeup, roi rq toi luc chay lai */

/* Loai irq, dung de tach so lieu bao cao. */
/* Nguong phat hien khoang irq bat thuong, xem irq_out. */
#define HIDS_IRQ_MAX_NS (1000ull * 1000 * 1000)

#define HIDS_IRQ_HARD 0
#define HIDS_IRQ_SOFT 1
#define HIDS_IRQ_VEC  2

#define HIDS_U32_MAX 0xffffffffU

/* Ban ghi 48 byte, little-endian, dung dac ta trong hids.mdc. */
struct hids_rec {
	__u64 ts_enter;
	__u64 cgroup_id;
	__u32 tid;
	__u32 seq;
	__u16 syscall_nr;
	__u16 flags;
	__u32 cpu_ns;
	__u32 steal_ns;
	__u32 irq_ns;
	__u32 rq_ns;
	__u32 vol_us;
};

_Static_assert(sizeof(struct hids_rec) == 48, "ban ghi phai dung 48 byte");

/* Trang thai theo thread (muc B cua M3). */
struct hids_tstate {
	__u64 last_enter_ts; /* ts cua sys_enter truoc */

	/* Bo cong don cua khoang hien tai, ns. Khong xoa khi ghi hut. */
	__u64 acc_cpu;
	__u64 acc_steal;
	__u64 acc_irq;
	__u64 acc_rq;
	__u64 acc_vol;

	/* Moc bat dau doan ON-CPU hien tai. */
	__u64 on_ts;
	__u64 on_steal_raw; /* vmw_steal_time.clock, hoac rq->prev_steal_time khi fallback */
	__u64 on_irq_total; /* bo cong don irq cua CPU do luc bat dau doan */
	__u32 on_cpu;

	/* Trang thai OFF-CPU. */
	__u64 off_ts;
	__u64 wake_ts;
	__u8 off_kind;

	__u8 on_active;    /* dang o tren CPU? */
	__u8 seen;         /* da ghi duoc ban ghi nao cho thread nay chua */
	__u8 gap_pending;  /* lan ghi truoc that bai */
	__u16 pending_flags;
};

/* Bo cong don irq cua mot CPU (muc C cua M3). */
struct hids_irqstate {
	__u64 start_ns; /* moc luc vao o do sau 0 */
	__u64 total_ns; /* tong thoi gian irq, ba loai cong lai */
	__u64 hard_ns;
	__u64 soft_ns;
	__u64 vec_ns;
	__u64 odd_ns;  /* tong khoang bi loai vi qua dai, xem HIDS_IRQ_MAX_NS */
	__u32 odd_cnt; /* so khoang bi loai */
	__u32 depth;
	__u32 kind; /* loai cua muc ngoai cung dang chay */
};

/* Cau hinh do user space nap truoc khi nap chuong trinh. */
const volatile __u32 hids_self_tgid = 0;
const volatile __u8 hids_filter_cgroup = 0;
const volatile __u64 hids_tsc_khz = 0;
const volatile __u8 hids_steal_fallback = 0; /* dung rq->prev_steal_time */
const volatile __u8 hids_steal_off = 0;      /* khong do steal (khong co stealclock) */

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 1 << 26); /* user space ghi de theo -ringbuf-mb */
} hids_events SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 4096);
	__type(key, __u32); /* tgid */
	__type(value, __u8);
} hids_pids SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 1024);
	__type(key, __u64); /* cgroup id = so inode cua thu muc cgroup v2 */
	__type(value, __u8);
} hids_cgroups SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_TASK_STORAGE);
	__uint(map_flags, BPF_F_NO_PREALLOC);
	__type(key, int);
	__type(value, struct hids_tstate);
} hids_task_state SEC(".maps");

/* seq tang cho MOI lan dinh ghi, ke ca khi ring buffer day. */
struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u32);
} hids_seq SEC(".maps");

/* So ban ghi mat vi ring buffer day. */
struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} hids_drops SEC(".maps");

/* Bo cong don irq cua tung CPU. */
struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct hids_irqstate);
} hids_irq SEC(".maps");

extern const struct vmware_steal_time vmw_steal_time;
extern const struct rq runqueues;

static __always_inline struct hids_irqstate *irq_state(void)
{
	__u32 key0 = 0;

	return bpf_map_lookup_elem(&hids_irq, &key0);
}

/* irq_total_at tra ve bo cong don irq cua CPU hien tai tinh den thoi diem now,
 * CONG CA phan irq dang chay do. sched_switch co the xay ra ngay trong duong
 * thoat irq (preempt_schedule_irq), khi do phan irq da chay nhung chua duoc
 * cong vao total_ns; neu bo qua thi phan do bi tinh sang cpu. */
static __always_inline __u64 irq_total_at(struct hids_irqstate *is, __u64 now)
{
	__u64 total;

	if (!is)
		return 0;
	total = is->total_ns;
	if (is->depth > 0 && now > is->start_ns)
		total += now - is->start_ns;
	return total;
}

/* steal_raw_now doc bo dem steal tho cua CPU hien tai.
 * Khong fallback: vmw_steal_time.clock, don vi chu ky vTSC.
 * Fallback:       rq->prev_steal_time, don vi ns. */
static __always_inline __u64 steal_raw_now(void)
{
	if (hids_steal_off)
		return 0;

	if (hids_steal_fallback) {
		const struct rq *rq = bpf_this_cpu_ptr(&runqueues);

		return rq->prev_steal_time;
	}

	{
		const struct vmware_steal_time *st = bpf_this_cpu_ptr(&vmw_steal_time);

		return st->clock;
	}
}

/* steal_delta_ns quy mot muc tang cua bo dem steal ra ns. */
static __always_inline __u64 steal_delta_ns(__u64 raw_delta)
{
	if (hids_steal_off)
		return 0;
	if (hids_steal_fallback)
		return raw_delta; /* da la ns */
	if (hids_tsc_khz == 0)
		return 0;
	/* chu ky x 1e6 / tsc_khz. Chan tran: 1.8e19 / 1e6 = 1.8e13 chu ky,
	 * tuong duong khoang 2.5 gio steal lien tuc tren mot doan ON-CPU. */
	if (raw_delta > (1ULL << 43))
		return 0;
	return raw_delta * 1000000ULL / hids_tsc_khz;
}

/* open_on_cpu ghi moc bat dau mot doan ON-CPU tai thoi diem now. */
static __always_inline void open_on_cpu(struct hids_tstate *st, __u64 now, __u32 cpu)
{
	st->on_ts = now;
	st->on_steal_raw = steal_raw_now();
	st->on_irq_total = irq_total_at(irq_state(), now);
	st->on_cpu = cpu;
	st->on_active = 1;
}

/* close_on_cpu dong doan ON-CPU tai now va cong vao cac bo cong don.
 * Phai goi tren dung CPU ma doan do dang chay. */
static __always_inline void close_on_cpu(struct hids_tstate *st, __u64 now)
{
	__u64 dur, steal_ns, irq_ns, raw, irq_total;

	if (!st->on_active)
		return;
	st->on_active = 0;

	dur = now > st->on_ts ? now - st->on_ts : 0;

	raw = steal_raw_now();
	steal_ns = raw > st->on_steal_raw ? steal_delta_ns(raw - st->on_steal_raw) : 0;

	irq_total = irq_total_at(irq_state(), now);
	irq_ns = irq_total > st->on_irq_total ? irq_total - st->on_irq_total : 0;

	st->acc_steal += steal_ns;
	st->acc_irq += irq_ns;

	if (steal_ns + irq_ns > dur) {
		/* Khong du do dai doan de chua ca steal va irq. Theo dinh nghia:
		 * cpu = 0 va bat co CLAMPED; steal va irq giu nguyen gia tri do. */
		st->pending_flags |= HIDS_F_CLAMPED;
	} else {
		st->acc_cpu += dur - steal_ns - irq_ns;
	}
}

static __always_inline bool cgroup_selected(void)
{
	__u64 id = bpf_get_current_cgroup_id();

	if (bpf_map_lookup_elem(&hids_cgroups, &id))
		return true;

	for (int level = 0; level < HIDS_MAX_CGROUP_LEVEL; level++) {
		__u64 anc = bpf_get_current_ancestor_cgroup_id(level);

		/* 0 nghia la level sau hon do sau hien tai, khong con to tien nao. */
		if (!anc)
			break;
		if (bpf_map_lookup_elem(&hids_cgroups, &anc))
			return true;
	}

	return false;
}

/* sat32 ep mot gia tri ns ve u32, bao hoa va bat OVERFLOW khi tran. */
static __always_inline __u32 sat32(__u64 v, __u16 *flags)
{
	if (v > HIDS_U32_MAX) {
		*flags |= HIDS_F_OVERFLOW;
		return HIDS_U32_MAX;
	}
	return (__u32)v;
}

SEC("tp_btf/sys_enter")
int BPF_PROG(hids_sys_enter, struct pt_regs *regs, long id)
{
	__u64 pid_tgid = bpf_get_current_pid_tgid();
	__u32 tgid = pid_tgid >> 32;
	__u32 tid = (__u32)pid_tgid;
	__u32 key0 = 0;
	struct hids_tstate *st;
	struct hids_rec *rec;
	__u32 *seqp;
	__u64 ts;
	__u32 cpu;
	__u16 flags = 0;

	if (tgid == hids_self_tgid)
		return 0;

	if (!bpf_map_lookup_elem(&hids_pids, &tgid)) {
		if (!hids_filter_cgroup)
			return 0;
		if (!cgroup_selected())
			return 0;
	}

	ts = bpf_ktime_get_ns();
	cpu = bpf_get_smp_processor_id();
	flags |= (__u16)((cpu & 0xff) << HIDS_F_CPU_SHIFT);
	if (hids_steal_fallback)
		flags |= HIDS_F_STEAL_FALLBACK;

	/* Chi o day moi tao task storage. sched_switch va sched_wakeup chi tra. */
	st = bpf_task_storage_get(&hids_task_state, bpf_get_current_task_btf(), NULL,
				  BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (!st) {
		/* Khong co trang thai thi khong do duoc thanh phan nao; van dem
		 * lan dinh ghi de so lieu mat mat khong bi lech. */
		seqp = bpf_map_lookup_elem(&hids_seq, &key0);
		if (seqp)
			*seqp += 1;
		return 0;
	}

	if (!st->seen) {
		/* Ban ghi dau tien cua thread: chua co khoang nao truoc do. */
		flags |= HIDS_F_FIRST;
	} else {
		/* Dong doan ON-CPU dang chay tai sys_enter nay. */
		close_on_cpu(st, ts);
		flags |= st->pending_flags & HIDS_PENDING_MASK;
		if (st->gap_pending)
			flags |= HIDS_F_GAP_BEFORE;
	}

	seqp = bpf_map_lookup_elem(&hids_seq, &key0);
	if (!seqp)
		return 0;
	*seqp += 1;

	rec = bpf_ringbuf_reserve(&hids_events, sizeof(*rec), 0);
	if (!rec) {
		__u64 *drops = bpf_map_lookup_elem(&hids_drops, &key0);

		if (drops)
			*drops += 1;
		st->gap_pending = 1;
		/* Giu nguyen acc_* va last_enter_ts: ban ghi thanh cong ke tiep
		 * mang thanh phan cua toan bo khoang gop. Mo lai doan ON-CPU de
		 * khong bo sot thoi gian. */
		if (!st->seen) {
			st->seen = 1;
			st->last_enter_ts = ts;
		}
		open_on_cpu(st, ts, cpu);
		return 0;
	}

	rec->ts_enter = ts;
	rec->cgroup_id = bpf_get_current_cgroup_id();
	rec->tid = tid;
	rec->seq = *seqp;
	rec->syscall_nr = (__u16)id;

	if (flags & HIDS_F_FIRST) {
		rec->cpu_ns = 0;
		rec->steal_ns = 0;
		rec->irq_ns = 0;
		rec->rq_ns = 0;
		rec->vol_us = 0;
	} else {
		rec->cpu_ns = sat32(st->acc_cpu, &flags);
		rec->steal_ns = sat32(st->acc_steal, &flags);
		rec->irq_ns = sat32(st->acc_irq, &flags);
		rec->rq_ns = sat32(st->acc_rq, &flags);
		rec->vol_us = sat32((st->acc_vol + 500) / 1000, &flags);
	}
	rec->flags = flags;

	bpf_ringbuf_submit(rec, 0);

	/* Bat dau khoang moi. */
	st->seen = 1;
	st->gap_pending = 0;
	st->pending_flags = 0;
	st->last_enter_ts = ts;
	st->acc_cpu = 0;
	st->acc_steal = 0;
	st->acc_irq = 0;
	st->acc_rq = 0;
	st->acc_vol = 0;
	open_on_cpu(st, ts, cpu);

	return 0;
}

SEC("tp_btf/sched_switch")
int BPF_PROG(hids_sched_switch, bool preempt, struct task_struct *prev,
	     struct task_struct *next, unsigned int prev_state)
{
	__u64 now = bpf_ktime_get_ns();
	__u32 cpu = bpf_get_smp_processor_id();
	struct hids_tstate *st;

	/* prev roi CPU. Khong tao storage o day. */
	st = bpf_task_storage_get(&hids_task_state, prev, NULL, 0);
	if (st && st->seen) {
		close_on_cpu(st, now);
		st->off_ts = now;
		st->wake_ts = 0;
		if (preempt || prev_state == HIDS_TASK_RUNNING) {
			st->off_kind = HIDS_OFF_RUNNABLE;
		} else {
			st->off_kind = HIDS_OFF_SLEEP;
			if (prev_state & HIDS_TASK_UNINTERRUPTIBLE)
				st->pending_flags |= HIDS_F_D_SLEEP;
		}
	}

	/* next duoc chay lai. */
	st = bpf_task_storage_get(&hids_task_state, next, NULL, 0);
	if (st && st->seen) {
		if (st->off_kind == HIDS_OFF_RUNNABLE) {
			if (now > st->off_ts)
				st->acc_rq += now - st->off_ts;
		} else if (st->off_kind == HIDS_OFF_SLEEP) {
			__u64 w = st->wake_ts;

			if (w == 0 || w < st->off_ts || w > now) {
				/* Khong co moc wakeup dung dan: tinh ca doan vao
				 * vol va bat CLAMPED. */
				if (now > st->off_ts)
					st->acc_vol += now - st->off_ts;
				st->pending_flags |= HIDS_F_CLAMPED;
			} else {
				st->acc_vol += w - st->off_ts;
				st->acc_rq += now - w;
			}
		}
		st->off_kind = HIDS_OFF_NONE;
		st->wake_ts = 0;

		if (cpu != st->on_cpu)
			st->pending_flags |= HIDS_F_MIGRATED;

		open_on_cpu(st, now, cpu);
	}

	return 0;
}

/* mark_wakeup ghi moc het ngu, chi mot lan cho moi doan OFF-CPU. */
static __always_inline void mark_wakeup(struct task_struct *p)
{
	__u64 now = bpf_ktime_get_ns();
	struct hids_tstate *st;

	st = bpf_task_storage_get(&hids_task_state, p, NULL, 0);
	if (!st || !st->seen)
		return;
	if (st->off_kind != HIDS_OFF_SLEEP)
		return;
	/* sched_wakeup co the chay song song voi sched_switch tren CPU khac;
	 * chi ghi khi o day con trong. */
	__sync_val_compare_and_swap(&st->wake_ts, 0, now);
}

SEC("tp_btf/sched_wakeup")
int BPF_PROG(hids_sched_wakeup, struct task_struct *p)
{
	mark_wakeup(p);
	return 0;
}

SEC("tp_btf/sched_wakeup_new")
int BPF_PROG(hids_sched_wakeup_new, struct task_struct *p)
{
	mark_wakeup(p);
	return 0;
}

/* ---- Bo cong don irq per-CPU (muc C) ---- */

static __always_inline void irq_in(__u32 kind)
{
	struct hids_irqstate *is = irq_state();

	if (!is)
		return;
	if (is->depth == 0) {
		is->start_ns = bpf_ktime_get_ns();
		is->kind = kind;
	}
	is->depth += 1;
}

static __always_inline void irq_out(void)
{
	struct hids_irqstate *is = irq_state();
	__u64 now, d;

	if (!is)
		return;
	/* Co the nap chuong trinh giua mot irq dang chay: khi do thay exit ma
	 * khong co entry. Bo qua, khong tru am. */
	if (is->depth == 0)
		return;
	is->depth -= 1;
	if (is->depth != 0)
		return;

	now = bpf_ktime_get_ns();
	if (now <= is->start_ns)
		return;
	d = now - is->start_ns;
	/* Chan an toan, KHONG phai hang so vat ly: do sau irq la mot phep
	 * doc-sua-ghi tren map per-CPU, mot hardirq long vao giua phep do co the
	 * lam mat mot lan tang. Khi do mot exit sau nay se dong so voi moc cu va
	 * sinh ra khoang rat dai. Loai khoang do ra va dem lai de bao cao, thay
	 * vi cong vao lam sai so lieu. Bo dem nay phai bang 0; khac 0 la co loi
	 * can bao kien truc su. */
	if (d > HIDS_IRQ_MAX_NS) {
		is->odd_ns += d;
		is->odd_cnt += 1;
		return;
	}
	is->total_ns += d;
	switch (is->kind) {
	case HIDS_IRQ_HARD:
		is->hard_ns += d;
		break;
	case HIDS_IRQ_SOFT:
		is->soft_ns += d;
		break;
	default:
		is->vec_ns += d;
		break;
	}
}

/* HIDS_IRQ_PAIR sinh hai chuong trinh cho mot cap tracepoint entry va exit. */
#define HIDS_IRQ_PAIR(tp, kind)                      \
	SEC("tp_btf/" #tp "_entry")                  \
	int BPF_PROG(hids_irq_##tp##_entry)          \
	{                                            \
		irq_in(kind);                        \
		return 0;                            \
	}                                            \
	SEC("tp_btf/" #tp "_exit")                   \
	int BPF_PROG(hids_irq_##tp##_exit)           \
	{                                            \
		irq_out();                           \
		return 0;                            \
	}

/* irq: */
HIDS_IRQ_PAIR(irq_handler, HIDS_IRQ_HARD)
HIDS_IRQ_PAIR(softirq, HIDS_IRQ_SOFT)

/* irq_vectors: moi cap entry/exit co trong
 * /sys/kernel/tracing/events/irq_vectors/ tren kernel 6.8.0-142-generic. */
HIDS_IRQ_PAIR(local_timer, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(reschedule, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(call_function, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(call_function_single, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(irq_work, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(x86_platform_ipi, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(error_apic, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(spurious_apic, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(thermal_apic, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(threshold_apic, HIDS_IRQ_VEC)
HIDS_IRQ_PAIR(deferred_error_apic, HIDS_IRQ_VEC)
