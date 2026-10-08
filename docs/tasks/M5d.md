NHIỆM VỤ M5d — lưu nguyên văn vào docs/tasks/M5d.md.
Kiến trúc sư đảo quyết định ở R017: số IWI = 8 khi đó được đo lúc bộ đọc hỏng. R018 cho thấy khoảng 100.000 IWI/giây và CAL thêm khoảng 120.000/giây ở C1, nên O1 là hướng tối ưu chính.

1. Sửa dò stealclock (lỗi thật, ảnh hưởng production):
   - Không phụ thuộc bộ đệm dmesg. Thứ tự: journalctl -k -b; nếu không có thì dùng bằng chứng lúc chạy: chụp vmw_steal_time của mọi CPU hai lần cách nhau 3 giây; giá trị khác 0 trên mọi CPU thì coi là stealclock bật.
   - Ghi rõ nguồn bằng chứng vào header.
   - Từ nay KHÔNG dùng -allow-no-stealclock trong mọi phép đo.

2. O1 làm lại đúng cách:
   - BPF: trước khi nộp, đọc bpf_ringbuf_query(&rb, BPF_RB_AVAIL_DATA). Nếu ≥ 1/8 kích thước ring thì nộp với BPF_RB_FORCE_WAKEUP; ngược lại nộp với BPF_RB_NO_WAKEUP.
   - User-space: trong CHÍNH goroutine đọc, trước mỗi lần ReadInto gọi SetDeadline(now + 10 ms). Gặp os.ErrDeadlineExceeded thì đọc tiếp (không coi là lỗi). Khi thoát: Flush rồi đọc vét.
   - Kiểm: G7a và G7b (64 MiB, 24 triệu bản ghi) phải mất = 0; G7b-nho (1 MiB) phải có (perf − bản ghi) = bộ đếm mất = seq thiếu; G3 S1–S5 phần dư ≤ 0,5 µs. In delta IWI và CAL trước và sau O1.

3. Chi phí BPF khi có tải: bật kernel.bpf_stats_enabled=1; chụp run_time_ns và run_cnt của các chương trình hids_ (bpftool prog show -j, lọc tên) ở ĐẦU và CUỐI cửa sổ đo, khi collector VẪN ĐANG CHẠY. ns trung bình = Δrun_time / Δrun_cnt. Làm cho T3-C1 và cho lúc máy rảnh. Nếu hids_sys_enter khi có tải ≥ 1,5 lần lúc rảnh thì làm O5 (ring buffer riêng cho từng CPU); ngược lại thì không.

4. Đo lại (dừng container thật trong lúc đo; docker start lại khi xong):
   - T1: C0 và C1 trong CÙNG một lượt → chi phí người quan sát.
   - T3, T4 kịch trần: C0, C1, C2, 5 lượt mỗi ô.
   - T3-R, T4-R ở 25% và 50%: C0, C1, C2, 3 lượt mỗi ô. Với MỌI điều kiện: độ trễ trung bình, p99, CPU của cgroup tải.
     · p99 của pgbench: dùng --log, rồi tính từ cột độ trễ trong file log giao dịch.
     · p99 của hey: dùng -o csv rồi tự tính.
   Lưu vào validation/m5d-<ngày>/.

Kết thúc: gắn tag m5d. Viết R019 bằng công cụ sửa file:
- bảng IWI/CAL trước/sau O1;
- bảng chi phí BPF khi có tải và lúc rảnh;
- bảng kịch trần đặt cạnh R016 và R018;
- bảng tải cố định ĐỦ C0, C1, C2 (độ trễ trung bình, p99, CPU);
- chi phí người quan sát;
- in nguyên văn summary.csv. DỪNG.
