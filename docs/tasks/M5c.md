NHIỆM VỤ M5c — lưu nguyên văn vào docs/tasks/M5c.md.
Quyết định cho mục 8 của R017: O1 KHÔNG làm tiếp (IWI chỉ khoảng 8–10, đánh thức không phải nơi tốn); xoá đường NO_WAKEUP và -ringbuf-poll-ms khỏi mã. O4 được DUYỆT làm thử nghiệm.

Chuẩn bị: dừng các container thật trong lúc đo (danh sách ghi vào /root/containers-da-dung.txt), docker start lại khi xong, kể cả khi lỗi giữa chừng.

BƯỚC 1 — chẩn đoán lại với bộ đọc đã sửa. T3 và T4, mỗi biến thể một lượt 60 giây:
 C0: không có collector;
 (a) C1 bình thường (ghi đĩa, nén zstd);
 (b) C1 với -discard;
 (f) C1 ghi ra tmpfs (mount -t tmpfs, kích thước 4 GiB, gỡ khi xong).
Với MỖI biến thể (kể cả C0): throughput; độ trễ trung bình và p99 (với pgbench lấy từ log của chính pgbench); delta các dòng CAL, IWI, RES trong /proc/interrupts; CPU của cgroup tải.
Riêng (a): bật kernel.bpf_stats_enabled=1 trong lúc tải chạy; in ns trung bình và số lần chạy mỗi giây của từng chương trình hids_; so với số đo lúc máy rảnh.
In bảng so sánh. Kỳ vọng (dùng để tìm lỗi, không phải kết luận): nếu đĩa là nguyên nhân thì T3 ở (b) và (f) sẽ phục hồi phần lớn TPS so với (a).

BƯỚC 2 — thử nghiệm (mỗi thử nghiệm một commit, chọn bằng cờ, mặc định giữ đường cũ):
 O4: fentry trên x64_sys_call thay cho tp_btf/sys_enter. Nếu symbol không có hoặc verifier từ chối: báo nguyên văn và bỏ qua.
 O5: CHỈ làm nếu ns trung bình của hids_sys_enter khi có tải ≥ 1,5 lần lúc rảnh. Dùng ring buffer riêng cho từng CPU (BPF_MAP_TYPE_ARRAY_OF_MAPS); seq và đếm mất giữ nguyên ngữ nghĩa.
Mỗi thử nghiệm: chạy T1, T2, T4-C1 (5 lượt), và G7a, G7d, G7b-nho, G3 S1–S5 để kiểm không hồi quy.

BƯỚC 3 — tải cố định, đủ các điều kiện:
 T3-R và T4-R ở 25% và 50% công suất C0; điều kiện C0, C1, C2 (dùng cấu hình tốt nhất sau bước 2); 3 lượt mỗi ô.
 In độ trễ trung bình, p99, và CPU của cgroup tải.

BƯỚC 4 — nếu bước 1 cho thấy đĩa là nguyên nhân: KHÔNG tự xử lý. Ghi vào mục 9 hướng dẫn người dùng thêm một ổ đĩa ảo riêng cho dữ liệu collector trên vCenter; mount và chạy lại T3 sẽ làm ở phiên sau.

Kết thúc: gắn tag m5c. Viết R018 bằng công cụ sửa file: bảng bước 1 (gồm cả C0); tác dụng của O4 và O5; bảng tải cố định; chi phí người quan sát mới; in nguyên văn summary.csv. DỪNG.
