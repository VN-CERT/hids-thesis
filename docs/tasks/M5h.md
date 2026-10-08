NHIỆM VỤ M5h — áp bản BPF tối ưu do kiến trúc sư viết, kiểm, rồi đo overhead lần cuối. Lưu nguyên văn vào docs/tasks/M5h.md. Nhiệm vụ này thay cho M5g (chưa chạy).
KHÔNG sửa nội dung bpf/sys_enter.bpf.c (do kiến trúc sư viết). Nếu build hoặc verifier báo lỗi: DỪNG, dán nguyên văn lỗi vào báo cáo.

0. Người dùng đã chép file mới vào bpf/sys_enter.bpf.c (sha256 7618d9c118c89548b6acca9fa2b9e9ab81022707a81f86306c8fcd31f503e47a). Kiểm lại sha256 trước. Commit riêng file này với nội dung "M5h: BPF toi uu (kien truc su)".
1. Sửa nhỏ phía Go, theo đúng cách đang nạp biến hids_self_tgid:
   - hids_filter_pid (kiểu u8): đặt 0 khi KHÔNG có -pid nào; có -pid thì đặt 1.
   - hids_rb_wake_bytes (kiểu u64): đặt bằng kích thước ring buffer tính theo byte, chia 8.
   - Header của file .bin thêm hai dòng: filter_pid và rb_wake_bytes.
   make build; commit; git status phải sạch.
2. Kiểm không hồi quy (từ commit sạch): G7a (tracepoint); G7a với -sys-enter-hook fentry; G7b (24 × 1.000.000); G7b-nho (1 MiB); G3 S1–S5.
   Yêu cầu như cũ: mất = 0 hoặc khớp tuyệt đối; G3 phần dư ≤ 0,5 µs; recursion_misses = 0; bảng đối chiếu với kernel ở cùng mức như bản v3. Không đạt: DỪNG.
3. Đo (dừng container thật; máy không chạy việc nào khác; trong mỗi loại tải, chạy xen kẽ các điều kiện):
   - T1: C0, C1-tracepoint, C1-fentry, C2-tracepoint, C2-fentry; 5 lượt.
   - T4 kịch trần (wrk gốc, như M5f): C0, C1-tracepoint, C1-fentry, C2-tracepoint, C2-fentry; 5 lượt.
   - T3 kịch trần (pgtest với cấu hình chống nhiễu, chạy VACUUM; rồi CHECKPOINT; trước mỗi lượt, như M5f): C0, C1, C2 (tracepoint); 3 lượt.
   - Tải cố định (tracepoint), mức = 25% và 50% của C0 kịch trần ĐO TRONG CHÍNH ĐỢT NÀY: T3-R25, T3-R50, T4-R25, T4-R50 với C0, C1, C2; 3 lượt. Thêm T4-R50 với C2-fentry, 3 lượt.
   - Mọi số độ trễ và tốc độ đọc bằng analysis/m5f_parse.py (không sửa file này). Với kịch trần chỉ dùng cột toc_do_per_s. Ghi CPU của cgroup tải mỗi lượt.
   Lưu vào validation/m5h-<ngày>/.
4. Gắn tag m5h. Viết R022 bằng công cụ sửa file: kết quả bước 2; bảng T1, T4, T3 kịch trần (trung bình ± sd, % so với C0) đặt cạnh số của R021; nguyên văn output m5f_parse.py của tải cố định, kèm CPU của cgroup mỗi lượt. DỪNG.
