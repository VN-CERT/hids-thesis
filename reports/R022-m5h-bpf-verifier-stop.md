# R022 — M5h: BPF tối ưu — dừng ở bước 2 (verifier)

1. **Số báo cáo:** R022  
   **Ngày giờ:** 2026-10-08 23:45 (UTC+7)  
   **Mốc:** M5h  
   **Git commit:** `49b9a16` (sau `25c66cb` BPF, `539a171` Go); **không** gắn tag `m5h`

2. **Mục tiêu**  
   Áp BPF tối ưu (sha256 kiến trúc sư), nạp `hids_filter_pid` / `hids_rb_wake_bytes`, kiểm không hồi quy G7/G3, đo overhead T1/T3/T4 và tải cố định; tag `m5h`.

3. **Đã làm gì**  
   - Bước 0: sha256 `bpf/sys_enter.bpf.c` = `7618d9c118c89548b6acca9fa2b9e9ab81022707a81f86306c8fcd31f503e47a` — khớp. Commit `25c66cb` «M5h: BPF toi uu (kien truc su)».  
   - Bước 1: `internal/syscallbpf/loader.go` nạp `hids_filter_pid` (0/1), `hids_rb_wake_bytes` = `ringbuf_bytes/8`; header `.bin`: `filter_pid`, `rb_wake_bytes`; danh sách TGID chuyển sang `filter_tgids`. `make build` thành công. Commit `539a171`. Commit phụ `49b9a16` (sửa m5f meta).  
   - Bước 2: chạy G7a (tracepoint) — **thất bại** (collector không READY). **Dừng**; không chạy G7a fentry, G7b, G7b-nho, G3, bước 3–4.

4. **Lệnh build / chạy**  
   ```bash
   cd /root/hids
   sha256sum bpf/sys_enter.bpf.c
   make build
   bash scripts/g7.sh a 1000000
   # log: validation/m5h-20261008/step2/g7a-tp.log
   #      validation/m5h-20261008/step2/g7a-tp-collect.log
   #      out/hids-collect.log (mục 2026-10-08T23:44:51+07:00)
   ```

5. **Kết quả**

   **G7a (tracepoint) — nguyên văn stderr / g7:**  
   ```
   === g7a: 1 sysinj, moi cai N=1000000, ring buffer 64 MiB, stress-ng=0 ===
   sysinj pids: 709244
   g7: collector khong in READY sau 30 giay, xem out/g7a-20261008-234447-collect.log
   ```

   **Lỗi verifier / libbpf (nguyên văn từ `out/hids-collect.log`):**  
   ```
   === 2026-10-08T23:44:51+07:00 khong nap duoc chuong trinh BPF cua collector ===
   load program: permission denied:
   	0: R1=ctx() R10=fp0
   	; int BPF_PROG(hids_sched_switch, bool preempt, struct task_struct *prev,
   	0: (79) r7 = *(u64 *)(r1 +24)         ; R1=ctx() R7_w=scalar()
   	1: (79) r6 = *(u64 *)(r1 +16)
   	func 'sched_switch' arg2 has btf_id 210 type STRUCT 'task_struct'
   	2: R1=ctx() R6_w=trusted_ptr_task_struct()
   	2: (79) r2 = *(u64 *)(r1 +0)          ; R1=ctx() R2_w=scalar()
   	3: (7b) *(u64 *)(r10 -32) = r2        ; R2_w=scalar() R10=fp0 fp-32_w=mmmmmmmm
   	4: (79) r2 = *(u64 *)(r1 +8)
   	func 'sched_switch' arg1 has btf_id 210 type STRUCT 'task_struct'
   	5: R1=ctx() R2_w=trusted_ptr_task_struct()
   	5: (b7) r8 = 0                        ; R8_w=0
   	; sp = bpf_task_storage_get(&hids_task_state, prev, NULL, 0);
   	6: (18) r1 = 0xffff8de22dd7da00       ; R1_w=map_ptr(map=hids_task_state,ks=4,vs=136)
   	8: (b7) r3 = 0                        ; R3_w=0
   	9: (b7) r4 = 0                        ; R4_w=0
   	10: (85) call bpf_task_storage_get#156        ; R0_w=map_value_or_null(id=1,map=hids_task_state,ks=4,vs=136)
   	11: (b7) r9 = 0                       ; R9_w=0
   	; if (sp && !sp->seen)
   	12: (15) if r0 == 0x0 goto pc+3       ; R0_w=map_value(map=hids_task_state,ks=4,vs=136)
   	; if (sp && !sp->seen)
   	13: (71) r1 = *(u8 *)(r0 +130)        ; R0=map_value(map=hids_task_state,ks=4,vs=136) R1=scalar(smin=smin32=0,smax=umax=smax32=umax32=255,var_off=(0x0; 0xff))
   	; if (sp && !sp->seen)
   	14: (15) if r1 == 0x0 goto pc+1       ; R1=scalar(smin=umin=smin32=umin32=1,smax=umax=smax32=umax32=255,var_off=(0x0; 0xff))
   	15: (bf) r9 = r0                      ; R0=map_value(map=hids_task_state,ks=4,vs=136) R9_w=map_value(map=hids_task_state,ks=4,vs=136)
   	; sn = bpf_task_storage_get(&hids_task_state, next, NULL, 0);
   	16: (18) r1 = 0xffff8de22dd7da00      ; R1_w=map_ptr(map=hids_task_state,ks=4,vs=136)
   	18: (bf) r2 = r6                      ; R2_w=trusted_ptr_task_struct() R6=trusted_ptr_task_struct()
   	19: (b7) r3 = 0                       ; R3_w=0
   	20: (b7) r4 = 0                       ; R4_w=0
   	21: (85) call bpf_task_storage_get#156        ; R0_w=map_value_or_null(id=2,map=hids_task_state,ks=4,vs=136)
   	; if (sn && !sn->seen)
   	22: (15) if r0 == 0x0 goto pc+3       ; R0_w=map_value(map=hids_task_state,ks=4,vs=136)
   	; if (sn && !sn->seen)
   	23: (71) r1 = *(u8 *)(r0 +130)        ; R0=map_value(map=hids_task_state,ks=4,vs=136) R1=scalar(smin=smin32=0,smax=umax=smax32=umax32=255,var_off=(0x0; 0xff))
   	; if (sn && !sn->seen)
   	24: (15) if r1 == 0x0 goto pc+1       ; R1=scalar(smin=umin=smin32=umin32=1,smax=umax=smax32=umax32=255,var_off=(0x0; 0xff))
   	25: (bf) r8 = r0                      ; R0=map_value(map=hids_task_state,ks=4,vs=136) R8_w=map_value(map=hids_task_state,ks=4,vs=136)
   	; if (!sp && !sn)
   	26: (bf) r1 = r9                      ; R1_w=map_value(map=hids_task_state,ks=4,vs=136) R9=map_value(map=hids_task_state,ks=4,vs=136)
   	27: (4f) r1 |= r8
   	R1 pointer |= pointer prohibited
   	processed 26 insns (limit 1000000) max_states_per_insn 0 total_states 2 peak_states 2 mark_read 1
   ```

   Chương trình: `hids_sched_switch`. G7a fentry, G7b, G7b-nho, G3 S1–S5, bước 3 đo, tag `m5h`: **chưa chạy**.

6. **File dữ liệu**  
   - `/root/hids/validation/m5h-20261008/step2/g7a-tp.log`  
   - `/root/hids/validation/m5h-20261008/step2/g7a-tp-collect.log`  
   - `/root/hids/docs/tasks/M5h.md`

7. **Quyết định đã tự đưa ra**  
   - Header: giữ danh sách TGID ở `filter_tgids`; `filter_pid` trong header là cờ 0/1 theo đặc tả M5h (tránh trùng nghĩa với dòng TGID cũ).  
   - Không sửa `bpf/sys_enter.bpf.c` theo lệnh nhiệm vụ.

8. **Cần kiến trúc sư quyết định**  
   - Sửa BPF `hids_sched_switch`: verifier từ chối `r1 |= r8` (pointer |= pointer) khi gộp kiểm tra `!sp && !sn` sau tối ưu task storage. Cần bản BPF mới sha256 trước khi chạy lại M5h từ bước 2.

9. **Việc người dùng cần làm tay**  
   - Chép file BPF đã sửa (nếu kiến trúc sư cung cấp) vào `bpf/sys_enter.bpf.c`, rồi giao chạy lại M5h.

10. **Lỗi còn tồn tại / việc tiếp theo**  
    - Collector không nạp được trên kernel 6.8.0-142 — M5h dừng tại bước 2.  
    - Sau khi có BPF verifier-pass: `make build`, lặp bước 2–4 của `docs/tasks/M5h.md`, gắn tag `m5h`, báo cáo R022 bổ sung hoặc R023.
