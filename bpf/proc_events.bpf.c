// SPDX-License-Identifier: GPL-2.0
//
// proc_events.bpf.c - M6b: luong metadata tien trinh (fork, exec, exit) cua
// cac cgroup dich. Do kien truc su viet. KHONG do thoi gian, KHONG dung chung
// map voi sys_enter.bpf.c; nap thanh mot object rieng.
//
// Moi su kien la mot ban ghi co dinh 176 byte (little-endian) dua vao ring
// buffer rieng hids_proc_events:
//   ts u64 | cgroup_id u64 | type u32 | tgid u32 | tid u32 | ppid u32 |
//   comm[16] | filename[128]
// type: 1 = fork (task la tien trinh/thread CON; ppid = tgid cua cha),
//       2 = exec (filename = duong dan file thuc thi),
//       3 = exit (moi thread khi ket thuc).
// comm va filename la chuoi ket thuc bang byte 0; phan sau byte 0 KHONG duoc
// xoa (bo nho ring buffer khong duoc khoi tao), ben doc phai cat tai byte 0.
// filename chi co nghia voi exec; voi fork/exit filename[0] = 0.
//
// Loc: cgroup hien tai (bpf_get_current_cgroup_id) phai nam trong map
// hids_proc_cgroups (user space nap CUNG tap cgroup dich nhu hids_cgroups cua
// collector chinh). Bo qua tien trinh cua chinh collector.
// Mat ban ghi (ring day) duoc dem trong hids_proc_drops (per-CPU).

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>

char LICENSE[] SEC("license") = "GPL";

#define HIDS_PROC_FORK 1
#define HIDS_PROC_EXEC 2
#define HIDS_PROC_EXIT 3
#define HIDS_COMM_LEN 16
#define HIDS_FNAME_LEN 128

struct hids_proc_ev {
	__u64 ts;
	__u64 cgroup_id;
	__u32 type;
	__u32 tgid;
	__u32 tid;
	__u32 ppid;
	char comm[HIDS_COMM_LEN];
	char filename[HIDS_FNAME_LEN];
};

const volatile __u32 hids_proc_self_tgid = 0;

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 65536);
	__type(key, __u64);
	__type(value, __u8);
} hids_proc_cgroups SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 8 << 20);
} hids_proc_events SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u64);
} hids_proc_drops SEC(".maps");

static __always_inline void proc_drop(void)
{
	__u32 k = 0;
	__u64 *d = bpf_map_lookup_elem(&hids_proc_drops, &k);

	if (d)
		*d += 1;
}

/* Tra cgroup hien tai; tra ve 0 neu khong thuoc tap dich. */
static __always_inline __u64 proc_cgroup_selected(void)
{
	__u64 cgid = bpf_get_current_cgroup_id();

	if (!bpf_map_lookup_elem(&hids_proc_cgroups, &cgid))
		return 0;
	return cgid;
}

/* fork chay trong ngu canh cua tien trinh CHA; con thua ke cgroup cua cha. */
SEC("tp_btf/sched_process_fork")
int BPF_PROG(hids_proc_fork, struct task_struct *parent, struct task_struct *child)
{
	struct hids_proc_ev *e;
	__u32 ptgid = BPF_CORE_READ(parent, tgid);
	__u64 cgid;

	if (ptgid == hids_proc_self_tgid)
		return 0;
	cgid = proc_cgroup_selected();
	if (!cgid)
		return 0;

	e = bpf_ringbuf_reserve(&hids_proc_events, sizeof(*e), 0);
	if (!e) {
		proc_drop();
		return 0;
	}
	e->ts = bpf_ktime_get_ns();
	e->cgroup_id = cgid;
	e->type = HIDS_PROC_FORK;
	e->tgid = BPF_CORE_READ(child, tgid);
	e->tid = BPF_CORE_READ(child, pid);
	e->ppid = ptgid;
	BPF_CORE_READ_STR_INTO(&e->comm, child, comm);
	e->filename[0] = 0;
	bpf_ringbuf_submit(e, 0);
	return 0;
}

/* exec chay trong ngu canh cua chinh tien trinh vua exec (comm da la ten moi). */
SEC("tp_btf/sched_process_exec")
int BPF_PROG(hids_proc_exec, struct task_struct *p, pid_t old_pid, struct linux_binprm *bprm)
{
	struct hids_proc_ev *e;
	__u32 tgid = BPF_CORE_READ(p, tgid);
	const char *fname;
	__u64 cgid;

	if (tgid == hids_proc_self_tgid)
		return 0;
	cgid = proc_cgroup_selected();
	if (!cgid)
		return 0;

	e = bpf_ringbuf_reserve(&hids_proc_events, sizeof(*e), 0);
	if (!e) {
		proc_drop();
		return 0;
	}
	e->ts = bpf_ktime_get_ns();
	e->cgroup_id = cgid;
	e->type = HIDS_PROC_EXEC;
	e->tgid = tgid;
	e->tid = BPF_CORE_READ(p, pid);
	e->ppid = BPF_CORE_READ(p, real_parent, tgid);
	BPF_CORE_READ_STR_INTO(&e->comm, p, comm);
	fname = BPF_CORE_READ(bprm, filename);
	if (bpf_probe_read_kernel_str(e->filename, sizeof(e->filename), fname) < 0)
		e->filename[0] = 0;
	bpf_ringbuf_submit(e, 0);
	return 0;
}

/* exit chay trong ngu canh cua thread dang ket thuc (moi thread mot su kien). */
SEC("tp_btf/sched_process_exit")
int BPF_PROG(hids_proc_exit, struct task_struct *p)
{
	struct hids_proc_ev *e;
	__u32 tgid = BPF_CORE_READ(p, tgid);
	__u64 cgid;

	if (tgid == hids_proc_self_tgid)
		return 0;
	cgid = proc_cgroup_selected();
	if (!cgid)
		return 0;

	e = bpf_ringbuf_reserve(&hids_proc_events, sizeof(*e), 0);
	if (!e) {
		proc_drop();
		return 0;
	}
	e->ts = bpf_ktime_get_ns();
	e->cgroup_id = cgid;
	e->type = HIDS_PROC_EXIT;
	e->tgid = tgid;
	e->tid = BPF_CORE_READ(p, pid);
	e->ppid = BPF_CORE_READ(p, real_parent, tgid);
	BPF_CORE_READ_STR_INTO(&e->comm, p, comm);
	e->filename[0] = 0;
	bpf_ringbuf_submit(e, 0);
	return 0;
}
