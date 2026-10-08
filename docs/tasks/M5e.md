NHIỆM VỤ M5e — lưu nguyên văn vào docs/tasks/M5e.md. Quyết định cho R019: O5 KHÔNG làm (mục tiêu overhead đã đạt; tỉ số 2,56 so hai đường code khác nhau là bị lọc bỏ và ghi bản ghi, không chứng minh tranh chấp). T3-R CÓ chạy lại.
Dừng container thật trong lúc đo; docker start lại khi xong.

1. Kiểm đường có nén đầu-cuối: G7a với zstd mặc định → giải nén và đếm bằng rec-stat; phải có perf = bản ghi, mất = 0. Thêm một lượt G7b (24 × 1.000.000) với zstd mặc định.
2. Sửa cách tính độ trễ: không đọc phần tóm tắt in ra của công cụ.
   - hey: dùng -o csv, tự tính trung bình, p50, p99, max từ cột thời gian của từng yêu cầu.
   - pgbench: dùng --log, tự tính từ cột độ trễ của từng giao dịch.
   - In kiểm tra hợp lý cho mỗi lượt: trung bình ≤ max và p50 ≤ p99 ≤ max. Lượt nào vi phạm thì đánh dấu, không đưa vào bảng.
3. Chạy lại tải cố định T3-R và T4-R ở 25% và 50%, đủ C0, C1, C2, 3 lượt mỗi ô, theo thứ tự XEN KẼ (C0, C1, C2, C0, C1, C2, …).
4. Chạy lại T4 kịch trần: C0, C1, C2, 7 lượt mỗi điều kiện, thứ tự xen kẽ. In thêm độ lệch chuẩn và khoảng tin cậy 95%.
5. Cập nhật summary; gắn tag m5e. Viết R020 bằng công cụ sửa file:
   - kết quả mục 1;
   - bảng tải cố định có độ trễ trung bình, p50, p99, CPU của cgroup tải cho C0, C1, C2;
   - bảng T4 kịch trần mới;
   - in nguyên văn summary. DỪNG.
