// SPDX-License-Identifier: GPL-2.0
//
// hids_steal_snap: doc bo dem steal cua tung CPU bang bpf_per_cpu_ptr() tren
// hai bien per-CPU cua kernel.
//
// Nguon do:
//   vmw_steal_time.clock       bo dem steal cua VMware stealclock, don vi chu ky vTSC
//                              (arch/x86/kernel/cpu/vmware.c). User space quy doi ra ns.
//   runqueues.prev_steal_time  bo dem steal cua scheduler, don vi ns, cap nhat theo tick.
//
// Ve khai bao ksym: hai bien duoi day la typed ksym (bien per-CPU cua kernel,
// doc qua bpf_per_cpu_ptr). Chung KHONG mang thuoc tinh __ksym vi loader Go
// github.com/cilium/ebpf v0.22.0 tu choi BTF Var co kieu trong section .ksyms
// ("data section .ksyms: expected vmw_steal_time to be *Void, not *btf.Var:
// not supported"). Thay vao do user space tra BTF id that cua VAR trong
// /sys/kernel/btf/vmlinux va ghi vao lenh ld_imm64 duoi dang BPF_PSEUDO_BTF_ID,
// dung nhu libbpf lam cho typed ksym. Kieu du lieu van do verifier kiem tra
// theo BTF cua kernel, offset truong do CO-RE sinh.
//
// Build voi -DHIDS_NO_VMW de bo hoan toan vmw_steal_time (dung khi ksym do
// khong nap duoc), chi con rq->prev_steal_time.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>

char LICENSE[] SEC("license") = "GPL";

#define HIDS_MAX_CPUS 64

#define HIDS_SLOT_VMW (1U << 0) /* vmw_raw doc duoc */
#define HIDS_SLOT_RQ  (1U << 1) /* rq_steal_ns doc duoc */

struct hids_steal_slot {
	__u64 ts_ns;       /* bpf_ktime_get_ns() tai luc doc CPU nay */
	__u64 vmw_raw;     /* vmw_steal_time.clock, chu ky vTSC */
	__u64 rq_steal_ns; /* runqueues.prev_steal_time, ns */
	__u32 flags;
	__u32 cpu;
};

/* Context truyen tu user space qua BPF_PROG_RUN (ctx_in). */
struct hids_snap_args {
	__u32 nr_cpus;
	__u32 pad;
};

/* Mang toan cuc trong .bss, user space doc bang Variables API. */
struct hids_steal_slot hids_steal_slots[HIDS_MAX_CPUS];
__u32 hids_snap_nr_cpus = 0;
__u64 hids_snap_count = 0;

#ifndef HIDS_NO_VMW
extern const struct vmware_steal_time vmw_steal_time;
#endif
extern const struct rq runqueues;

SEC("syscall")
int hids_steal_snap(struct hids_snap_args *args)
{
	__u32 nr = args->nr_cpus;
	__u32 i;

	if (nr > HIDS_MAX_CPUS)
		nr = HIDS_MAX_CPUS;

	for (i = 0; i < HIDS_MAX_CPUS; i++) {
		struct hids_steal_slot *slot;
		const struct rq *rq;
		__u64 vmw_raw = 0;
		__u64 rq_steal_ns = 0;
		__u32 flags = 0;

		if (i >= nr)
			break;

#ifndef HIDS_NO_VMW
		{
			const struct vmware_steal_time *st;

			st = bpf_per_cpu_ptr(&vmw_steal_time, i);
			if (st) {
				vmw_raw = st->clock;
				flags |= HIDS_SLOT_VMW;
			}
		}
#endif

		rq = bpf_per_cpu_ptr(&runqueues, i);
		if (rq) {
			rq_steal_ns = rq->prev_steal_time;
			flags |= HIDS_SLOT_RQ;
		}

		slot = &hids_steal_slots[i];
		slot->vmw_raw = vmw_raw;
		slot->rq_steal_ns = rq_steal_ns;
		slot->flags = flags;
		slot->cpu = i;
		slot->ts_ns = bpf_ktime_get_ns();
	}

	hids_snap_nr_cpus = nr;
	hids_snap_count++;
	return 0;
}
