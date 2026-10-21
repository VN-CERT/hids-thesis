NHIỆM VỤ M6c — PMU trong bản ghi (64 byte), sửa cuộc đua ngắt, bộ overhead CUỐI cho bài. Lưu nguyên văn vào docs/tasks/M6c.md. Máy: uni-lms-app (vPMC đã bật).
File của kiến trúc sư (KHÔNG sửa nội dung; kiểm sha256 trước mỗi lần build, in vào báo cáo):
 - bpf/sys_enter.bpf.c = 8b05464db597cfc471dc7af24ce651ef905751ebd80ec463b3863b7dd0263c35
 - analysis/m6c_stats.py = 8c390002870f3ea8ace38a241f803bb5e7ec6c2413fdd403f757de24a6a1be25
 - bpf/proc_events.bpf.c = 39d892e5524de1cb49ace593b152c5b303d99c056e110f0a072d344c8270c7ec (không đổi)
 - analysis/m5f_parse.py = 9f0b4cde1c2e1c6aa560c041eaefaef1a40e5c7d9fc292db1d77dfc971d046cd (không đổi)
Build hoặc verifier lỗi: DỪNG, dán NGUYÊN VĂN toàn bộ log verifier của chương trình lỗi.

0. Chuẩn bị: kernel.perf_event_paranoid phải ≤ 1 (nếu không thì sysctl -w kernel.perf_event_paranoid=1). Mọi phép đo hiệu năng: dừng container thật, máy không chạy việc khác, docker start lại khi xong (kể cả khi lỗi). Commit trước, build sau; không dùng M5_SKIP_GIT_CHECK.

1. Cập nhật đặc tả trong .cursor/rules/hids.mdc:
 - Bản ghi 64 byte: ts_enter u64 | cgroup_id u64 | tid u32 | seq u32 | syscall_nr u16 | flags u16 | cpu_ns u32 | steal_ns u32 | irq_ns u32 | rq_ns u32 | vol_us u32 | steal_off_ns u32 | inst u32 | cyc u32 | reserved u32. Bản 48 và 56 byte cũ vẫn phải đọc được (theo record_size trong header).
 - flags bit7 = PMU: 1 khi inst và cyc hợp lệ cho CẢ khoảng; 0 thì không dùng inst/cyc. (Đặc tả cũ ghi "bit7 = 0": thay bằng định nghĩa này.)
 - inst/cyc = số lệnh / số chu kỳ CHẾ ĐỘ USER (exclude_kernel=1, exclude_hv=1) trong các đoạn ON-CPU của khoảng, đọc từ bộ đếm per-CPU. Không gồm phần chạy trong kernel (syscall, irq, BPF), nên không chứa chi phí của collector. Tràn u32 thì bão hoà và bật OVERFLOW (bit4).

2. Phía Go:
 a. internal/recfmt: ĐỔI RecordSize thành 64 (kích thước bản ghi mới), thêm hằng RecordSize56 = 56, giữ LegacyRecordSize = 48. Decode, ForEach và RecordSizeFromHeader chấp nhận cả 48/56/64. Record thêm Inst, Cyc; FlagPMU = 1<<7. Rà MỌI chỗ trong cmd/ và internal/ đang kiểm hoặc giả định độ dài bản ghi 56 byte (đặc biệt chỗ đọc mẫu từ ring buffer và chỗ ghi header): bản ghi mới là 64 byte. Header ghi record_size: 64, pmu: on|off, pmu_events: instructions:u,cycles:u.
 b. Rà mọi công cụ (rec-check, rec-stat, rec-chain, rec-export, script trong scripts/ và analysis/) có kiểm "bit7 phải bằng 0" hoặc coi bit7 là lỗi: cập nhật theo định nghĩa mới. Liệt kê các chỗ đã sửa trong báo cáo.
 c. Loader: cờ -pmu auto|on|off (mặc định auto). Với auto/on: trên mỗi CPU online, perf_event_open hai sự kiện PERF_TYPE_HARDWARE (PERF_COUNT_HW_INSTRUCTIONS và PERF_COUNT_HW_CPU_CYCLES), pid=-1, cpu=i, exclude_kernel=1, exclude_hv=1, disabled=0, read_format = TOTAL_TIME_ENABLED|TOTAL_TIME_RUNNING. Đưa fd vào map hids_pmu_inst / hids_pmu_cyc tại chỉ số = số CPU; đặt hids_pmu_on=1. Mở lỗi ở bất kỳ CPU nào: auto → hids_pmu_on=0, in cảnh báo, header ghi pmu: off; on → báo lỗi, từ chối chạy. Giữ fd mở suốt đời collector, đóng khi dừng. hids_pmu_on nạp như các biến cấu hình hiện có (hids_filter_pid, hids_rb_wake_bytes).
   - Nạp fd vào map tại index = SỐ CPU (cpu id), KHÔNG phải index tuần tự. Xác nhận map đủ max_entries cho CPU cao nhất (máy 24 CPU, map 256 chỗ: đủ).
   - Mở bộ đếm với disabled=0 (bật ngay). Nếu một CPU offline lúc mở thì bỏ qua CPU đó nhưng đánh dấu; với -pmu on mà có CPU online không mở được thì từ chối chạy.
 d. Luồng host mỗi giây: thêm cột pmu_inst_delta và pmu_cyc_delta = tổng trên mọi CPU (user space đọc các fd); ghi "na" khi pmu off. Cột mới thêm ở CUỐI dòng.
 e. rec-export: thêm cột inst, cyc, pmu_ok ở CUỐI (không chèn vào giữa, vì các script G3/B3' đang đọc cột theo vị trí). rec-stat: thêm tỉ lệ bản ghi không-FIRST có cờ PMU.

3. Cổng kiểm (từ commit sạch, binary cuối; mục nào không đạt: DỪNG, dán nguyên văn):
 - Đọc lại dữ liệu cũ: chạy rec-stat và rec-check bản mới trên một file .bin 56 byte còn giữ từ trước (ví dụ trong validation/ hoặc /srv/hids-data/). Phải đọc được, số bản ghi khớp file .stats đi kèm.
 - G7a (-zstd-level 0): perf = bản ghi, mất = 0. Chạy hai lần: -pmu on và -pmu off.
 - G7b (24 × 1.000.000, -zstd-level 0), 3 lần: KHÔNG đòi mất = 0 (tải này vượt công suất khoảng 1,2 triệu bản ghi/giây, R031). Đòi: perf − bản ghi = bộ đếm mất = seq thiếu, khớp tuyệt đối. Báo tỉ lệ mất từng lần.
 - G7b-nho: như cũ.
 - G3 S1–S5 với -pmu on, dừng container, chỉ một collector; chạy 3 lần. Yêu cầu mỗi lần: phần dư ≤ 500 ns; recursion_misses = 0; bảng đối chiếu với kernel; dòng "so khoang CLAMPED va |phan du| > 500 ns" phải là 0 / tổng (cuộc đua ngắt đã sửa). Thêm một lần G3 với -pmu off.
 - G11 (mới, PMU): ở S1 và S3, chạy thêm perf stat -e instructions:u,cycles:u -t <tid đích>, gắn khi wl đang chờ FIFO và dừng sau khi kịch bản xong. So với tổng inst và tổng cyc của các bản ghi của tid đích trong cùng cửa sổ (như g3_window.py). Yêu cầu: lệch ≤ 1% cho từng đại lượng; tỉ lệ bản ghi không-FIRST có cờ PMU ≥ 99%. Báo nguyên văn các con số.
   Nếu perf stat báo ghép kênh (cột phần trăm thời gian đếm < 100%) hoặc tỉ lệ cờ PMU < 99%: chạy lại G11 thành hai lần riêng, một lần chỉ instructions:u, một lần chỉ cycles:u; báo cả hai cách chạy.
   Báo thêm: phân bố cờ PMU theo CPU (có CPU nào tỉ lệ cờ PMU thấp bất thường không); nếu có, nhiều khả năng CPU đó mở bộ đếm trễ hoặc bị ghép kênh — báo số, không tự sửa.
 - G8, G9a, G9b, G10: như R030.

4. Bộ overhead CUỐI cho bài (binary cuối, dừng container, xen kẽ điều kiện, MỖI Ô ≥ 10 LƯỢT):
 - Điều kiện: C0 (không collector), C1 (bị đo, -pmu on), C1n (bị đo, -pmu off), C2 (không bị đo, -pmu on).
 - T1: sysinj N=10.000.000 ghim CPU 12 → ns/syscall (C0, C1, C1n, C2).
 - T4 kịch trần (wrk gốc như M5f) → Requests/sec (C0, C1, C1n, C2).
 - T3 kịch trần (pgtest chống nhiễu, VACUUM; rồi CHECKPOINT; trước mỗi lượt) → TPS (C0, C1, C2).
 - Tải cố định, mức = 25% và 50% của thông lượng C0 kịch trần ĐO TRONG ĐỢT NÀY: T3-R25, T4-R25, T4-R50 với C0, C1, C2 → độ trễ trung bình, p50, p99 (đọc bằng analysis/m5f_parse.py) và CPU của cgroup tải.
 - Mỗi chỉ số ghi thành một file TSV có tiêu đề "load cond run value", rồi chạy python3 analysis/m6c_stats.py <file> (KHÔNG sửa script). Dán NGUYÊN VĂN mọi output.
 - Ghi thêm số bản ghi/giây và số mất của mỗi lượt C1 và C1n.
 - Đường CPU của collector theo tốc độ, binary cuối, -pmu on: 1k, 10k, 100k, 500k bản ghi/giây, mỗi mức 2 phút (như R030).
 - Công suất với binary cuối, zstd mặc định: G7-cap mức 1, 2, 4 tiến trình, mỗi mức 60 giây: báo bản ghi đọc được/giây và tỉ lệ mất.

5. E4p (E4 có PMU): chạy lại E4-stream ở L = 0, 12, 22 (như E4 gốc) với -pmu on, 3 lần mỗi mức. Với các khoảng đốt của workload, báo trung vị của cpu_ns, inst, cyc, và hai tỉ số: cyc/inst (CPI) và cyc/cpu_ns (tần số hiệu dụng, GHz). Kỳ vọng để đối chiếu (KHÔNG phải tiêu chí): inst gần như không đổi theo L; nếu cpu tăng mà tần số hiệu dụng không giảm thì phần tăng là do CPI (tranh chấp bộ nhớ), không phải turbo. Lưu ý: cyc chỉ đếm chế độ user còn cpu_ns gồm cả phần kernel, nên tần số hiệu dụng chỉ đúng gần đúng cho khoảng đốt (gần như toàn user).

6. Kết thúc: commit, gắn tag m6c, git push github --all && git push github --tags. Viết R032 với mục "Thay đổi ngoài phạm vi nhiệm vụ" và sha256 bốn file kiến trúc sư. DỪNG.
