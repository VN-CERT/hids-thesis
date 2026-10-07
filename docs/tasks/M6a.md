NHIỆM VỤ M6a — lưu nguyên văn vào docs/tasks/M6a.md.

0. Dừng M5: systemctl stop hids-m5-full (nếu còn chạy). Đổi tên validation/m5-20261007 thành validation/m5-20261007-truoc-m6a, kèm README "số liệu trên mã trước M6a, không dùng cho bài". M5 sẽ chạy lại toàn bộ sau M6a.

1. Xác nhận lỗi trước khi sửa, trên dữ liệu E2 mức 36000 (dùng file .bin nếu còn trong out/, nếu không thì dùng CSV export): đếm số bản ghi có CLAMPED; đếm số bản ghi |phần dư| > 1 µs; in 5 bản ghi có irq lớn nhất (dt, cpu, steal, irq, rq, vol, flags). Làm tương tự cho mức 24000 và 12000.
   Giả thuyết của kiến trúc sư: khi hypervisor dừng vCPU đúng lúc đang xử lý ngắt, khoảng bị lấy mất được tính HAI lần (trong irq và trong steal), nên cpu bị kẹp về 0 và tổng thành phần vượt Δt; dòng check 787 µs ≈ Δirq 775 µs ở mức 36000. Ghi kết quả vào báo cáo, dù xác nhận hay bác bỏ.

2. Sửa irq để không chồng với steal:
   - Trạng thái irq per-CPU của mỗi loại (hard, soft, vector) ghi thêm giá trị vmw thô lúc vào.
   - Lúc ra: thời gian irq = (ra − vào) − Δsteal trên CPU đó trong cùng khoảng (quy ra ns), kẹp ≥ 0. Áp dụng cho hard, vector, soft_raw.
   - soft_excl = (ra − vào) − Δsteal của cả khoảng soft − phần lồng (hard + vector, đã trừ steal).
   - irq_total_at() (phần irq đang dở) cũng trừ steal theo cùng cách.
   Kỳ vọng: cpu + steal + irq của mỗi đoạn ON-CPU bằng độ dài đoạn mà không phải kẹp; cờ CLAMPED không còn xuất hiện khi có steal.

3. Thêm trường steal_off_ns; bản ghi nới lên 56 byte. Cập nhật đặc tả trong hids.mdc:
   ts_enter u64 | cgroup_id u64 | tid u32 | seq u32 | syscall_nr u16 | flags u16 | cpu_ns u32 | steal_ns u32 | irq_ns u32 | rq_ns u32 | vol_us u32 | steal_off_ns u32 | reserved u32 (= 0)
   Định nghĩa: steal trên vCPU liên quan trong lúc thread OFF-CPU trong khoảng. KHÔNG nằm trong phép cộng Δt (nó chồng lên vol và rq); chỉ đo thêm để biết phần vol/rq trùng với lúc hypervisor dừng vCPU.
   (a) Phần ngủ: Δvmw của CPU lúc switch-out, tính từ switch-out tới sched_wakeup (đọc từ xa bằng bpf_per_cpu_ptr tại thời điểm wakeup).
   (b) Phần chờ rq: Δvmw của CPU mục tiêu, tính từ lúc bắt đầu chờ tới sched_switch vào. CPU mục tiêu = task_cpu(p) tại sched_wakeup; với loại RUNNABLE thì là CPU lúc switch-out. Nếu thread được chạy trên CPU khác CPU mục tiêu: vẫn tính trên CPU mục tiêu, giữ cờ MIGRATED.
   Cộng dồn qua mọi đoạn OFF-CPU trong khoảng. Tràn u32 thì bão hoà và bật OVERFLOW.

4. Cập nhật mọi công cụ cho bản ghi 56 byte: hids-collect (header ghi record_size: 56), rec-stat, rec-check (G5 giữ nguyên; thêm tổng steal_off), rec-export (thêm cột steal_off_ns), analysis/m4.py (thêm steal_off vào thống kê và bảng phân rã). File .bin 48 byte cũ vẫn phải đọc được (đọc record_size từ header).

5. Tự kiểm sau khi sửa (từ commit sạch, tự chạy):
   - G7a (N=1.000.000) và G7d: khớp tuyệt đối như trước.
   - G3 S1–S5: bảng đối chiếu như bản v3; G5 phần dư ≤ 0,5 µs.
   - In tổng steal_off của S2 (máy rảnh, kỳ vọng ≈ 0).
   Lưu vào validation/g3-<ngày>-m6a/.

6. Chuẩn bị E2 lần 3 (NGƯỜI DÙNG chạy): giữ nguyên quy trình của scripts/m4.sh e2. Summary và bảng phân rã thêm steal_off cho cả khoảng đốt và khoảng ngủ, và đếm số bản ghi CLAMPED theo từng mức. KHÔNG chạy E2.

7. Commit, gắn tag m6a. Viết R014: kết quả mục 1, những gì đã sửa, bảng tự kiểm mục 5, và mục 9 hướng dẫn người dùng chạy E2. DỪNG.
