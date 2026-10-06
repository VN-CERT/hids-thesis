NHIỆM VỤ M3 PHẦN 2. Trước khi làm: lưu nguyên văn nhiệm vụ này vào docs/tasks/M3-phan2.md. Từ nay, mọi nhiệm vụ đều lưu nguyên văn vào docs/tasks/.

QUYẾT ĐỊNH CỦA KIẾN TRÚC SƯ CHO R004
- Các quyết định tự đưa ra ở mục 7 của R004: đều chấp nhận.
- 8.1 Ngưỡng so hai đường steal max(2 ms, 1%) trong 3 giây: GIỮ NGUYÊN.
- 8.2 Đua trên độ sâu irq: chọn (c). Viết lại mục C như sau:
  · Bỏ biến độ sâu dùng chung. Mỗi CPU giữ trạng thái RIÊNG cho từng loại hard, soft, vector: mốc vào (0 = không hoạt động) và tổng. Mỗi trường chỉ do chương trình của đúng loại đó ghi.
  · Cơ sở: trên một CPU, hard và vector không lồng vào nhau và không tự lồng; soft không tự lồng; hard và vector có thể lồng vào trong soft.
  · Tránh đếm hai lần: lúc soft vào, chụp (tổng hard + tổng vector) của CPU. Lúc soft ra: phần lồng = (tổng hard + tổng vector hiện tại) − ảnh chụp; soft_excl += (ra − vào) − phần lồng. Giữ thêm soft_raw += (ra − vào), chỉ dùng để đối chiếu với softirqs-bpfcc.
  · Thành phần irq của thread = hard + vector + soft_excl.
  · irq_total_at() cộng thêm phần đang dở của từng loại đang hoạt động (cho trường hợp sched_switch xảy ra trong đường thoát irq). Với soft đang dở, phần lồng cũng trừ theo cùng cách.
  · Giữ bộ phát hiện hỏng dữ liệu (khoảng > 1 giây thì loại ra và đếm) và dòng in số loại còn đang hoạt động lúc kết thúc.
  · Lúc kết thúc, in recursion_misses của TỪNG chương trình BPF (lấy từ bpf_prog_info). Phải bằng 0; khác 0 thì ghi vào báo cáo.
  · File .periodic thêm cột soft_raw_delta_ns.
- 8.3 Header thêm: CONFIG_IRQ_TIME_ACCOUNTING, CONFIG_PARAVIRT_TIME_ACCOUNTING, CONFIG_SCHEDSTATS, CONFIG_SCHED_INFO (đọc từ /boot/config-$(uname -r)).
- 8.4 Đã quyết, ghi vào STATE.md để đóng:
  · G7c theo phương án (c).
  · Mất bản ghi: collector luôn in LOSS và không bao giờ tự dừng. Ngưỡng "bất thường" thuộc tầng phát hiện (GĐ3): khoảng có GAP_BEFORE bị loại khỏi chấm điểm và cộng vào "thời gian mù"; ngưỡng cảnh báo sẽ đặt theo ngân sách báo động của fleet.

PHẦN 1 = 8.2 + 8.3
Làm xong thì chạy lại phép chạy thử 30 giây của R004 và phép soi chéo tự nhất quán; commit; in đúng dòng "XONG PHẦN 1" rồi CHỜ. Người dùng sẽ đổi model và bảo làm tiếp.

PHẦN 2 = M3 mục F–J (định nghĩa A–E đã ghi trong hids.mdc)

F. tools/wl.c (C, gcc, đơn luồng)
- Giao thức BA lần read() trên stdin:
  1. read lần 1 (chờ go1) → một syscall đánh dấu (getuid) để collector khởi tạo trạng thái;
  2. read lần 2 (chờ go2) → chạy kịch bản → một syscall đánh dấu;
  3. read lần 3 (chờ go3) → thoát.
- Chế độ:
  · cpu X_us: đốt CPU tới khi CLOCK_THREAD_CPUTIME_ID tăng X µs, rồi gọi getppid;
  · sleep Y_us: nanosleep, rồi gọi getppid;
  · mixed X Y;
  · io: pwrite 4 KiB + fdatasync trên file tạm trong /root/hids/out.
  Số vòng R.

G. bin/rec-check
- G5, phần dư: với mỗi bản ghi không có cờ FIRST, Δt = ts_enter − ts_enter của bản ghi trước cùng tid; phần dư = Δt − (cpu + steal + irq + rq + vol_us×1000). In p50, p99, p99.9, max của |phần dư|; số bản ghi có |phần dư| > 1 µs và > 10 µs. Tách riêng nhóm bản ghi có GAP_BEFORE.
- Tổng các thành phần theo tid trong một cửa sổ; số bản ghi mang từng cờ.

H. scripts/g3.sh (TỰ CHẠY)
- Đầu script: lưu giá trị kernel.sched_schedstats hiện tại rồi đặt = 1. Cuối script: trả lại giá trị cũ.
- Trình tự mỗi kịch bản:
  chạy wl → hids-collect -pid → chờ READY → go1 → chờ wl thực sự ngủ trong read lần 2 (trạng thái S trong /proc/<pid>/stat) → chụp /proc/<tid>/schedstat và /proc/<tid>/sched (mốc A) → go2 → chờ wl ngủ trong read lần 3 → chụp lại (mốc B) → dừng collector → go3.
- Cửa sổ so sánh của collector = các bản ghi có ts_enter nằm trong (ts sys_enter của read lần 2, ts sys_enter của read lần 3].
- Các kịch bản (wl ghim CPU 20 bằng taskset):
  S1: cpu X=10000 R=300, máy rảnh
  S2: sleep Y=5000 R=500
  S3: mixed X=2000 Y=3000 R=500
  S4: như S1, kèm stress-ng --cpu 1 --taskset 20 chạy suốt kịch bản
  S5: io R=300
- Mỗi kịch bản in bảng (thành phần | collector | tham chiếu | nguồn):
  · cpu+steal+irq vs Δ trường 1 của /proc/<tid>/schedstat (sum_exec_runtime; trên kernel này đã gồm cả steal và irq)
  · rq vs Δ trường 2 của /proc/<tid>/schedstat (run_delay), và vs Δ wait_sum trong /proc/<tid>/sched
  · vol vs Δ sum_sleep_runtime trong /proc/<tid>/sched
  · vol của các bản ghi có D_SLEEP vs Δ sum_block_runtime (nếu kernel có trường này)
  Kèm theo: số bản ghi, số bản ghi mang mỗi cờ, thống kê phần dư G5, riêng từng giá trị cpu, steal, irq.
  Trường nào không có hoặc không đổi: in nguyên văn file đó ra, không đoán.
- G-real (thông tin): lọc cgroup container qdrant trong 120 giây. Với các thread sống suốt cửa sổ, so tổng thành phần với Δ /proc/<tid>/schedstat và /proc/<tid>/sched (chụp đầu và cuối cửa sổ). In tổng trên mọi thread và 10 thread bận nhất. Chênh lệch do biên cửa sổ là bình thường.
- G-irq (thông tin): trong 30 giây máy rảnh, chạy cùng lúc hardirqs-bpfcc 30 1 và softirqs-bpfcc 30 1.
  · So hard của collector với hardirqs-bpfcc.
  · So soft_raw của collector với softirqs-bpfcc (bcc tính cả phần hard lồng bên trong soft).
  · In thêm soft_excl và vector của collector (bcc không đo vector).
- G7d: tự chạy lại một lần với binary mới (bash scripts/g7.sh d hoặc tên phần tương ứng).

I. Kỳ vọng vật lý. Dùng để TỰ TÌM LỖI trong code của bạn, KHÔNG dùng để kết luận đạt:
- Phần dư G5 dưới khoảng 1 µs.
- Các cặp so sánh ở mục H, với S1–S5, lệch khoảng 1% hoặc ít hơn.
- S1: vol ≈ 0, cpu mỗi khoảng ≈ 10 ms. S2: vol mỗi khoảng ≈ 5 ms. S4: rq cỡ bằng cpu. S5: có cờ D_SLEEP.
- recursion_misses = 0; bộ phát hiện hỏng irq = 0.
Lệch lớn: tìm nguyên nhân trong code của bạn và sửa. Nếu nguyên nhân nằm ở định nghĩa hoặc nguồn tham chiếu: KHÔNG tự sửa định nghĩa; ghi vào mục 8 kèm số liệu, dừng phần đó, làm tiếp phần khác.

J. Kết thúc
- Lưu output (*-ketqua.txt, .periodic, .stats) vào validation/g3-<ngày>/, commit, gắn tag m3.
- Viết R005: dán nguyên văn bảng của S1–S5, G-real, G-irq, G7d, recursion_misses; tổng hợp chi phí CPU của collector.
- Viết xong thì DỪNG, không làm M4.
