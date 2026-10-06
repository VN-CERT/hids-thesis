# Chỉ mục báo cáo

| Số | Ngày giờ | Mốc | Tóm tắt | Trạng thái |
|---|---|---|---|---|
| [R001](R001-m1-steal-probe.md) | 2026-10-06 22:05 | M1 | Công cụ `steal-probe` và `steal-summary` đọc bộ đếm steal của từng CPU bằng `bpf_per_cpu_ptr` và đối chiếu với `/proc/stat`. | Xong. Kiến trúc sư đã duyệt 3 câu hỏi; G1 đã chạy và ĐẠT |
| [R002](R002-m2-ban-ghi-syscall.md) | 2026-10-06 22:47 | M2 | Bản ghi syscall 48 byte qua `tp_btf/sys_enter`, lọc theo pid/cgroup, ring buffer dùng chung, đếm bản ghi mất; `hids-collect`, `rec-stat`, `sysinj`, `g7.sh`. | Xong phần việc của máy; chờ người dùng chạy G7a/b/c và kiến trúc sư quyết định về trường CPU trong bản ghi |
