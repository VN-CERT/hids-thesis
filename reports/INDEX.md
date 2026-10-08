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
| [R009](R009-m4-e2-tag.md) | 2026-10-07 14:05 | M4 | E2 trong `summary.csv`, `E2.png`, tag `m4`. | **E2 không hợp lệ, thay bằng R010** |
| [R010](R010-m4.2-e2-invalid-fix.md) | 2026-10-07 15:00 | M4.2 | Loại E2 sai; sửa `m4.sh e2` + workflow; chờ người dùng thu E2 lại. | Xong phần chuẩn bị. |
| [R011](R011-m4.3-e2-stats-fix.md) | 2026-10-07 15:15 | M4.3 | Sửa E2 + stats; E2-lan1; không chạy E2 lại. | Xong. |
| [R012](R012-m4-close.md) | 2026-10-07 15:45 | M4.4 | Đóng M4: E2.png, phân rã, sửa mẫu số steal 10s; tag `m4`. | Xong. |
| [R013](R013-m5-overhead.md) | 2026-10-07 16:10 | M5 | Overhead collector; job `hids-m5-full` đang chạy. | **Thay bằng R016 (M5 m6a)** |
| [R014](R014-m6a-irq-steal-stealoff.md) | 2026-10-07 16:45 | M6a | irq trừ steal, `steal_off_ns` 56 byte, tự kiểm G7/G3 S1–S5; E2 lần 3 chờ người dùng. | Xong, tag `m6a`. |
| [R015](R015-e2-lan3-m4py.md) | 2026-10-07 17:05 | E2-l3 | Sửa `m4.py` gộp CSV; tái tạo summary/E2.png; E2-lan2/lan3. | Xong. |
| [R016](R016-m5-m6a-overhead.md) | 2026-10-07 21:05 | M5 | Overhead C0–C3 T1–T4 m6a; `validation/m5-20261007-m6a/`. | Xong, tag `m5`. |
| [R017](R017-m5b-overhead-opt.md) | 2026-10-07 22:15 | M5b | O2/O3, sửa C2; O1 NO_WAKEUP hoãn; M5b + G3; tag `m5b`. | Xong (T4-R/chẩn đoán cần chạy lại). |
| [R018](R018-m5c-overhead-fentry-diag.md) | 2026-10-08 11:30 | M5c | Chẩn đoán đĩa; bỏ O1; O4 fentry; T3-R/T4-R; tag `m5c`. | Xong. O5 chưa; BPF stats tải rỗng. |
| [R019](R019-m5d-o1-close.md) | 2026-10-08 17:05 | M5d | O1 verify G7/G3, G7-cap, BPF, ma trận C0–C2; tag `m5d`. | Xong. O5 chờ KA; T3-R thiếu số. |
| [R020](R020-m5e-t3r-latency-noise.md) | 2026-10-08 19:45 | M5e | G7 zstd, T3-R/T4-R, T4 kịch trần, nhiễu git push; tag `m5e`. | Xong. O5 không làm. |
| [R021](R021-m5f-wrk2-t3r-t4r-case-a.md) | 2026-10-08 23:10 | M5f | Case A T4 wrk, T3 cấu hình mới, T3-R/T4-R + m5f_parse; tag `m5f`. | Xong. `m5f_parse.tsv` job rỗng; O5 không làm. |
