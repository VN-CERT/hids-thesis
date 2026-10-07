// SPDX-License-Identifier: GPL-2.0
//
// Chuong trinh BPF cua collector. Ghi mot ban ghi 56 byte cho moi sys_enter
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
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

/* bpf_ringbuf_* flags; user space doc theo nhịp khi dung BPF_RB_NO_WAKEUP. */
#ifndef BPF_RB_NO_WAKEUP
#define BPF_RB_NO_WAKEUP (1ULL)
#endif

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

#define HIDS_U32_MAX 0xffffffffU

/* Ban ghi 56 byte, little-endian, dung dac ta trong hids.mdc. */
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
	__u32 steal_off_ns;
	__u32 reserved;
};

_Static_assert(sizeof(struct hids_rec) == 56, "ban ghi phai dung 56 byte");

/* Trang thai theo thread (muc B cua M3). */
struct hids_tstate {
	__u64 last_enter_ts; /* ts cua sys_enter truoc */

	/* Bo cong don cua khoang hien tai, ns. Khong xoa khi ghi hut. */
	__u64 acc_cpu;
	__u64 acc_steal;
	__u64 acc_irq;
	__u64 acc_rq;
	__u64 acc_vol;
	__u64 acc_steal_off; /* steal tren vCPU khi OFF-CPU, khong nam trong tong dt */

	/* Moc bat dau doan ON-CPU hien tai. */
	__u64 on_ts;
	__u64 on_steal_raw; /* vmw_steal_time.clock, hoac rq->prev_steal_time khi fallback */
	__u64 on_irq_total; /* bo cong don irq cua CPU do luc bat dau doan */
	__u32 on_cpu;

	/* Trang thai OFF-CPU. */
	__u64 off_ts;
	__u64 wake_ts;
	__u32 off_cpu;       /* CPU luc switch-out (phan ngu) */
	__u32 target_cpu;    /* CPU cho phan cho rq */
	__u64 off_steal_raw; /* vmw tho tren off_cpu luc switch-out */
	__u64 rq_steal_raw;  /* vmw tho tren target_cpu luc bat dau cho rq */
	__u8 off_kind;

	__u8 on_active;    /* dang o tren CPU? */
	__u8 seen;         /* da ghi duoc ban ghi nao cho thread nay chua */
	__u8 gap_pending;  /* lan ghi truoc that bai */
	__u16 pending_flags;
};

/* Bo cong don irq cua mot CPU (muc C cua M3, viet lai theo phuong an (c) cua
 * kien truc su o R004).
 *
 * Khong co bien do sau dung chung nua. Moi loai giu trang thai RIENG, va moi
 * truong chi do chuong trinh cua dung loai do ghi, nen khong co phep doc-sua-ghi
 * nao bi mot loai khac chen vao giua.
 *
 * Co so: tren mot CPU, hard va vector khong long vao nhau va khong tu long;
 * soft khong tu long; hard va vector co the long vao trong soft.
 *
 * Tranh dem hai lan: luc soft vao, chup (hard_ns + vec_ns). Luc soft ra,
 * phan long = (hard_ns + vec_ns) hien tai tru anh chup, va
 * soft_excl_ns += (ra - vao) - phan long.
 *
 * Thanh phan irq cua thread = hard_ns + vec_ns + soft_excl_ns.
 * soft_raw_ns chi dung de doi chieu voi softirqs-bpfcc (bcc tinh ca phan long). */
struct hids_irqstate {
	__u64 hard_start; /* 0 = khong hoat dong */
	__u64 hard_start_steal;
	__u64 hard_ns;

	__u64 vec_start;
	__u64 vec_start_steal;
	__u64 vec_ns;

	__u64 soft_start;
	__u64 soft_start_steal;
	__u64 soft_snap;     /* (hard_ns + vec_ns) luc soft vao */
	__u64 soft_raw_ns;   /* tong (ra - vao), ke ca phan long */
	__u64 soft_excl_ns;  /* soft_raw tru phan long */

	__u64 odd_ns;  /* tong khoang bi loai vi qua dai, xem HIDS_IRQ_MAX_NS */
	__u32 odd_cnt; /* so khoang bi loai */
	__u32 pad;
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
	__uint(max_entries, 4096);
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

/* irq_dur tra ve do dai mot khoang irq, hoac 0 neu khoang do bat thuong. */
static __always_inline __u64 irq_dur(struct hids_irqstate *is, __u64 start, __u64 now)
{
	__u64 d;

	if (now <= start)
		return 0;
	d = now - start;
	if (d > HIDS_IRQ_MAX_NS) {
		is->odd_ns += d;
		is->odd_cnt += 1;
		return 0;
	}
	return d;
}

/* steal_raw_on_cpu doc bo dem steal tho cua mot CPU (doc tu xa). */
static __always_inline __u64 steal_raw_on_cpu(__u32 cpu)
{
	if (hids_steal_off)
		return 0;

	if (hids_steal_fallback) {
		const struct rq *rq = bpf_per_cpu_ptr(&runqueues, cpu);

		return rq ? rq->prev_steal_time : 0;
	}

	{
		const struct vmware_steal_time *st = bpf_per_cpu_ptr(&vmw_steal_time, cpu);

		return st ? st->clock : 0;
	}
}

/* steal_raw_now doc bo dem steal tho cua CPU hien tai.
 * Khong fallback: vmw_steal_time.clock, don vi chu ky vTSC.
 * Fallback:       rq->prev_steal_time, don vi ns. */
static __always_inline __u64 steal_raw_now(void)
{
	return steal_raw_on_cpu(bpf_get_smp_processor_id());
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
	if (raw_delta > (1ULL << 43))
		return 0;
	return raw_delta * 1000000ULL / hids_tsc_khz;
}

static __always_inline void steal_off_add(struct hids_tstate *st, __u64 delta)
{
	if (!delta)
		return;
	st->acc_steal_off += delta;
}

static __always_inline void steal_off_close_cpu(struct hids_tstate *st, __u32 cpu, __u64 raw_start)
{
	__u64 raw_now, delta;

	if (hids_steal_off)
		return;
	raw_now = steal_raw_on_cpu(cpu);
	if (raw_now <= raw_start)
		return;
	delta = steal_delta_ns(raw_now - raw_start);
	steal_off_add(st, delta);
}

/* irq_progress_ns: do dai irq dang do, tru delta steal tren CPU hien tai. */
static __always_inline __u64 irq_progress_ns(__u64 start, __u64 start_steal, __u64 now)
{
	__u64 d, steal_ns, raw;

	if (!start || now <= start)
		return 0;
	d = now - start;
	raw = steal_raw_now();
	steal_ns = raw > start_steal ? steal_delta_ns(raw - start_steal) : 0;
	if (steal_ns >= d)
		return 0;
	return d - steal_ns;
}

/* irq_interval_ns: dong mot khoang irq da ket thuc, tru steal. */
static __always_inline __u64 irq_interval_ns(struct hids_irqstate *is, __u64 start,
					     __u64 start_steal, __u64 now)
{
	__u64 d, steal_ns, raw;

	d = irq_dur(is, start, now);
	if (!d)
		return 0;
	raw = steal_raw_now();
	steal_ns = raw > start_steal ? steal_delta_ns(raw - start_steal) : 0;
	if (steal_ns >= d)
		return 0;
	return d - steal_ns;
}

/* irq_total_at tra ve bo cong don irq cua CPU hien tai tinh den thoi diem now,
 * CONG CA phan dang do cua tung loai dang hoat dong. sched_switch co the xay ra
 * ngay trong duong thoat irq (preempt_schedule_irq), khi do phan irq da chay
 * nhung chua duoc cong vao bo cong don; neu bo qua thi phan do bi tinh sang cpu.
 *
 * Voi soft dang do, phan long cung duoc tru theo dung cach nhu luc soft ra. */
static __always_inline __u64 irq_total_at(struct hids_irqstate *is, __u64 now)
{
	__u64 hv, total;

	if (!is)
		return 0;

	hv = is->hard_ns + is->vec_ns;
	if (is->hard_start && now > is->hard_start)
		hv += irq_progress_ns(is->hard_start, is->hard_start_steal, now);
	if (is->vec_start && now > is->vec_start)
		hv += irq_progress_ns(is->vec_start, is->vec_start_steal, now);

	total = hv + is->soft_excl_ns;

	if (is->soft_start && now > is->soft_start) {
		__u64 dur = irq_progress_ns(is->soft_start, is->soft_start_steal, now);
		__u64 nested = hv > is->soft_snap ? hv - is->soft_snap : 0;

		if (dur > nested)
			total += dur - nested;
	}

	return total;
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

	return bpf_map_lookup_elem(&hids_cgroups, &id) != NULL;
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
		rec->steal_off_ns = 0;
	} else {
		rec->cpu_ns = sat32(st->acc_cpu, &flags);
		rec->steal_ns = sat32(st->acc_steal, &flags);
		rec->irq_ns = sat32(st->acc_irq, &flags);
		rec->rq_ns = sat32(st->acc_rq, &flags);
		rec->vol_us = sat32((st->acc_vol + 500) / 1000, &flags);
		rec->steal_off_ns = sat32(st->acc_steal_off, &flags);
	}
	rec->reserved = 0;
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
	st->acc_steal_off = 0;
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
		st->off_cpu = cpu;
		st->off_steal_raw = steal_raw_on_cpu(cpu);
		if (preempt || prev_state == HIDS_TASK_RUNNING) {
			st->off_kind = HIDS_OFF_RUNNABLE;
			st->target_cpu = cpu;
			st->rq_steal_raw = st->off_steal_raw;
		} else {
			st->off_kind = HIDS_OFF_SLEEP;
			if (prev_state & HIDS_TASK_UNINTERRUPTIBLE)
				st->pending_flags |= HIDS_F_D_SLEEP;
		}
	}

	/* next duoc chay lai. */
	st = bpf_task_storage_get(&hids_task_state, next, NULL, 0);
	if (st && st->seen) {
		steal_off_close_cpu(st, st->target_cpu, st->rq_steal_raw);
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
	/* Phan ngu: steal tren off_cpu tu switch-out den wakeup. */
	steal_off_close_cpu(st, st->off_cpu, st->off_steal_raw);
	st->target_cpu = (__u32)BPF_CORE_READ(p, wake_cpu);
	st->rq_steal_raw = steal_raw_on_cpu(st->target_cpu);
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

static __always_inline void irq_hard_in(void)
{
	struct hids_irqstate *is = irq_state();

	if (is) {
		is->hard_start = bpf_ktime_get_ns();
		is->hard_start_steal = steal_raw_now();
	}
}

static __always_inline void irq_hard_out(void)
{
	struct hids_irqstate *is = irq_state();
	__u64 start;

	if (!is)
		return;
	start = is->hard_start;
	/* Co the nap chuong trinh giua mot irq dang chay: thay exit ma khong co
	 * entry. Bo qua. */
	if (!start)
		return;
	is->hard_start = 0;
	is->hard_ns += irq_interval_ns(is, start, is->hard_start_steal, bpf_ktime_get_ns());
}

static __always_inline void irq_vec_in(void)
{
	struct hids_irqstate *is = irq_state();

	if (is) {
		is->vec_start = bpf_ktime_get_ns();
		is->vec_start_steal = steal_raw_now();
	}
}

static __always_inline void irq_vec_out(void)
{
	struct hids_irqstate *is = irq_state();
	__u64 start;

	if (!is)
		return;
	start = is->vec_start;
	if (!start)
		return;
	is->vec_start = 0;
	is->vec_ns += irq_interval_ns(is, start, is->vec_start_steal, bpf_ktime_get_ns());
}

static __always_inline void irq_soft_in(void)
{
	struct hids_irqstate *is = irq_state();

	if (!is)
		return;
	is->soft_snap = is->hard_ns + is->vec_ns;
	is->soft_start = bpf_ktime_get_ns();
	is->soft_start_steal = steal_raw_now();
}

static __always_inline void irq_soft_out(void)
{
	struct hids_irqstate *is = irq_state();
	__u64 start, d, hv, nested;

	if (!is)
		return;
	start = is->soft_start;
	if (!start)
		return;
	is->soft_start = 0;

	d = irq_interval_ns(is, start, is->soft_start_steal, bpf_ktime_get_ns());
	if (!d)
		return;

	is->soft_raw_ns += d;

	/* Hard va vector long ben trong soft da duoc cong vao hard_ns/vec_ns
	 * roi, nen phai tru ra de khong dem hai lan. */
	hv = is->hard_ns + is->vec_ns;
	nested = hv > is->soft_snap ? hv - is->soft_snap : 0;
	if (d > nested)
		is->soft_excl_ns += d - nested;
}

/* HIDS_IRQ_PAIR sinh hai chuong trinh cho mot cap tracepoint entry va exit. */
#define HIDS_IRQ_PAIR(tp, kind)                      \
	SEC("tp_btf/" #tp "_entry")                  \
	int BPF_PROG(hids_irq_##tp##_entry)          \
	{                                            \
		irq_##kind##_in();                   \
		return 0;                            \
	}                                            \
	SEC("tp_btf/" #tp "_exit")                   \
	int BPF_PROG(hids_irq_##tp##_exit)           \
	{                                            \
		irq_##kind##_out();                  \
		return 0;                            \
	}

/* irq: */
HIDS_IRQ_PAIR(irq_handler, hard)
HIDS_IRQ_PAIR(softirq, soft)

/* irq_vectors: moi cap entry/exit co trong
 * /sys/kernel/tracing/events/irq_vectors/ tren kernel 6.8.0-142-generic. */
HIDS_IRQ_PAIR(local_timer, vec)
HIDS_IRQ_PAIR(reschedule, vec)
HIDS_IRQ_PAIR(call_function, vec)
HIDS_IRQ_PAIR(call_function_single, vec)
HIDS_IRQ_PAIR(irq_work, vec)
HIDS_IRQ_PAIR(x86_platform_ipi, vec)
HIDS_IRQ_PAIR(error_apic, vec)
HIDS_IRQ_PAIR(spurious_apic, vec)
HIDS_IRQ_PAIR(thermal_apic, vec)
HIDS_IRQ_PAIR(threshold_apic, vec)
HIDS_IRQ_PAIR(deferred_error_apic, vec)
