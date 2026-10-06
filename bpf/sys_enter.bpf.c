// SPDX-License-Identifier: GPL-2.0
//
// hids_sys_enter: ghi mot ban ghi 48 byte cho moi sys_enter cua cac thread duoc chon.
//
// Bo loc xet theo thu tu re tien nhat truoc:
//   1. bo qua tien trinh cua chinh collector (tgid do user space nap vao);
//   2. giu lai neu tgid nam trong tap PID dich;
//   3. hoac cgroup hien tai / mot cgroup to tien nam trong tap cgroup dich.
//
// M2 chi do thoi diem sys_enter; cpu_ns, steal_ns, irq_ns, rq_ns, vol_us = 0,
// se duoc do that o M3.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

char LICENSE[] SEC("license") = "GPL";

/* So level to tien toi da duyet khi loc theo cgroup. */
#define HIDS_MAX_CGROUP_LEVEL 16

/* Bang flags chot trong .cursor/rules/hids.mdc. */
#define HIDS_F_FIRST      (1U << 0)
#define HIDS_F_GAP_BEFORE (1U << 1)

/* bit8..15 chua so CPU luc sys_enter. User space tu choi chay neu may co hon
 * 256 CPU possible, nen 8 bit luon du. */
#define HIDS_F_CPU_SHIFT 8

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

/* Trang thai theo thread. M3 se mo rong them. */
struct hids_tstate {
	__u8 seen;        /* da ghi duoc ban ghi nao cho thread nay chua */
	__u8 gap_pending; /* lan ghi truoc that bai, ban ghi sau phai mang GAP_BEFORE */
};

/* Cau hinh do user space nap truoc khi nap chuong trinh. */
const volatile __u32 hids_self_tgid = 0;
const volatile __u8 hids_filter_cgroup = 0;

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
	flags |= (__u16)((bpf_get_smp_processor_id() & 0xff) << HIDS_F_CPU_SHIFT);

	seqp = bpf_map_lookup_elem(&hids_seq, &key0);
	if (!seqp)
		return 0;
	*seqp += 1;

	st = bpf_task_storage_get(&hids_task_state, bpf_get_current_task_btf(), NULL,
				  BPF_LOCAL_STORAGE_GET_F_CREATE);
	if (st) {
		if (!st->seen)
			flags |= HIDS_F_FIRST;
		if (st->gap_pending)
			flags |= HIDS_F_GAP_BEFORE;
	}

	rec = bpf_ringbuf_reserve(&hids_events, sizeof(*rec), 0);
	if (!rec) {
		__u64 *drops = bpf_map_lookup_elem(&hids_drops, &key0);

		if (drops)
			*drops += 1;
		if (st)
			st->gap_pending = 1;
		return 0;
	}

	rec->ts_enter = ts;
	rec->cgroup_id = bpf_get_current_cgroup_id();
	rec->tid = tid;
	rec->seq = *seqp;
	rec->syscall_nr = (__u16)id;
	rec->flags = flags;
	rec->cpu_ns = 0;
	rec->steal_ns = 0;
	rec->irq_ns = 0;
	rec->rq_ns = 0;
	rec->vol_us = 0;

	bpf_ringbuf_submit(rec, 0);

	if (st) {
		st->seen = 1;
		st->gap_pending = 0;
	}

	return 0;
}
