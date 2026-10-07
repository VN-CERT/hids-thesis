# Chỉ mục báo cáo

| Số | Ngày giờ | Mốc | Tóm tắt | Trạng thái |
|---|---|---|---|---|
| [R001](R001-m1-steal-probe.md) | 2026-10-06 22:05 | M1 | Công cụ `steal-probe` và `steal-summary` đọc bộ đếm steal của từng CPU bằng `bpf_per_cpu_ptr` và đối chiếu với `/proc/stat`. | Xong. Kiến trúc sư đã duyệt 3 câu hỏi; G1 đã chạy và ĐẠT |
| [R002](R002-m2-ban-ghi-syscall.md) | 2026-10-06 22:47 | M2 | Bản ghi syscall 48 byte qua `tp_btf/sys_enter`, lọc theo pid/cgroup, ring buffer dùng chung, đếm bản ghi mất; `hids-collect`, `rec-stat`, `sysinj`, `g7.sh`. | Xong. Kiến trúc sư đã quyết định mục 8: chọn phương án B |
| [R003](R003-m2.1-cpu-trong-flags-va-do-g7.md) | 2026-10-06 23:30 | M2.1 | Số CPU vào flags bit 8–15, `rec-stat` phân tích seq theo từng CPU, `sysinj` chờ bằng `read()`; chạy bốn phép đo G7a, G7b, G7b-nho, G7c. | Xong. Chờ kiến trúc sư quyết định 2 mục (biên cửa sổ G7c, ngưỡng cảnh báo ring buffer đầy) |
| [R004](R004-m3-ae-trang-thai-thread-irq-failclosed.md) | 2026-10-07 00:10 | M3 mục A–E | Trạng thái theo thread trong task storage, máy trạng thái ON-CPU/OFF-CPU, bộ cộng dồn irq per-CPU 13 cặp tracepoint, kiểm tra fail-closed lúc khởi động và 8 dòng header mới. Mục F–J của M3 chưa làm. | Xong phần A–E, tag `m3-ae`. Chờ kiến trúc sư quyết định 4 mục, trước hết là đua trên độ sâu irq |
| [R005](R005-m3-phan2-g3-wl-rec-check.md) | 2026-10-07 00:42 | M3 PHẦN 2 | `wl`, `rec-check`, `g3.sh` (S1–S5, G-real, G-irq, G7d), dữ liệu `validation/g3-20261007/`, tag `m3`. | **R005 hỏng định dạng, số liệu thay bằng R006** (heredoc shell không quote) |
| [R006](R006-m3.1-g3-v2-wl-bpftrace.md) | 2026-10-07 01:25 | M3.1 | G3 v2: wl hiệu chỉnh, bpftrace S2/S3/S5, G-real `cgroup.threads`, `validation/g3-20261007-v2/`, tag `m3` → `d4c55b9`. | Xong M3.1. Chờ kiến trúc sư G-real / G-irq / rq bpftrace |
| [R007](R007-m3.2-m4-ab.md) | 2026-10-07 03:50 | M3.2 + M4-ab | G3 v3, E1/E3/E4, `validation/m4-20261007/`, tag `m4-ab`; E2 chờ người dùng. | Xong phần Cursor. Tag `m4` sau E2. |
| [R008](R008-m4.1-mem-e4.md) | 2026-10-07 13:35 | M4.1 | Sửa hiệu chỉnh `wl mem`, chạy lại E4, `summary.csv` tái tạo. | Xong. |
