NHIỆM VỤ M5b — tối ưu overhead. Lưu nguyên văn vào docs/tasks/M5b.md.
Theo ngưỡng đã chốt: C1 với T3/T4 vượt 10% và C2 vượt 3%, nên bắt buộc tối ưu trước khi thu production.

BƯỚC 1 — CHẨN ĐOÁN TRƯỚC, KHÔNG ĐOÁN. Chạy T3-C1 và T4-C1 mỗi cái một lượt 60 giây, với từng biến thể:
 (a) như R016;
 (b) collector bỏ dữ liệu (đọc ring buffer nhưng không ghi đĩa; thêm cờ -discard) → tách phần do ghi đĩa;
 (c) bật kernel.bpf_stats_enabled=1 TRONG LÚC tải chạy → ns trung bình và số lần chạy mỗi giây của từng chương trình hids_ khi có tải;
 (d) delta của các dòng IWI (irq work) và CAL (function call) trong /proc/interrupts trong lúc chạy → số lần đánh thức và ngắt liên CPU;
 (e) CPU của chính collector (usage_usec của scope).
In bảng so sánh (a)–(e).

BƯỚC 2 — TỐI ƯU (mỗi tối ưu là một commit riêng, để đo được tác dụng của từng cái):
 O1. Ring buffer: bpf_ringbuf_submit với BPF_RB_NO_WAKEUP; collector đọc theo nhịp hẹn giờ (khoảng 10 ms) và đọc vét khi thoát. Đếm mất phải vẫn chính xác.
 O2. Bộ lọc: bỏ vòng duyệt tổ tiên. User space tính trước tập id của MỌI cgroup con cháu của các cgroup đích, nạp vào map; quét lại mỗi giây để bắt cgroup mới. BPF chỉ tra một lần bpf_get_current_cgroup_id() trong tập đó. Giữ nguyên lọc theo tgid.
 O3. Ghi file: nén zstd dạng luồng (mức 1–3) ngay trong collector, ghi theo khối lớn. Đây cũng là một phần của M6b.
 O4. CHỈ khi sau O1–O3 mà C2 vẫn > 3%: thử fentry trên x64_sys_call thay cho tp_btf/sys_enter (kiến trúc sư duyệt làm thử nghiệm; giữ cả hai đường, chọn bằng cờ; báo lại nếu symbol không có).

BƯỚC 3 — KIỂM KHÔNG HỒI QUY (tự chạy, từ commit sạch):
 G7a, G7d: khớp tuyệt đối. G7b-nho (ring buffer 1 MiB): tổng (perf − bản ghi) = bộ đếm mất = seq thiếu. G3 S1–S5: phần dư ≤ 0,5 µs, bảng đối chiếu với kernel như bản v3.

BƯỚC 4 — ĐO LẠI M5 với binary đã tối ưu (đủ ma trận T1–T4 × C0–C3, 5 lượt), thêm hai phép tải cố định:
 T3-R: pgbench -R bằng 50% TPS của T3-C0 → độ trễ trung bình, p99, CPU của cgroup pgtest.
 T4-R: tải HTTP cố định bằng 50% req/s của T4-C0 (tự chọn công cụ hỗ trợ giới hạn tốc độ, ghi rõ lý do) → độ trễ p50, p99, CPU của cgroup nginx.
 Ghi thêm chi phí cộng vào thành phần cpu trên mỗi syscall = (T1-C1 − T1-C0) ns, gọi là "chi phí người quan sát".
 Lưu validation/m5b-<ngày>/.

Kết thúc: gắn tag m5b. Viết R017 bằng công cụ sửa file: bảng chẩn đoán bước 1; tác dụng của từng tối ưu O1–O4; bảng M5 mới đặt cạnh R016; kết quả tải cố định; chi phí người quan sát; in nguyên văn summary.csv. DỪNG.
